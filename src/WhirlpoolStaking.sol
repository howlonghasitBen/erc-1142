// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ISurfSwap.sol";

/// @title WhirlpoolStaking — LP staking, ownership tracking, and fee distribution
/// @author Whirlpool Team
/// @notice Immutable. No admin. Handles card + WETH staking with MasterChef-style rewards.
/// @dev This contract implements:
///      1. Share-based LP staking (stake card tokens, get proportional shares)
///      2. Dynamic NFT ownership (biggest shareholder = owner, tracked in CardStake.currentOwner)
///      3. Fee distribution via MasterChef accumulators (O(1) gas)
///         - Card swap fees → card stakers
///         - WETH swap fees → WETH stakers
///         - Mint fees → all stakers (weighted by shares + WETH 1.5x boost)
///      4. Effective balance tracking (shares × stakedCards / totalShares)
///      
///      Key mechanic: Staked tokens go into SurfSwap pool as single-sided LP, remaining tradeable.
///      When swaps occur, stakedCards changes → effectiveBalance changes → ownership can shift.
contract WhirlpoolStaking is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constants ───────────────────────────────────────────────
    /// @notice WETH stakers get 1.5x weight in global mint fee distribution (15/10 = 1.5)
    uint256 public constant WETH_BOOST = 15;
    /// @notice Precision for MasterChef accumulators (prevents rounding loss)
    uint256 private constant ACC_PRECISION = 1e18;
    /// @notice Minimum stake amount (placeholder, could be increased for gas efficiency)
    uint256 private constant MIN_STAKE = 1;

    // ─── Immutable refs ─────────────────────────────────────────
    /// @notice WAVES token (reward token for swap fees)
    address public immutable waves;
    /// @notice WETH token (stakeable for boosted rewards)
    address public immutable weth;
    /// @notice SurfSwap AMM (where staked tokens are deposited)
    address public immutable surfSwap;
    /// @notice WhirlpoolRouter (only address that can register cards)
    address public immutable router;

    // ─── Card staking data (LP shares) ──────────────────────────
    /// @notice Per-card staking data
    /// @dev Shares represent proportional ownership of staked liquidity
    ///      effectiveBalance = userShares * stakedCards / totalShares
    ///      currentOwner = address with most shares
    /// @custom:review Share calculation uses stakedCards (not cardReserve) for proportional fairness
    /// @custom:review Ownership tracking updates on every stake, but only checks shares (not effectiveBalance)
    struct CardStake {
        address token;              // Card token address
        uint256 totalShares;        // Total LP shares issued
        uint256 totalStaked;        // Informational (not used in calculations)
        address currentOwner;       // Current NFT owner (biggest shareholder)
        uint256 ownerShares;        // Owner's share count (cached for comparison)
        uint256 accWavesPerShare;   // MasterChef accumulator for card swap fees
    }

    mapping(uint256 => CardStake) public cardStakes;
    mapping(uint256 => mapping(address => uint256)) public userCardShares; // User LP shares
    mapping(uint256 => mapping(address => uint256)) public userCardDebt;

    // ─── WETH staking ───────────────────────────────────────────
    uint256 public totalWethStaked;
    uint256 public accWavesPerWethShare; // MasterChef accumulator for WETH swap fees
    mapping(address => uint256) public userWethStake;
    mapping(address => uint256) public userWethDebt;

    // ─── Global mint fee distribution ───────────────────────────
    uint256 public accEthPerWeight;
    uint256 public totalGlobalWeight;
    mapping(address => uint256) public userGlobalDebt;
    mapping(address => uint256) public userGlobalWeight;

    // ─── Events ─────────────────────────────────────────────────
    event Staked(uint256 indexed cardId, address indexed user, uint256 amount);
    event Unstaked(uint256 indexed cardId, address indexed user, uint256 amount);
    event OwnerChanged(uint256 indexed cardId, address indexed previousOwner, address indexed newOwner);
    event WETHStaked(address indexed user, uint256 amount);
    event WETHUnstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────
    constructor(address waves_, address weth_, address surfSwap_, address router_) {
        waves = waves_;
        weth = weth_;
        surfSwap = surfSwap_;
        router = router_;
    }

    // ═══════════════════════════════════════════════════════════
    //                    CARD STAKING
    // ═══════════════════════════════════════════════════════════

    /// @notice Stake card tokens to earn fees and compete for NFT ownership
    /// @dev Transfers tokens to this contract, then deposits them into SurfSwap as single-sided LP
    ///      Mints LP shares based on: shares = amount * totalShares / currentStakedCards
    ///      First staker gets 1:1 shares (bootstrap), subsequent stakers get proportional shares
    /// @param cardId Card identifier
    /// @param amount Card tokens to stake (must approve first)
    /// @custom:review Share calculation denominator is stakedCards (not cardReserve) for fairness
    function stake(uint256 cardId, uint256 amount) external nonReentrant {
        require(amount >= MIN_STAKE, "Below minimum");
        address token = _getCardToken(cardId);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _stakeInternal(cardId, msg.sender, amount);
    }

    /// @notice Register a new card (called by Router during card creation)
    /// @dev Must be called before autoStake, stores token address for later lookups
    /// @param cardId Card identifier
    /// @param token Card token ERC-20 address
    function registerCard(uint256 cardId, address token) external {
        require(msg.sender == router, "Only router");
        require(cardStakes[cardId].token == address(0), "Card exists");
        cardStakes[cardId].token = token;
    }

    /// @notice Auto-stake tokens for user (called by Router during card creation)
    /// @dev Similar to stake(), but called by Router with user's tokens (minter's 20% allocation)
    ///      This makes the minter the initial owner (first staker gets 1:1 shares)
    /// @param cardId Card identifier
    /// @param user Address receiving the LP shares (card minter)
    /// @param amount Card tokens to auto-stake (20% of supply = 2M tokens)
    function autoStake(uint256 cardId, address user, uint256 amount) external {
        require(msg.sender == router, "Only router");
        address token = cardStakes[cardId].token;
        require(token != address(0), "Card not registered");
        // Transfer tokens from router to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _stakeInternal(cardId, user, amount);
    }

    /// @notice Internal staking logic (called by stake() and autoStake())
    /// @dev Share calculation is the CRITICAL mechanic:
    ///      - First staker: shares = amount (1:1 bootstrap)
    ///      - Subsequent: shares = amount * totalShares / currentStakedCards
    ///      
    ///      currentStakedCards fluctuates with swaps:
    ///      - WAVES → CARD swaps DECREASE stakedCards → existing shares worth less
    ///      - CARD → WAVES swaps INCREASE stakedCards → existing shares worth more (rare)
    ///      
    ///      This creates "active defense" dynamics: swaps erode your position.
    /// @param cardId Card identifier
    /// @param user Address receiving shares
    /// @param amount Card tokens being staked
    /// @custom:review Share calculation denominator is stakedCards (NOT cardReserve) to ensure fair pricing
    /// @custom:review First staker gets advantage of 1:1 shares, but also takes price risk (no market yet)
    function _stakeInternal(uint256 cardId, address user, uint256 amount) internal {
        CardStake storage cs = cardStakes[cardId];

        // Harvest pending card rewards (MasterChef pattern: harvest before changing shares)
        if (userCardShares[cardId][user] > 0) {
            uint256 pending = userCardShares[cardId][user] * cs.accWavesPerShare / ACC_PRECISION - userCardDebt[cardId][user];
            if (pending > 0) {
                IERC20(waves).safeTransfer(user, pending);
            }
        }

        // Harvest global rewards (mint fees)
        _harvestGlobal(user);

        // Calculate LP shares
        // First staker gets 1:1, subsequent stakers get proportional shares
        uint256 sharesToMint;
        if (cs.totalShares == 0) {
            sharesToMint = amount; // Bootstrap: 1:1
        } else {
            // shares = amount * totalShares / currentStakedCards (reflects pool changes from swaps)
            uint256 currentStaked = ISurfSwap(surfSwap).getStakedCards(cardId);
            require(currentStaked > 0, "No staked liquidity");
            sharesToMint = amount * cs.totalShares / currentStaked;
        }
        require(sharesToMint > 0, "Zero shares");

        // Deposit tokens into SurfSwap (increase card reserve)
        address token = _getCardToken(cardId);
        IERC20(token).approve(surfSwap, amount);
        ISurfSwap(surfSwap).addToCardReserve(cardId, amount);

        // Update shares and staked amount
        userCardShares[cardId][user] += sharesToMint;
        cs.totalShares += sharesToMint;
        cs.totalStaked += amount;

        // Update global weight (use shares for weight)
        userGlobalWeight[user] += sharesToMint;
        totalGlobalWeight += sharesToMint;

        // Update debts
        userCardDebt[cardId][user] = userCardShares[cardId][user] * cs.accWavesPerShare / ACC_PRECISION;
        userGlobalDebt[user] = userGlobalWeight[user] * accEthPerWeight / ACC_PRECISION;

        // Check ownership (by shares)
        _updateOwnership(cardId, user);

        emit Staked(cardId, user, amount);
    }

    function unstake(uint256 cardId, uint256 shares) external nonReentrant {
        require(shares > 0, "Zero shares");
        require(userCardShares[cardId][msg.sender] >= shares, "Insufficient shares");

        CardStake storage cs = cardStakes[cardId];

        // Harvest card rewards
        uint256 pending = userCardShares[cardId][msg.sender] * cs.accWavesPerShare / ACC_PRECISION - userCardDebt[cardId][msg.sender];
        if (pending > 0) {
            IERC20(waves).safeTransfer(msg.sender, pending);
        }

        // Harvest global
        _harvestGlobal(msg.sender);

        // Calculate proportional card tokens from staked portion only
        uint256 stakedCards = ISurfSwap(surfSwap).getStakedCards(cardId);
        uint256 cardAmount = shares * stakedCards / cs.totalShares;
        require(cardAmount > 0, "Zero amount");

        // Update shares
        userCardShares[cardId][msg.sender] -= shares;
        cs.totalShares -= shares;

        // Update global weight
        userGlobalWeight[msg.sender] -= shares;
        totalGlobalWeight -= shares;

        // Update debts
        userCardDebt[cardId][msg.sender] = userCardShares[cardId][msg.sender] * cs.accWavesPerShare / ACC_PRECISION;
        userGlobalDebt[msg.sender] = userGlobalWeight[msg.sender] * accEthPerWeight / ACC_PRECISION;

        // Remove tokens from SurfSwap reserve
        ISurfSwap(surfSwap).removeFromCardReserve(cardId, cardAmount);

        // Transfer tokens back
        address token = _getCardToken(cardId);
        IERC20(token).safeTransfer(msg.sender, cardAmount);

        // Check ownership change
        address prevOwner = cs.currentOwner;
        if (msg.sender == prevOwner) {
            if (userCardShares[cardId][msg.sender] > 0) {
                cs.ownerShares = userCardShares[cardId][msg.sender];
            } else {
                cs.currentOwner = address(0);
                cs.ownerShares = 0;
                emit OwnerChanged(cardId, prevOwner, address(0));
            }
        }

        emit Unstaked(cardId, msg.sender, shares);
    }

    function claimRewards(uint256 cardId) external nonReentrant {
        CardStake storage cs = cardStakes[cardId];
        uint256 pending = userCardShares[cardId][msg.sender] * cs.accWavesPerShare / ACC_PRECISION - userCardDebt[cardId][msg.sender];
        if (pending > 0) {
            IERC20(waves).safeTransfer(msg.sender, pending);
        }
        userCardDebt[cardId][msg.sender] = userCardShares[cardId][msg.sender] * cs.accWavesPerShare / ACC_PRECISION;

        _harvestGlobal(msg.sender);
        userGlobalDebt[msg.sender] = userGlobalWeight[msg.sender] * accEthPerWeight / ACC_PRECISION;

        emit RewardsClaimed(msg.sender, pending);
    }

    // ═══════════════════════════════════════════════════════════
    //                    WETH STAKING
    // ═══════════════════════════════════════════════════════════

    function stakeWETH(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");

        IERC20(weth).safeTransferFrom(msg.sender, address(this), amount);

        // Harvest WETH swap rewards
        if (userWethStake[msg.sender] > 0) {
            uint256 pending = userWethStake[msg.sender] * accWavesPerWethShare / ACC_PRECISION - userWethDebt[msg.sender];
            if (pending > 0) {
                IERC20(waves).safeTransfer(msg.sender, pending);
            }
        }

        // Harvest global
        _harvestGlobal(msg.sender);

        userWethStake[msg.sender] += amount;
        totalWethStaked += amount;

        // WETH stakers get 1.5x global weight
        uint256 weightAdded = amount * WETH_BOOST / 10;
        userGlobalWeight[msg.sender] += weightAdded;
        totalGlobalWeight += weightAdded;

        // Transfer WETH to SurfSwap for actual liquidity
        IERC20(weth).approve(surfSwap, amount);
        IERC20(weth).safeTransfer(surfSwap, amount);
        
        // Update reserves in SurfSwap
        ISurfSwap(surfSwap).addToWethReserve(amount);

        userWethDebt[msg.sender] = userWethStake[msg.sender] * accWavesPerWethShare / ACC_PRECISION;
        userGlobalDebt[msg.sender] = userGlobalWeight[msg.sender] * accEthPerWeight / ACC_PRECISION;

        emit WETHStaked(msg.sender, amount);
    }

    function unstakeWETH(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");
        require(userWethStake[msg.sender] >= amount, "Insufficient stake");

        // Harvest WETH swap rewards
        uint256 pending = userWethStake[msg.sender] * accWavesPerWethShare / ACC_PRECISION - userWethDebt[msg.sender];
        if (pending > 0) {
            IERC20(waves).safeTransfer(msg.sender, pending);
        }

        // Harvest global
        _harvestGlobal(msg.sender);

        userWethStake[msg.sender] -= amount;
        totalWethStaked -= amount;

        uint256 weightRemoved = amount * WETH_BOOST / 10;
        userGlobalWeight[msg.sender] -= weightRemoved;
        totalGlobalWeight -= weightRemoved;

        // Update virtual reserves in SurfSwap
        ISurfSwap(surfSwap).removeFromWethReserve(amount);

        userWethDebt[msg.sender] = userWethStake[msg.sender] * accWavesPerWethShare / ACC_PRECISION;
        userGlobalDebt[msg.sender] = userGlobalWeight[msg.sender] * accEthPerWeight / ACC_PRECISION;

        IERC20(weth).safeTransfer(msg.sender, amount);

        emit WETHUnstaked(msg.sender, amount);
    }

    function claimWETHRewards() external nonReentrant {
        uint256 pending = userWethStake[msg.sender] * accWavesPerWethShare / ACC_PRECISION - userWethDebt[msg.sender];
        if (pending > 0) {
            IERC20(waves).safeTransfer(msg.sender, pending);
        }
        userWethDebt[msg.sender] = userWethStake[msg.sender] * accWavesPerWethShare / ACC_PRECISION;

        _harvestGlobal(msg.sender);
        userGlobalDebt[msg.sender] = userGlobalWeight[msg.sender] * accEthPerWeight / ACC_PRECISION;

        emit RewardsClaimed(msg.sender, pending);
    }

    // ═══════════════════════════════════════════════════════════
    //                    FEE DISTRIBUTION
    // ═══════════════════════════════════════════════════════════

    function distributeMintFee() external payable {
        require(msg.sender == router, "Only router");
        if (totalGlobalWeight > 0) {
            accEthPerWeight += msg.value * ACC_PRECISION / totalGlobalWeight;
        }
    }

    function distributeSwapFees(uint256 cardId, uint256 wavesFee) external {
        require(msg.sender == surfSwap, "Only SurfSwap");
        CardStake storage cs = cardStakes[cardId];
        if (cs.totalShares > 0 && wavesFee > 0) {
            cs.accWavesPerShare += wavesFee * ACC_PRECISION / cs.totalShares;
        }
    }

    function distributeWethSwapFees(uint256 wavesFee) external {
        require(msg.sender == surfSwap, "Only SurfSwap");
        if (totalWethStaked > 0 && wavesFee > 0) {
            accWavesPerWethShare += wavesFee * ACC_PRECISION / totalWethStaked;
        }
    }

    // ═══════════════════════════════════════════════════════════
    //                    INTERNAL
    // ═══════════════════════════════════════════════════════════

    function _harvestGlobal(address user) internal {
        if (userGlobalWeight[user] > 0) {
            uint256 pending = userGlobalWeight[user] * accEthPerWeight / ACC_PRECISION - userGlobalDebt[user];
            if (pending > 0) {
                (bool ok, ) = user.call{value: pending}("");
                require(ok, "ETH transfer failed");
            }
        }
    }

    /// @notice Update NFT ownership based on share count
    /// @dev Ownership is determined by SHARES, not effectiveBalance:
    ///      - Compares userShares vs ownerShares
    ///      - If user has more shares → user becomes owner
    ///      - Emits OwnerChanged event (triggers BidNFT.ownerOf() update)
    ///      
    ///      Note: Uses shares (not effectiveBalance) because:
    ///      - Cheaper (no external call to SurfSwap)
    ///      - Simpler logic (direct comparison)
    ///      - Still fair (shares represent proportional ownership)
    /// @param cardId Card identifier
    /// @param user Address that just staked
    /// @custom:review Ownership tracked by shares, not effectiveBalance (both are valid metrics)
    function _updateOwnership(uint256 cardId, address user) internal {
        CardStake storage cs = cardStakes[cardId];
        uint256 userShares = userCardShares[cardId][user];

        if (userShares > cs.ownerShares) {
            address prevOwner = cs.currentOwner;
            cs.currentOwner = user;
            cs.ownerShares = userShares;
            if (prevOwner != user) {
                emit OwnerChanged(cardId, prevOwner, user);
            }
        } else if (user == cs.currentOwner) {
            cs.ownerShares = userShares;
        }
    }

    function _getCardToken(uint256 cardId) internal view returns (address) {
        address token = cardStakes[cardId].token;
        require(token != address(0), "Card does not exist");
        return token;
    }

    // ═══════════════════════════════════════════════════════════
    //                       VIEWS
    // ═══════════════════════════════════════════════════════════

    function ownerOfCard(uint256 cardId) external view returns (address) {
        return cardStakes[cardId].currentOwner;
    }

    /// @notice Returns user's LP shares for a card
    function stakeOf(uint256 cardId, address user) external view returns (uint256) {
        return userCardShares[cardId][user];
    }

    /// @notice Returns the actual card token amount represented by user's shares
    function effectiveBalance(uint256 cardId, address user) external view returns (uint256) {
        uint256 shares = userCardShares[cardId][user];
        if (shares == 0) return 0;
        
        CardStake storage cs = cardStakes[cardId];
        if (cs.totalShares == 0) return 0;
        
        uint256 stakedCards = ISurfSwap(surfSwap).getStakedCards(cardId);
        return shares * stakedCards / cs.totalShares;
    }

    function pendingRewards(uint256 cardId, address user) external view returns (uint256) {
        CardStake storage cs = cardStakes[cardId];
        if (userCardShares[cardId][user] == 0) return 0;
        return userCardShares[cardId][user] * cs.accWavesPerShare / ACC_PRECISION - userCardDebt[cardId][user];
    }

    function pendingGlobalRewards(address user) external view returns (uint256) {
        if (userGlobalWeight[user] == 0) return 0;
        return userGlobalWeight[user] * accEthPerWeight / ACC_PRECISION - userGlobalDebt[user];
    }

    // Allow receiving ETH
    receive() external payable {}
}
