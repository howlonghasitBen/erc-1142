// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IWhirlpool.sol";

/// @title SurfSwap — Constant product AMM with multi-route support
/// @notice Immutable. Handles all swap logic and liquidity reserves.
contract SurfSwap is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constants ───────────────────────────────────────────────
    uint256 public constant SWAP_FEE_BPS = 30; // 0.3%
    uint256 private constant BPS = 10000;

    // ─── Immutable refs ─────────────────────────────────────────
    address public immutable waves;
    address public immutable weth;
    address public immutable whirlpool;
    address public immutable router;

    // ─── Pool reserves ──────────────────────────────────────────
    struct CardPool {
        address token;
        uint256 wavesReserve;
        uint256 cardReserve;
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

    function initializePool(uint256 cardId, address token, uint256 wavesAmount, uint256 cardAmount) external {
        require(msg.sender == router, "Only router");
        require(cards[cardId].token == address(0), "Pool exists");

        // Transfer tokens into this contract
        IERC20(waves).safeTransferFrom(msg.sender, address(this), wavesAmount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), cardAmount);

        cards[cardId] = CardPool({
            token: token,
            wavesReserve: wavesAmount,
            cardReserve: cardAmount
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

    function _swapCardToWaves(address cardAddr, uint256 amountIn) internal returns (uint256 amountOut) {
        uint256 cardId = tokenToCard[cardAddr];
        CardPool storage pool = cards[cardId];

        uint256 fee = amountIn * SWAP_FEE_BPS / BPS;
        uint256 amountInAfterFee = amountIn - fee;

        // Constant product: x * y = k
        uint256 newCardReserve = pool.cardReserve + amountInAfterFee;
        uint256 grossOut = pool.wavesReserve - (pool.wavesReserve * pool.cardReserve) / newCardReserve;
        
        // Take fee from output
        uint256 waveFee = grossOut * SWAP_FEE_BPS / BPS;
        amountOut = grossOut - waveFee;

        pool.cardReserve = newCardReserve + fee; // fee stays in reserve
        pool.wavesReserve -= grossOut;

        // Transfer fee to Whirlpool for distribution
        if (waveFee > 0) {
            IERC20(waves).safeTransfer(whirlpool, waveFee);
            IWhirlpool(whirlpool).distributeSwapFees(cardId, waveFee);
        }
    }

    function _swapWavesToCard(address cardAddr, uint256 amountIn) internal returns (uint256 amountOut) {
        uint256 cardId = tokenToCard[cardAddr];
        CardPool storage pool = cards[cardId];

        uint256 fee = amountIn * SWAP_FEE_BPS / BPS;
        uint256 amountInAfterFee = amountIn - fee;

        uint256 newWavesReserve = pool.wavesReserve + amountInAfterFee;
        amountOut = pool.cardReserve - (pool.wavesReserve * pool.cardReserve) / newWavesReserve;

        pool.wavesReserve = newWavesReserve;
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
    //                    CARD RESERVE UPDATES (LP STAKING)
    // ═══════════════════════════════════════════════════════════

    function addToCardReserve(uint256 cardId, uint256 amount) external {
        require(msg.sender == whirlpool, "Only Whirlpool");
        CardPool storage pool = cards[cardId];
        require(pool.token != address(0), "Pool not initialized");
        pool.cardReserve += amount;
    }

    function removeFromCardReserve(uint256 cardId, uint256 amount) external {
        require(msg.sender == whirlpool, "Only Whirlpool");
        CardPool storage pool = cards[cardId];
        require(pool.cardReserve >= amount, "Insufficient reserve");
        pool.cardReserve -= amount;
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

    function getPrice(uint256 cardId) external view returns (uint256) {
        CardPool storage pool = cards[cardId];
        if (pool.cardReserve == 0) return 0;
        return pool.wavesReserve * 1e18 / pool.cardReserve;
    }

    function getReserves(uint256 cardId) external view returns (uint256 wavesR, uint256 cardsR) {
        CardPool storage pool = cards[cardId];
        return (pool.wavesReserve, pool.cardReserve);
    }

    function getWethReserves() external view returns (uint256 wavesR, uint256 wethR) {
        return (wavesWethReserve, wethReserve);
    }
}
