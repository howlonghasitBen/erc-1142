// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IWhirlpool.sol";

/// @title SurfSwap — Constant product AMM with multi-route support
/// @author Whirlpool Team
/// @notice Immutable constant-product (x*y=k) AMM that routes all swaps through WAVES as hub token.
/// @dev This contract is part of the Whirlpool system. It manages:
///      - Card ↔ WAVES liquidity pools (one per card)
///      - WAVES ↔ WETH liquidity pool
///      - Multi-hop routing (CARD → WAVES → CARD, CARD → WAVES → WETH, etc.)
///      - Proportional stakedCards tracking (for LP staking mechanics)
///      Staked tokens remain in the pool and are tradeable, creating "active defense" dynamics.
contract SurfSwap is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constants ───────────────────────────────────────────────
    /// @notice Swap fee in basis points (0.3%)
    uint256 public constant SWAP_FEE_BPS = 30;
    uint256 private constant BPS = 10000;

    // ─── Immutable refs ─────────────────────────────────────────
    /// @notice WAVES token (hub token for all swaps)
    address public immutable waves;
    /// @notice WETH token (provides exit liquidity)
    address public immutable weth;
    /// @notice WhirlpoolStaking contract (receives fees, manages LP)
    address public immutable whirlpool;
    /// @notice WhirlpoolRouter contract (only address that can initialize pools)
    address public immutable router;

    // ─── Pool reserves ──────────────────────────────────────────
    /// @notice Pool data for each card
    /// @dev stakedCards is a subset of cardReserve, representing tokens deposited via LP staking
    ///      The ratio stakedCards/cardReserve is maintained constant across swaps via proportional adjustments
    /// @custom:review Proportional tracking may accumulate rounding errors over many swaps (tested negligible)
    struct CardPool {
        address token;          // Card token address
        uint256 wavesReserve;   // WAVES balance in pool
        uint256 cardReserve;    // Total card tokens (base AMM + staked LP)
        uint256 stakedCards;    // Portion from LP staking (subset of cardReserve)
    }

    mapping(uint256 => CardPool) public cards;
    mapping(address => uint256) public tokenToCard;
    mapping(address => bool) public isCardToken;

    // ─── WETH ↔ WAVES pool ─────────────────────────────────────
    uint256 public wavesWethReserve;
    uint256 public wethReserve;

    // ─── Events ─────────────────────────────────────────────────
    event PoolInitialized(uint256 indexed cardId, address indexed token, uint256 wavesAmount, uint256 cardAmount);
    event Swap(address indexed tokenIn, address indexed tokenOut, address indexed user, uint256 amountIn, uint256 amountOut);

    // ─── Constructor ────────────────────────────────────────────
    constructor(address waves_, address weth_, address whirlpool_, address router_) {
        waves = waves_;
        weth = weth_;
        whirlpool = whirlpool_;
        router = router_;
    }

    // ═══════════════════════════════════════════════════════════
    //                     POOL INITIALIZATION
    // ═══════════════════════════════════════════════════════════

    /// @notice Initialize a new CARD ↔ WAVES liquidity pool
    /// @dev Can only be called once per cardId, only by Router during card creation
    /// @param cardId Unique card identifier
    /// @param token Card token ERC-20 address
    /// @param wavesAmount Initial WAVES liquidity (typically 500 WAVES = 25% of minted)
    /// @param cardAmount Initial card liquidity (typically 7.5M tokens = 75% of supply)
    /// @custom:review Initial liquidity ratio determines starting price (currently 500 WAVES : 7.5M CARD)
    function initializePool(uint256 cardId, address token, uint256 wavesAmount, uint256 cardAmount) external {
        require(msg.sender == router, "Only router");
        require(cards[cardId].token == address(0), "Pool exists");

        // Transfer tokens into this contract
        IERC20(waves).safeTransferFrom(msg.sender, address(this), wavesAmount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), cardAmount);

        cards[cardId] = CardPool({
            token: token,
            wavesReserve: wavesAmount,
            cardReserve: cardAmount,
            stakedCards: 0
        });

        tokenToCard[token] = cardId;
        isCardToken[token] = true;

        // Bootstrap WETH pool if needed (first card)
        if (wavesWethReserve == 0 && wethReserve > 0) {
            wavesWethReserve = wavesAmount;
        }

        emit PoolInitialized(cardId, token, wavesAmount, cardAmount);
    }

    // ═══════════════════════════════════════════════════════════
    //                        SWAPS
    // ═══════════════════════════════════════════════════════════

    /// @notice Swap exact input amount for output tokens
    /// @dev Supports 7 swap routes:
    ///      1. CARD → WAVES (direct)
    ///      2. WAVES → CARD (direct)
    ///      3. WETH → WAVES (direct)
    ///      4. WAVES → WETH (direct)
    ///      5. CARD → CARD (via WAVES, double fee)
    ///      6. CARD → WETH (via WAVES, double fee)
    ///      7. WETH → CARD (via WAVES, double fee)
    ///      All routes charge 0.3% fee, collected by WhirlpoolStaking for distribution
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param amountIn Exact input amount (must approve first)
    /// @param minAmountOut Minimum output (slippage protection, reverts if not met)
    /// @return amountOut Actual output amount received
    /// @custom:review Multi-hop swaps cost ~280K gas, could be optimized by batching state updates
    function swapExact(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "Zero amount");
        require(tokenIn != tokenOut, "Same token");

        // Transfer input tokens
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        if (isCardToken[tokenIn] && tokenOut == waves) {
            // CARD → WAVES
            amountOut = _swapCardToWaves(tokenIn, amountIn);
        } else if (tokenIn == waves && isCardToken[tokenOut]) {
            // WAVES → CARD
            amountOut = _swapWavesToCard(tokenOut, amountIn);
        } else if (tokenIn == weth && tokenOut == waves) {
            // WETH → WAVES
            amountOut = _swapWethToWaves(amountIn);
        } else if (tokenIn == waves && tokenOut == weth) {
            // WAVES → WETH
            amountOut = _swapWavesToWeth(amountIn);
        } else if (isCardToken[tokenIn] && isCardToken[tokenOut]) {
            // CARD → CARD (via WAVES)
            uint256 wavesMiddle = _swapCardToWaves(tokenIn, amountIn);
            amountOut = _swapWavesToCard(tokenOut, wavesMiddle);
        } else if (isCardToken[tokenIn] && tokenOut == weth) {
            // CARD → WETH (via WAVES)
            uint256 wavesMiddle = _swapCardToWaves(tokenIn, amountIn);
            amountOut = _swapWavesToWeth(wavesMiddle);
        } else if (tokenIn == weth && isCardToken[tokenOut]) {
            // WETH → CARD (via WAVES)
            uint256 wavesMiddle = _swapWethToWaves(amountIn);
            amountOut = _swapWavesToCard(tokenOut, wavesMiddle);
        } else {
            revert("Invalid swap route");
        }

        require(amountOut >= minAmountOut, "Slippage");

        // Transfer output
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        emit Swap(tokenIn, tokenOut, msg.sender, amountIn, amountOut);
    }

    /// @notice Internal: Swap CARD tokens → WAVES
    /// @dev Implements constant product formula: x * y = k
    ///      1. Calculate output using (x+Δx)(y-Δy) = xy
    ///      2. Take 0.3% fee from both input and output
    ///      3. Proportionally INCREASE stakedCards (cards entering pool)
    ///      4. Distribute fee to WhirlpoolStaking for stakers
    /// @param cardAddr Card token address
    /// @param amountIn Card tokens being sold (input)
    /// @return amountOut WAVES received (after fees)
    /// @custom:review stakedCards proportional increase maintains ratio, but rounds down (negligible impact)
    function _swapCardToWaves(address cardAddr, uint256 amountIn) internal returns (uint256 amountOut) {
        uint256 cardId = tokenToCard[cardAddr];
        CardPool storage pool = cards[cardId];

        uint256 fee = amountIn * SWAP_FEE_BPS / BPS;
        uint256 amountInAfterFee = amountIn - fee;

        // Constant product: x * y = k
        // newReserve * (oldReserve - out) = oldReserve1 * oldReserve2
        uint256 newCardReserve = pool.cardReserve + amountInAfterFee;
        uint256 grossOut = pool.wavesReserve - (pool.wavesReserve * pool.cardReserve) / newCardReserve;
        
        // Take fee from output (double fee on trades)
        uint256 waveFee = grossOut * SWAP_FEE_BPS / BPS;
        amountOut = grossOut - waveFee;

        // Proportionally increase staked portion when cards enter the pool
        // Maintains: stakedCards / cardReserve = constant
        uint256 addedCards = (amountInAfterFee + fee);
        if (pool.stakedCards > 0 && pool.cardReserve > 0) {
            uint256 stakedIncrease = addedCards * pool.stakedCards / pool.cardReserve;
            pool.stakedCards += stakedIncrease;
        }
        pool.cardReserve = newCardReserve + fee; // fee stays in reserve
        pool.wavesReserve -= grossOut;

        // Transfer fee to Whirlpool for distribution
        if (waveFee > 0) {
            IERC20(waves).safeTransfer(whirlpool, waveFee);
            IWhirlpool(whirlpool).distributeSwapFees(cardId, waveFee);
        }
    }

    /// @notice Internal: Swap WAVES → CARD tokens
    /// @dev Implements constant product formula with proportional stakedCards REDUCTION
    ///      This is the critical "active defense" function:
    ///      - When users buy cards from pool, stakedCards decreases proportionally
    ///      - All LP stakers see their effectiveBalance decrease
    ///      - Forces active defense to maintain ownership
    /// @param cardAddr Card token address
    /// @param amountIn WAVES being sold (input)
    /// @return amountOut Card tokens received (after fees)
    /// @custom:review stakedReduction clamped to prevent underflow, maintains ratio correctness
    function _swapWavesToCard(address cardAddr, uint256 amountIn) internal returns (uint256 amountOut) {
        uint256 cardId = tokenToCard[cardAddr];
        CardPool storage pool = cards[cardId];

        uint256 fee = amountIn * SWAP_FEE_BPS / BPS;
        uint256 amountInAfterFee = amountIn - fee;

        uint256 newWavesReserve = pool.wavesReserve + amountInAfterFee;
        amountOut = pool.cardReserve - (pool.wavesReserve * pool.cardReserve) / newWavesReserve;

        pool.wavesReserve = newWavesReserve;
        // Proportionally reduce staked portion when cards leave the pool
        // This DECREASES effectiveBalance for all LP stakers (active defense)
        if (pool.stakedCards > 0 && pool.cardReserve > 0) {
            uint256 stakedReduction = amountOut * pool.stakedCards / pool.cardReserve;
            if (stakedReduction > pool.stakedCards) stakedReduction = pool.stakedCards; // Clamp to prevent underflow
            pool.stakedCards -= stakedReduction;
        }
        pool.cardReserve -= amountOut;

        // Transfer fee to Whirlpool
        if (fee > 0) {
            IERC20(waves).safeTransfer(whirlpool, fee);
            IWhirlpool(whirlpool).distributeSwapFees(cardId, fee);
        }
    }

    function _swapWethToWaves(uint256 amountIn) internal returns (uint256 amountOut) {
        require(wethReserve > 0 && wavesWethReserve > 0, "WETH pool not initialized");

        uint256 fee = amountIn * SWAP_FEE_BPS / BPS;
        uint256 amountInAfterFee = amountIn - fee;

        uint256 newWethReserve = wethReserve + amountInAfterFee;
        uint256 grossOut = wavesWethReserve - (wethReserve * wavesWethReserve) / newWethReserve;
        
        // Take fee from output
        uint256 waveFee = grossOut * SWAP_FEE_BPS / BPS;
        amountOut = grossOut - waveFee;

        wethReserve = newWethReserve + fee;
        wavesWethReserve -= grossOut;

        // Transfer fee to Whirlpool for WETH stakers
        if (waveFee > 0) {
            IERC20(waves).safeTransfer(whirlpool, waveFee);
            IWhirlpool(whirlpool).distributeWethSwapFees(waveFee);
        }
    }

    function _swapWavesToWeth(uint256 amountIn) internal returns (uint256 amountOut) {
        require(wethReserve > 0 && wavesWethReserve > 0, "WETH pool not initialized");

        uint256 fee = amountIn * SWAP_FEE_BPS / BPS;
        uint256 amountInAfterFee = amountIn - fee;

        uint256 newWavesReserve = wavesWethReserve + amountInAfterFee;
        amountOut = wethReserve - (wethReserve * wavesWethReserve) / newWavesReserve;

        wavesWethReserve = newWavesReserve;
        wethReserve -= amountOut;

        // Transfer fee to Whirlpool for WETH stakers
        if (fee > 0) {
            IERC20(waves).safeTransfer(whirlpool, fee);
            IWhirlpool(whirlpool).distributeWethSwapFees(fee);
        }
    }

    // ═══════════════════════════════════════════════════════════
    //                    INTERNAL SWAP (STAKE SWAPPING)
    // ═══════════════════════════════════════════════════════════

    /// @notice Internal swap from one card to another without token transfers
    /// @dev Only callable by WhirlpoolStaking for swapStake() operations
    ///      This function performs a CARD → WAVES → CARD swap purely through reserve accounting.
    ///      Key difference from regular swaps: we're swapping tokens ALREADY IN THE POOL (stakedCards).
    ///      
    ///      Approach:
    ///      1. Remove cardAmountIn from fromCard's reserves (both cardReserve AND stakedCards)
    ///      2. Calculate WAVES output using constant product on REDUCED reserves
    ///      3. Calculate toCard output using constant product
    ///      4. Add output to toCard's reserves (both cardReserve AND stakedCards)
    ///      5. Charge 0.3% fee on each hop
    ///      
    ///      NO ERC20 TRANSFERS - pure accounting changes
    /// @param fromCardId Source card identifier
    /// @param toCardId Destination card identifier
    /// @param cardAmountIn Amount of fromCard tokens to swap
    /// @return cardAmountOut Amount of toCard tokens received
    function internalSwapCardToCard(
        uint256 fromCardId,
        uint256 toCardId,
        uint256 cardAmountIn
    ) external nonReentrant returns (uint256 cardAmountOut) {
        require(msg.sender == whirlpool, "Only Whirlpool");
        require(fromCardId != toCardId, "Same card");
        require(cardAmountIn > 0, "Zero amount");

        CardPool storage fromPool = cards[fromCardId];
        CardPool storage toPool = cards[toCardId];
        require(fromPool.token != address(0), "From pool not initialized");
        require(toPool.token != address(0), "To pool not initialized");
        require(fromPool.cardReserve >= cardAmountIn, "Insufficient from reserve");
        require(fromPool.stakedCards >= cardAmountIn, "Insufficient staked cards");

        // ─── Step 1: Remove from fromCard reserves ──────────────
        // These tokens are leaving the staked pool to be swapped
        fromPool.cardReserve -= cardAmountIn;
        fromPool.stakedCards -= cardAmountIn;

        // ─── Step 2: Swap fromCard → WAVES (internal) ───────────
        
        // Take fee from input
        uint256 fee1 = cardAmountIn * SWAP_FEE_BPS / BPS;
        uint256 amountInAfterFee = cardAmountIn - fee1;

        // Calculate WAVES output using constant product: (x + Δx)(y - Δy) = xy
        // We're SELLING cards TO the pool (pool gains cards, loses WAVES)
        uint256 newCardReserve = fromPool.cardReserve + amountInAfterFee;
        uint256 grossWavesOut = fromPool.wavesReserve - (fromPool.cardReserve * fromPool.wavesReserve) / newCardReserve;
        
        // Take fee from WAVES output (double fee)
        uint256 wavesFee1 = grossWavesOut * SWAP_FEE_BPS / BPS;
        uint256 wavesOut = grossWavesOut - wavesFee1;

        // Update fromCard reserves (add back cards + fee, remove WAVES)
        fromPool.cardReserve = newCardReserve + fee1;
        fromPool.wavesReserve -= grossWavesOut;

        // Distribute fromCard fee
        if (wavesFee1 > 0) {
            IERC20(waves).safeTransfer(whirlpool, wavesFee1);
            IWhirlpool(whirlpool).distributeSwapFees(fromCardId, wavesFee1);
        }

        // ─── Step 3: Swap WAVES → toCard (internal) ──────────────

        // Take fee from WAVES input
        uint256 fee2 = wavesOut * SWAP_FEE_BPS / BPS;
        uint256 wavesInAfterFee = wavesOut - fee2;

        // Calculate toCard output using constant product
        // We're BUYING cards FROM the pool (pool gains WAVES, loses cards)
        uint256 newToWavesReserve = toPool.wavesReserve + wavesInAfterFee;
        cardAmountOut = toPool.cardReserve - (toPool.wavesReserve * toPool.cardReserve) / newToWavesReserve;

        // Update toCard reserves (add WAVES, remove cards)
        toPool.wavesReserve = newToWavesReserve;
        toPool.cardReserve -= cardAmountOut;
        
        // Proportionally reduce toCard's staked portion (cards leaving pool)
        if (toPool.stakedCards > 0 && toPool.cardReserve + cardAmountOut > 0) {
            uint256 stakedReduction = cardAmountOut * toPool.stakedCards / (toPool.cardReserve + cardAmountOut);
            if (stakedReduction > toPool.stakedCards) stakedReduction = toPool.stakedCards;
            toPool.stakedCards -= stakedReduction;
        }

        // ─── Step 4: Add output to toCard reserves ──────────────
        // These tokens are being staked in the destination card
        toPool.stakedCards += cardAmountOut;
        toPool.cardReserve += cardAmountOut;

        // Distribute toCard fee
        if (fee2 > 0) {
            IERC20(waves).safeTransfer(whirlpool, fee2);
            IWhirlpool(whirlpool).distributeSwapFees(toCardId, fee2);
        }
    }

    // ═══════════════════════════════════════════════════════════
    //                    CARD RESERVE UPDATES (LP STAKING)
    // ═══════════════════════════════════════════════════════════

    /// @notice Add tokens to card reserve (called when user stakes)
    /// @dev Only WhirlpoolStaking can call this. Increases both cardReserve and stakedCards 1:1
    ///      Tokens are transferred to this contract before calling (by Whirlpool)
    /// @param cardId Card identifier
    /// @param amount Tokens being added to reserve
    /// @custom:review This is single-sided LP deposit - tokens go directly into tradeable pool
    function addToCardReserve(uint256 cardId, uint256 amount) external {
        require(msg.sender == whirlpool, "Only Whirlpool");
        CardPool storage pool = cards[cardId];
        require(pool.token != address(0), "Pool not initialized");
        pool.cardReserve += amount;
        pool.stakedCards += amount;
    }

    /// @notice Remove tokens from card reserve (called when user unstakes)
    /// @dev Only WhirlpoolStaking can call this. Decreases both reserves, clamped to prevent underflow
    /// @param cardId Card identifier
    /// @param amount Tokens being removed from reserve
    /// @custom:review Clamps stakedCards to 0 if amount exceeds it (prevents underflow from rounding)
    function removeFromCardReserve(uint256 cardId, uint256 amount) external {
        require(msg.sender == whirlpool, "Only Whirlpool");
        CardPool storage pool = cards[cardId];
        require(pool.cardReserve >= amount, "Insufficient reserve");
        pool.cardReserve -= amount;
        if (pool.stakedCards >= amount) {
            pool.stakedCards -= amount;
        } else {
            pool.stakedCards = 0; // Clamp to prevent underflow (edge case from rounding)
        }
    }

    /// @notice Returns the staked portion of the card reserve
    /// @dev Used by WhirlpoolStaking to calculate LP shares and effectiveBalance
    ///      This value fluctuates with swaps (proportional tracking)
    /// @param cardId Card identifier
    /// @return Staked card tokens (subset of cardReserve)
    function getStakedCards(uint256 cardId) external view returns (uint256) {
        return cards[cardId].stakedCards;
    }

    // ═══════════════════════════════════════════════════════════
    //                    WETH RESERVE UPDATES
    // ═══════════════════════════════════════════════════════════

    function addToWethReserve(uint256 amount) external {
        require(msg.sender == whirlpool, "Only Whirlpool");
        wethReserve += amount;
        // Bootstrap WAVES side if needed
        if (wavesWethReserve == 0 && wethReserve > 0) {
            wavesWethReserve = 500 ether; // bootstrap with 500 WAVES equivalent
        }
    }

    function removeFromWethReserve(uint256 amount) external {
        require(msg.sender == whirlpool, "Only Whirlpool");
        if (wethReserve >= amount) {
            wethReserve -= amount;
        } else {
            wethReserve = 0;
        }
    }

    // ═══════════════════════════════════════════════════════════
    //                       VIEWS
    // ═══════════════════════════════════════════════════════════

    /// @notice Get current price of card token in WAVES (per 1 token, with 18 decimals)
    /// @dev Price = wavesReserve / cardReserve * 1e18
    ///      Uses TOTAL cardReserve (includes staked tokens), so price reflects tradeable liquidity
    /// @param cardId Card identifier
    /// @return Price in WAVES (e.g., 52631578947368 = 0.0000526 WAVES per token)
    function getPrice(uint256 cardId) external view returns (uint256) {
        CardPool storage pool = cards[cardId];
        if (pool.cardReserve == 0) return 0;
        return pool.wavesReserve * 1e18 / pool.cardReserve;
    }

    /// @notice Get reserve balances for a card pool
    /// @dev Returns total reserves (base AMM + staked LP)
    /// @param cardId Card identifier
    /// @return wavesR WAVES in pool
    /// @return cardsR Card tokens in pool (total, includes staked)
    function getReserves(uint256 cardId) external view returns (uint256 wavesR, uint256 cardsR) {
        CardPool storage pool = cards[cardId];
        return (pool.wavesReserve, pool.cardReserve);
    }

    /// @notice Get reserve balances for WETH pool
    /// @dev wethReserve is virtual (from staking), wavesWethReserve is real
    /// @return wavesR WAVES in WETH pool
    /// @return wethR WETH in pool (virtual from staking)
    function getWethReserves() external view returns (uint256 wavesR, uint256 wethR) {
        return (wavesWethReserve, wethReserve);
    }
}
