// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ISurfSwap.sol";
import "./interfaces/IGlobalRewards.sol";

/// @title CardStaking — LP staking, ownership tracking, and card-specific fee distribution
/// @author Whirlpool Team
/// @notice Handles card token staking with share-based LP, dynamic NFT ownership, and swap fee rewards.
/// @dev Staked tokens go into SurfSwap pool as single-sided LP, remaining tradeable.
///      When swaps occur, stakedCards changes → effectiveBalance changes → ownership can shift.
///      Global weight is managed via GlobalRewards contract.
contract CardStaking is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant ACC_PRECISION = 1e18;
    uint256 private constant MIN_STAKE = 1;

    // ─── Immutable refs ─────────────────────────────────────────
    address public immutable waves;
    address public immutable surfSwap;
    address public immutable router;
    IGlobalRewards public immutable globalRewards;

    // ─── Card staking data ──────────────────────────────────────
    struct CardStake {
        address token;
        uint256 totalShares;
        uint256 totalStaked;
        address currentOwner;
        uint256 ownerShares;
        uint256 accWavesPerShare;
    }

    mapping(uint256 => CardStake) public cardStakes;
    mapping(uint256 => mapping(address => uint256)) public userCardShares;
    mapping(uint256 => mapping(address => uint256)) public userCardDebt;
    mapping(uint256 => address[]) public cardStakers;
    mapping(uint256 => mapping(address => bool)) public isCardStaker;

    // ─── Events ─────────────────────────────────────────────────
    event Staked(uint256 indexed cardId, address indexed user, uint256 amount);
    event Unstaked(uint256 indexed cardId, address indexed user, uint256 amount);
    event OwnerChanged(uint256 indexed cardId, address indexed previousOwner, address indexed newOwner);

    constructor(address _waves, address _surfSwap, address _router, address _globalRewards) {
        waves = _waves;
        surfSwap = _surfSwap;
        router = _router;
        globalRewards = IGlobalRewards(_globalRewards);
    }

    // ═══════════════════════════════════════════════════════════
    //                    STAKING
    // ═══════════════════════════════════════════════════════════

    /// @notice Stake card tokens to earn fees and compete for NFT ownership
    function stake(uint256 cardId, uint256 amount) external nonReentrant {
        require(amount >= MIN_STAKE, "Below minimum stake");
        address token = _getCardToken(cardId);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _stakeInternal(cardId, msg.sender, amount);
    }

    /// @notice Register a new card (called by Router during card creation)
    function registerCard(uint256 cardId, address token) external {
        require(msg.sender == router, "Only router");
        cardStakes[cardId].token = token;
    }

    /// @notice Auto-stake tokens for user (called by Router during card creation)
    function autoStake(uint256 cardId, address user, uint256 amount) external {
        require(msg.sender == router, "Only router");
        address token = cardStakes[cardId].token;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _stakeInternal(cardId, user, amount);
    }

    /// @notice Internal staking logic
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
        globalRewards.harvestGlobal(user);

        // Calculate LP shares
        uint256 sharesToMint;
        if (cs.totalShares == 0) {
            sharesToMint = amount;
        } else {
            uint256 currentStaked = ISurfSwap(surfSwap).getStakedCards(cardId);
            require(currentStaked > 0, "No staked liquidity");
            sharesToMint = amount * cs.totalShares / currentStaked;
        }
        require(sharesToMint > 0, "Zero shares");

        // Deposit tokens into SurfSwap
        address token = _getCardToken(cardId);
        IERC20(token).approve(surfSwap, amount);
        ISurfSwap(surfSwap).addToCardReserve(cardId, amount);

        // Update shares
        userCardShares[cardId][user] += sharesToMint;
        cs.totalShares += sharesToMint;
        cs.totalStaked += amount;

        // Update global weight
        globalRewards.addWeight(user, sharesToMint);

        // Update debts
        userCardDebt[cardId][user] = userCardShares[cardId][user] * cs.accWavesPerShare / ACC_PRECISION;

        // Track staker
        if (!isCardStaker[cardId][user]) {
            isCardStaker[cardId][user] = true;
            cardStakers[cardId].push(user);
        }

        // Check ownership
        _updateOwnership(cardId, user);

        emit Staked(cardId, user, amount);
    }

    // ═══════════════════════════════════════════════════════════
    //                    UNSTAKING
    // ═══════════════════════════════════════════════════════════

    /// @notice Unstake LP shares and withdraw proportional card tokens
    function unstake(uint256 cardId, uint256 shares) external nonReentrant {
        require(shares > 0, "Zero shares");
        CardStake storage cs = cardStakes[cardId];
        require(userCardShares[cardId][msg.sender] >= shares, "Insufficient shares");

        // Calculate card token amount from shares
        uint256 currentStaked = ISurfSwap(surfSwap).getStakedCards(cardId);
        uint256 cardAmount = shares * currentStaked / cs.totalShares;

        // Harvest pending card rewards
        uint256 pending = userCardShares[cardId][msg.sender] * cs.accWavesPerShare / ACC_PRECISION - userCardDebt[cardId][msg.sender];
        if (pending > 0) {
            IERC20(waves).safeTransfer(msg.sender, pending);
        }

        // Harvest global rewards
        globalRewards.harvestGlobal(msg.sender);

        // Update shares
        userCardShares[cardId][msg.sender] -= shares;
        cs.totalShares -= shares;

        // Update global weight
        globalRewards.removeWeight(msg.sender, shares);

        // Update debt
        userCardDebt[cardId][msg.sender] = userCardShares[cardId][msg.sender] * cs.accWavesPerShare / ACC_PRECISION;

        // Remove tokens from SurfSwap
        ISurfSwap(surfSwap).removeFromCardReserve(cardId, cardAmount);

        // Transfer tokens back
        address token = _getCardToken(cardId);
        IERC20(token).safeTransfer(msg.sender, cardAmount);

        // Check ownership — scan for new largest staker
        if (msg.sender == cs.currentOwner) {
            _findNewOwner(cardId, msg.sender);
        }

        emit Unstaked(cardId, msg.sender, shares);
    }

    // ═══════════════════════════════════════════════════════════
    //                    SWAP STAKING
    // ═══════════════════════════════════════════════════════════

    /// @notice Swap staked position from one card to another atomically
    function swapStake(uint256 fromCardId, uint256 toCardId, uint256 shares) external nonReentrant {
        require(shares > 0, "Zero shares");
        require(fromCardId != toCardId, "Same card");
        CardStake storage fromCs = cardStakes[fromCardId];
        CardStake storage toCs = cardStakes[toCardId];
        require(userCardShares[fromCardId][msg.sender] >= shares, "Insufficient shares");

        // Calculate card amount from shares
        uint256 currentFromStaked = ISurfSwap(surfSwap).getStakedCards(fromCardId);
        uint256 cardAmountIn = shares * currentFromStaked / fromCs.totalShares;

        // Harvest from-card rewards
        uint256 pendingFrom = userCardShares[fromCardId][msg.sender] * fromCs.accWavesPerShare / ACC_PRECISION - userCardDebt[fromCardId][msg.sender];
        if (pendingFrom > 0) {
            IERC20(waves).safeTransfer(msg.sender, pendingFrom);
        }

        // Harvest to-card rewards
        if (userCardShares[toCardId][msg.sender] > 0) {
            uint256 pendingTo = userCardShares[toCardId][msg.sender] * toCs.accWavesPerShare / ACC_PRECISION - userCardDebt[toCardId][msg.sender];
            if (pendingTo > 0) {
                IERC20(waves).safeTransfer(msg.sender, pendingTo);
            }
        }

        // Harvest global
        globalRewards.harvestGlobal(msg.sender);

        // Burn from-card shares
        userCardShares[fromCardId][msg.sender] -= shares;
        fromCs.totalShares -= shares;

        // Internal swap via SurfSwap
        uint256 cardAmountOut = ISurfSwap(surfSwap).internalSwapCardToCard(fromCardId, toCardId, cardAmountIn);

        // Mint to-card shares
        uint256 sharesToMint;
        uint256 currentToStaked = ISurfSwap(surfSwap).getStakedCards(toCardId);
        if (toCs.totalShares == 0) {
            sharesToMint = cardAmountOut;
        } else {
            uint256 preSwapStaked = currentToStaked - cardAmountOut;
            require(preSwapStaked > 0, "No staked liquidity in target");
            sharesToMint = cardAmountOut * toCs.totalShares / preSwapStaked;
        }
        require(sharesToMint > 0, "Zero shares from swap");

        userCardShares[toCardId][msg.sender] += sharesToMint;
        toCs.totalShares += sharesToMint;

        // Update global weight: remove old, add new
        globalRewards.removeWeight(msg.sender, shares);
        globalRewards.addWeight(msg.sender, sharesToMint);

        // Update debts
        userCardDebt[fromCardId][msg.sender] = userCardShares[fromCardId][msg.sender] * fromCs.accWavesPerShare / ACC_PRECISION;
        userCardDebt[toCardId][msg.sender] = userCardShares[toCardId][msg.sender] * toCs.accWavesPerShare / ACC_PRECISION;

        // Track staker for toCard
        if (!isCardStaker[toCardId][msg.sender]) {
            isCardStaker[toCardId][msg.sender] = true;
            cardStakers[toCardId].push(msg.sender);
        }

        // Update ownership
        if (msg.sender == fromCs.currentOwner) {
            _findNewOwner(fromCardId, msg.sender);
        }
        _updateOwnership(toCardId, msg.sender);

        emit Unstaked(fromCardId, msg.sender, shares);
        emit Staked(toCardId, msg.sender, sharesToMint);
    }

    /// @notice Batch swap stake from multiple cards into one target card atomically
    function batchSwapStake(uint256[] calldata fromCardIds, uint256 toCardId) external nonReentrant {
        require(fromCardIds.length > 0, "Empty array");
        CardStake storage toCs = cardStakes[toCardId];

        // Harvest to-card rewards
        if (userCardShares[toCardId][msg.sender] > 0) {
            uint256 pendingTo = userCardShares[toCardId][msg.sender] * toCs.accWavesPerShare / ACC_PRECISION - userCardDebt[toCardId][msg.sender];
            if (pendingTo > 0) {
                IERC20(waves).safeTransfer(msg.sender, pendingTo);
            }
        }

        // Harvest global once
        globalRewards.harvestGlobal(msg.sender);

        uint256 totalSharesToMintForTo;
        uint256 totalGlobalWeightRemoved;

        for (uint256 i = 0; i < fromCardIds.length; i++) {
            uint256 fromCardId = fromCardIds[i];
            require(fromCardId != toCardId, "Cannot swap to self");
            CardStake storage fromCs = cardStakes[fromCardId];
            uint256 shares = userCardShares[fromCardId][msg.sender];
            require(shares > 0, "No shares in source card");

            // Harvest from-card rewards
            uint256 pendingFrom = shares * fromCs.accWavesPerShare / ACC_PRECISION - userCardDebt[fromCardId][msg.sender];
            if (pendingFrom > 0) {
                IERC20(waves).safeTransfer(msg.sender, pendingFrom);
            }

            // Calculate card amount
            uint256 currentFromStaked = ISurfSwap(surfSwap).getStakedCards(fromCardId);
            uint256 cardAmountIn = shares * currentFromStaked / fromCs.totalShares;

            // Burn from shares
            userCardShares[fromCardId][msg.sender] = 0;
            fromCs.totalShares -= shares;
            userCardDebt[fromCardId][msg.sender] = 0;
            totalGlobalWeightRemoved += shares;

            // Internal swap
            uint256 cardAmountOut = ISurfSwap(surfSwap).internalSwapCardToCard(fromCardId, toCardId, cardAmountIn);

            // Calculate to-card shares
            uint256 sharesToMint;
            uint256 currentToStaked = ISurfSwap(surfSwap).getStakedCards(toCardId);
            if (toCs.totalShares == 0 && totalSharesToMintForTo == 0) {
                sharesToMint = cardAmountOut;
            } else {
                uint256 preSwapStaked = currentToStaked - cardAmountOut;
                require(preSwapStaked > 0, "No staked liquidity in target");
                sharesToMint = cardAmountOut * (toCs.totalShares + totalSharesToMintForTo) / preSwapStaked;
            }
            require(sharesToMint > 0, "Zero shares");

            totalSharesToMintForTo += sharesToMint;

            // Update fromCard ownership
            if (msg.sender == fromCs.currentOwner) {
                _findNewOwner(fromCardId, msg.sender);
            }

            emit Unstaked(fromCardId, msg.sender, shares);
        }

        // Mint all toCard shares at once
        userCardShares[toCardId][msg.sender] += totalSharesToMintForTo;
        toCs.totalShares += totalSharesToMintForTo;

        // Track staker
        if (!isCardStaker[toCardId][msg.sender]) {
            isCardStaker[toCardId][msg.sender] = true;
            cardStakers[toCardId].push(msg.sender);
        }

        // Update global weight
        globalRewards.removeWeight(msg.sender, totalGlobalWeightRemoved);
        globalRewards.addWeight(msg.sender, totalSharesToMintForTo);

        // Update debts
        userCardDebt[toCardId][msg.sender] = userCardShares[toCardId][msg.sender] * toCs.accWavesPerShare / ACC_PRECISION;

        // Update toCard ownership
        _updateOwnership(toCardId, msg.sender);

        emit Staked(toCardId, msg.sender, totalSharesToMintForTo);
    }

    // ═══════════════════════════════════════════════════════════
    //                    REWARDS
    // ═══════════════════════════════════════════════════════════

    /// @notice Claim pending WAVES rewards from card-specific swap fees and global mint fees
    function claimRewards(uint256 cardId) external nonReentrant {
        CardStake storage cs = cardStakes[cardId];
        uint256 pending = userCardShares[cardId][msg.sender] * cs.accWavesPerShare / ACC_PRECISION - userCardDebt[cardId][msg.sender];
        if (pending > 0) {
            IERC20(waves).safeTransfer(msg.sender, pending);
        }
        userCardDebt[cardId][msg.sender] = userCardShares[cardId][msg.sender] * cs.accWavesPerShare / ACC_PRECISION;

        // Also harvest global
        globalRewards.harvestGlobal(msg.sender);
    }

    // ═══════════════════════════════════════════════════════════
    //                    FEE DISTRIBUTION
    // ═══════════════════════════════════════════════════════════

    /// @notice Distribute WAVES swap fees to card-specific LP stakers
    function distributeSwapFees(uint256 cardId, uint256 wavesFee) external {
        require(msg.sender == surfSwap, "Only SurfSwap");
        CardStake storage cs = cardStakes[cardId];
        if (cs.totalShares > 0 && wavesFee > 0) {
            cs.accWavesPerShare += wavesFee * ACC_PRECISION / cs.totalShares;
        }
    }

    // ═══════════════════════════════════════════════════════════
    //                    INTERNAL
    // ═══════════════════════════════════════════════════════════

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

    function _findNewOwner(uint256 cardId, address prevOwner) internal {
        CardStake storage cs = cardStakes[cardId];
        address bestAddr = address(0);
        uint256 bestShares = 0;
        address[] storage stakers = cardStakers[cardId];
        for (uint256 i = 0; i < stakers.length; i++) {
            uint256 s = userCardShares[cardId][stakers[i]];
            if (s > bestShares) {
                bestShares = s;
                bestAddr = stakers[i];
            }
        }
        if (bestAddr != cs.currentOwner) {
            cs.currentOwner = bestAddr;
            cs.ownerShares = bestShares;
            emit OwnerChanged(cardId, prevOwner, bestAddr);
        } else {
            cs.ownerShares = bestShares;
        }
    }

    function _getCardToken(uint256 cardId) internal view returns (address) {
        address token = cardStakes[cardId].token;
        require(token != address(0), "Card does not exist");
        return token;
    }

    // ═══════════════════════════════════════════════════════════
    //                    VIEWS
    // ═══════════════════════════════════════════════════════════

    /// @notice Get the current NFT owner (biggest LP shareholder) for a card
    function ownerOfCard(uint256 cardId) external view returns (address) {
        return cardStakes[cardId].currentOwner;
    }

    /// @notice Get effective balance (shares × stakedCards / totalShares)
    function effectiveBalance(uint256 cardId, address user) external view returns (uint256) {
        CardStake storage cs = cardStakes[cardId];
        if (cs.totalShares == 0) return 0;
        uint256 currentStaked = ISurfSwap(surfSwap).getStakedCards(cardId);
        return userCardShares[cardId][user] * currentStaked / cs.totalShares;
    }

    /// @notice Get pending WAVES rewards from card-specific swap fees
    function pendingRewards(uint256 cardId, address user) external view returns (uint256) {
        CardStake storage cs = cardStakes[cardId];
        if (userCardShares[cardId][user] == 0) return 0;
        return userCardShares[cardId][user] * cs.accWavesPerShare / ACC_PRECISION - userCardDebt[cardId][user];
    }
}
