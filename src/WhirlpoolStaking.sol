// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ISurfSwap.sol";

/// @title WhirlpoolStaking — All staking, ownership tracking, and fee distribution
/// @notice Immutable. No admin. Handles card + WETH staking with MasterChef-style rewards.
contract WhirlpoolStaking is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constants ───────────────────────────────────────────────
    uint256 public constant WETH_BOOST = 15; // 1.5x = 15/10
    uint256 private constant ACC_PRECISION = 1e18;
    uint256 private constant MIN_STAKE = 1;

    // ─── Immutable refs ─────────────────────────────────────────
    address public immutable waves;
    address public immutable weth;
    address public immutable surfSwap;
    address public immutable router;

    // ─── Card staking data (LP shares) ──────────────────────────
    struct CardStake {
        address token;
        uint256 totalShares;       // Total LP shares issued
        uint256 totalStaked;       // Total card tokens staked (tracked separately from pool reserve)
        address currentOwner;
        uint256 ownerShares;       // Shares held by current owner
        uint256 accWavesPerShare;  // MasterChef accumulator for card-specific rewards
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

    function stake(uint256 cardId, uint256 amount) external nonReentrant {
        require(amount >= MIN_STAKE, "Below minimum");
        address token = _getCardToken(cardId);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _stakeInternal(cardId, msg.sender, amount);
    }

    function registerCard(uint256 cardId, address token) external {
        require(msg.sender == router, "Only router");
        require(cardStakes[cardId].token == address(0), "Card exists");
        cardStakes[cardId].token = token;
    }

    function autoStake(uint256 cardId, address user, uint256 amount) external {
        require(msg.sender == router, "Only router");
        address token = cardStakes[cardId].token;
        require(token != address(0), "Card not registered");
        // Transfer tokens from router to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _stakeInternal(cardId, user, amount);
    }

    function _stakeInternal(uint256 cardId, address user, uint256 amount) internal {
        CardStake storage cs = cardStakes[cardId];

        // Harvest pending card rewards
        if (userCardShares[cardId][user] > 0) {
            uint256 pending = userCardShares[cardId][user] * cs.accWavesPerShare / ACC_PRECISION - userCardDebt[cardId][user];
            if (pending > 0) {
                IERC20(waves).safeTransfer(user, pending);
            }
        }

        // Harvest global rewards
        _harvestGlobal(user);

        // Calculate LP shares
        // First staker gets 1:1, subsequent stakers get proportional shares
        uint256 sharesToMint;
        if (cs.totalShares == 0) {
            sharesToMint = amount; // Bootstrap: 1:1
        } else {
            // shares = amount * totalShares / totalStaked
            sharesToMint = amount * cs.totalShares / cs.totalStaked;
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

        // Calculate proportional card tokens from current reserve
        (uint256 wavesR, uint256 cardR) = ISurfSwap(surfSwap).getReserves(cardId);
        uint256 cardAmount = shares * cardR / cs.totalShares;
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

        // Update virtual reserves in SurfSwap
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
        
        (, uint256 cardR) = ISurfSwap(surfSwap).getReserves(cardId);
        return shares * cardR / cs.totalShares;
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
