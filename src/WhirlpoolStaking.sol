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

    /// @notice Unstake LP shares and withdraw proportional card tokens
    /// @dev Harvests pending card + global rewards before modifying shares.
    ///      Withdrawal amount = shares × stakedCards / totalShares (proportional to current staked liquidity).
    ///      If user was NFT owner and unstakes all shares, ownership clears to address(0).
    /// @param cardId Card identifier
    /// @param shares Number of LP shares to burn
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

    /// @notice Swap staked position from one card to another atomically
    /// @dev This is the key innovation: swap without unstaking/re-staking
    ///      Process:
    ///      1. Calculate card tokens represented by user's fromCard shares
    ///      2. Harvest pending rewards (must do before changing shares)
    ///      3. Burn user's fromCard shares
    ///      4. Call SurfSwap.internalSwapCardToCard (pure reserve math, no token transfers)
    ///      5. Mint new toCard shares based on output amount
    ///      6. Update ownership for both cards
    ///      7. Update global weight tracking
    ///      
    ///      Benefits:
    ///      - Single transaction (vs 3 separate txns)
    ///      - No token approvals needed
    ///      - Lower gas cost
    ///      - No slippage from token transfers
    /// @param fromCardId Source card identifier
    /// @param toCardId Destination card identifier  
    /// @param shares Amount of fromCard shares to swap
    function swapStake(
        uint256 fromCardId,
        uint256 toCardId,
        uint256 shares
    ) external nonReentrant {
        require(shares > 0, "Zero shares");
        require(fromCardId != toCardId, "Same card");
        require(userCardShares[fromCardId][msg.sender] >= shares, "Insufficient shares");

        CardStake storage fromCs = cardStakes[fromCardId];
        CardStake storage toCs = cardStakes[toCardId];

        // Harvest all pending rewards FIRST (before changing shares)
        // Harvest fromCard rewards
        if (userCardShares[fromCardId][msg.sender] > 0) {
            uint256 pendingFrom = userCardShares[fromCardId][msg.sender] * fromCs.accWavesPerShare / ACC_PRECISION - userCardDebt[fromCardId][msg.sender];
            if (pendingFrom > 0) {
                IERC20(waves).safeTransfer(msg.sender, pendingFrom);
            }
        }

        // Harvest toCard rewards (if user already has stake there)
        if (userCardShares[toCardId][msg.sender] > 0) {
            uint256 pendingTo = userCardShares[toCardId][msg.sender] * toCs.accWavesPerShare / ACC_PRECISION - userCardDebt[toCardId][msg.sender];
            if (pendingTo > 0) {
                IERC20(waves).safeTransfer(msg.sender, pendingTo);
            }
        }

        // Harvest global rewards
        _harvestGlobal(msg.sender);

        // Calculate card amount represented by shares
        uint256 stakedCards = ISurfSwap(surfSwap).getStakedCards(fromCardId);
        uint256 cardAmountIn = shares * stakedCards / fromCs.totalShares;
        require(cardAmountIn > 0, "Zero amount");

        // Burn fromCard shares
        userCardShares[fromCardId][msg.sender] -= shares;
        fromCs.totalShares -= shares;

        // Update global weight (remove fromCard weight)
        userGlobalWeight[msg.sender] -= shares;
        totalGlobalWeight -= shares;

        // Perform internal swap (no token transfers, pure reserve math)
        uint256 cardAmountOut = ISurfSwap(surfSwap).internalSwapCardToCard(
            fromCardId,
            toCardId,
            cardAmountIn
        );
        require(cardAmountOut > 0, "Zero output");

        // Calculate toCard shares to mint
        uint256 sharesToMint;
        if (toCs.totalShares == 0) {
            // Bootstrap case: first staker gets 1:1
            sharesToMint = cardAmountOut;
        } else {
            // Proportional shares based on new stakedCards amount
            uint256 currentToStaked = ISurfSwap(surfSwap).getStakedCards(toCardId);
            require(currentToStaked > 0, "No staked liquidity in target");
            sharesToMint = cardAmountOut * toCs.totalShares / currentToStaked;
        }
        require(sharesToMint > 0, "Zero shares minted");

        // Mint toCard shares
        userCardShares[toCardId][msg.sender] += sharesToMint;
        toCs.totalShares += sharesToMint;

        // Update global weight (add toCard weight)
        userGlobalWeight[msg.sender] += sharesToMint;
        totalGlobalWeight += sharesToMint;

        // Update debts for both cards
        userCardDebt[fromCardId][msg.sender] = userCardShares[fromCardId][msg.sender] * fromCs.accWavesPerShare / ACC_PRECISION;
        userCardDebt[toCardId][msg.sender] = userCardShares[toCardId][msg.sender] * toCs.accWavesPerShare / ACC_PRECISION;
        userGlobalDebt[msg.sender] = userGlobalWeight[msg.sender] * accEthPerWeight / ACC_PRECISION;

        // Update ownership for fromCard (check if user was owner)
        address prevFromOwner = fromCs.currentOwner;
        if (msg.sender == prevFromOwner) {
            if (userCardShares[fromCardId][msg.sender] > 0) {
                // User still has shares, update ownerShares
                fromCs.ownerShares = userCardShares[fromCardId][msg.sender];
            } else {
                // User has no shares left, clear ownership
                fromCs.currentOwner = address(0);
                fromCs.ownerShares = 0;
                emit OwnerChanged(fromCardId, prevFromOwner, address(0));
            }
        }

        // Update ownership for toCard (user might become owner)
        _updateOwnership(toCardId, msg.sender);

        // Emit events
        emit Unstaked(fromCardId, msg.sender, shares);
        emit Staked(toCardId, msg.sender, sharesToMint);
    }

    /// @notice Batch swap stake from multiple cards into one target card atomically
    /// @dev Consolidates positions from N source cards into 1 target card in a single tx.
    ///      Gas optimization: harvests rewards and updates global weight once (not N times).
    ///      Each source card is fully unstaked via internalSwapCardToCard.
    ///      All resulting toCard shares are minted in sequence.
    /// @param fromCardIds Array of source card identifiers (user's full stake is swapped from each)
    /// @param toCardId Destination card identifier
    function batchSwapStake(
        uint256[] calldata fromCardIds,
        uint256 toCardId
    ) external nonReentrant {
        require(fromCardIds.length > 0, "Empty array");

        CardStake storage toCs = cardStakes[toCardId];

        // Harvest toCard rewards once (before any share changes)
        if (userCardShares[toCardId][msg.sender] > 0) {
            uint256 pendingTo = userCardShares[toCardId][msg.sender] * toCs.accWavesPerShare / ACC_PRECISION - userCardDebt[toCardId][msg.sender];
            if (pendingTo > 0) {
                IERC20(waves).safeTransfer(msg.sender, pendingTo);
            }
        }

        // Harvest global rewards once
        _harvestGlobal(msg.sender);

        uint256 totalSharesToMintForTo = 0;
        uint256 totalGlobalWeightRemoved = 0;

        for (uint256 i = 0; i < fromCardIds.length; i++) {
            uint256 fromCardId = fromCardIds[i];
            require(fromCardId != toCardId, "Same card");

            uint256 shares = userCardShares[fromCardId][msg.sender];
            require(shares > 0, "No stake in card");

            CardStake storage fromCs = cardStakes[fromCardId];

            // Harvest fromCard rewards
            uint256 pendingFrom = shares * fromCs.accWavesPerShare / ACC_PRECISION - userCardDebt[fromCardId][msg.sender];
            if (pendingFrom > 0) {
                IERC20(waves).safeTransfer(msg.sender, pendingFrom);
            }

            // Calculate card amount from shares
            uint256 stakedCards = ISurfSwap(surfSwap).getStakedCards(fromCardId);
            uint256 cardAmountIn = shares * stakedCards / fromCs.totalShares;
            require(cardAmountIn > 0, "Zero amount");

            // Burn fromCard shares
            userCardShares[fromCardId][msg.sender] = 0;
            fromCs.totalShares -= shares;
            totalGlobalWeightRemoved += shares;

            // Update fromCard debt
            userCardDebt[fromCardId][msg.sender] = 0;

            // Swap via AMM
            uint256 cardAmountOut = ISurfSwap(surfSwap).internalSwapCardToCard(
                fromCardId,
                toCardId,
                cardAmountIn
            );
            require(cardAmountOut > 0, "Zero output");

            // Calculate toCard shares to mint
            uint256 sharesToMint;
            if (toCs.totalShares + totalSharesToMintForTo == 0) {
                sharesToMint = cardAmountOut;
            } else {
                uint256 currentToStaked = ISurfSwap(surfSwap).getStakedCards(toCardId);
                require(currentToStaked > 0, "No staked liquidity in target");
                sharesToMint = cardAmountOut * (toCs.totalShares + totalSharesToMintForTo) / currentToStaked;
            }
            require(sharesToMint > 0, "Zero shares minted");

            totalSharesToMintForTo += sharesToMint;

            // Update fromCard ownership
            address prevFromOwner = fromCs.currentOwner;
            if (msg.sender == prevFromOwner) {
                fromCs.currentOwner = address(0);
                fromCs.ownerShares = 0;
                emit OwnerChanged(fromCardId, prevFromOwner, address(0));
            }

            emit Unstaked(fromCardId, msg.sender, shares);
        }

        // Mint all toCard shares at once
        userCardShares[toCardId][msg.sender] += totalSharesToMintForTo;
        toCs.totalShares += totalSharesToMintForTo;

        // Update global weight: remove old, add new
        userGlobalWeight[msg.sender] = userGlobalWeight[msg.sender] - totalGlobalWeightRemoved + totalSharesToMintForTo;
        totalGlobalWeight = totalGlobalWeight - totalGlobalWeightRemoved + totalSharesToMintForTo;

        // Update debts
        userCardDebt[toCardId][msg.sender] = userCardShares[toCardId][msg.sender] * toCs.accWavesPerShare / ACC_PRECISION;
        userGlobalDebt[msg.sender] = userGlobalWeight[msg.sender] * accEthPerWeight / ACC_PRECISION;

        // Update toCard ownership
        _updateOwnership(toCardId, msg.sender);

        emit Staked(toCardId, msg.sender, totalSharesToMintForTo);
    }

    /// @notice Claim pending WAVES rewards from card-specific swap fees and global mint fees
    /// @dev Harvests both card accumulator and global (ETH) accumulator in one call
    /// @param cardId Card identifier to claim swap fee rewards from
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

    /// @notice Stake WETH to earn swap fees and 1.5x boosted global mint fee rewards
    /// @dev WETH is transferred to SurfSwap as virtual liquidity for the WAVES ↔ WETH pool.
    ///      WETH stakers receive 1.5x weight in global mint fee distribution.
    ///      Harvests any pending WETH + global rewards before modifying stake.
    /// @param amount WETH to stake (must approve WhirlpoolStaking first)
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

    /// @notice Unstake WETH and withdraw from the WAVES ↔ WETH pool
    /// @dev Harvests pending WETH swap + global rewards before modifying stake.
    ///      Removes WETH from SurfSwap virtual reserve and transfers back to user.
    /// @param amount WETH to unstake
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

    /// @notice Claim pending WAVES rewards from WETH swap fees and global mint fees
    /// @dev Harvests both WETH swap fee accumulator and global (ETH) accumulator
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

    /// @notice Distribute ETH mint fee to all stakers (card LP + WETH) weighted by global weight
    /// @dev Only callable by Router during card creation. Uses MasterChef accumulator pattern.
    ///      Weight = card LP shares (1x) + WETH staked (1.5x)
    function distributeMintFee() external payable {
        require(msg.sender == router, "Only router");
        if (totalGlobalWeight > 0) {
            accEthPerWeight += msg.value * ACC_PRECISION / totalGlobalWeight;
        }
    }

    /// @notice Distribute WAVES swap fees to card-specific LP stakers
    /// @dev Only callable by SurfSwap during swaps. Increments per-share accumulator.
    /// @param cardId Card identifier whose stakers receive the fee
    /// @param wavesFee WAVES fee amount to distribute
    function distributeSwapFees(uint256 cardId, uint256 wavesFee) external {
        require(msg.sender == surfSwap, "Only SurfSwap");
        CardStake storage cs = cardStakes[cardId];
        if (cs.totalShares > 0 && wavesFee > 0) {
            cs.accWavesPerShare += wavesFee * ACC_PRECISION / cs.totalShares;
        }
    }

    /// @notice Distribute WAVES swap fees to WETH stakers
    /// @dev Only callable by SurfSwap during WETH ↔ WAVES swaps
    /// @param wavesFee WAVES fee amount to distribute
    function distributeWethSwapFees(uint256 wavesFee) external {
        require(msg.sender == surfSwap, "Only SurfSwap");
        if (totalWethStaked > 0 && wavesFee > 0) {
            accWavesPerWethShare += wavesFee * ACC_PRECISION / totalWethStaked;
        }
    }

    // ═══════════════════════════════════════════════════════════
    //                    INTERNAL
    // ═══════════════════════════════════════════════════════════

    /// @notice Harvest pending ETH from global mint fee distribution
    /// @dev Calculates pending = weight × accEthPerWeight - debt, sends ETH via low-level call
    /// @param user Address to harvest for
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

    /// @notice Get the current NFT owner (biggest LP shareholder) for a card
    /// @param cardId Card identifier
    /// @return Address of current owner (address(0) if no stakers)
    function ownerOfCard(uint256 cardId) external view returns (address) {
        return cardStakes[cardId].currentOwner;
    }

    /// @notice Returns user's LP shares for a card
    /// @param cardId Card identifier
    /// @param user Address to query
    /// @return Number of LP shares held by user
    function stakeOf(uint256 cardId, address user) external view returns (uint256) {
        return userCardShares[cardId][user];
    }

    /// @notice Returns the actual card token amount represented by user's shares
    /// @dev effectiveBalance = userShares × stakedCards / totalShares
    ///      This value fluctuates as swaps affect stakedCards
    /// @param cardId Card identifier
    /// @param user Address to query
    /// @return Token amount (may be less than originally staked due to swap erosion)
    function effectiveBalance(uint256 cardId, address user) external view returns (uint256) {
        uint256 shares = userCardShares[cardId][user];
        if (shares == 0) return 0;
        
        CardStake storage cs = cardStakes[cardId];
        if (cs.totalShares == 0) return 0;
        
        uint256 stakedCards = ISurfSwap(surfSwap).getStakedCards(cardId);
        return shares * stakedCards / cs.totalShares;
    }

    /// @notice Get pending WAVES rewards from card-specific swap fees
    /// @param cardId Card identifier
    /// @param user Address to query
    /// @return Pending WAVES reward amount (claimable via claimRewards)
    function pendingRewards(uint256 cardId, address user) external view returns (uint256) {
        CardStake storage cs = cardStakes[cardId];
        if (userCardShares[cardId][user] == 0) return 0;
        return userCardShares[cardId][user] * cs.accWavesPerShare / ACC_PRECISION - userCardDebt[cardId][user];
    }

    /// @notice Get pending ETH rewards from global mint fee distribution
    /// @param user Address to query
    /// @return Pending ETH reward amount (claimable via claimRewards or claimWETHRewards)
    function pendingGlobalRewards(address user) external view returns (uint256) {
        if (userGlobalWeight[user] == 0) return 0;
        return userGlobalWeight[user] * accEthPerWeight / ACC_PRECISION - userGlobalDebt[user];
    }

    // Allow receiving ETH
    receive() external payable {}
}
