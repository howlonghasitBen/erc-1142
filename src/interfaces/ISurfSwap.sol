// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ISurfSwap — Interface for the SurfSwap constant-product AMM
/// @notice Defines pool initialization, swaps, reserve management, and view functions
interface ISurfSwap {
    /// @notice Initialize a new CARD ↔ WAVES liquidity pool
    /// @param cardId Unique card identifier
    /// @param token Card token ERC-20 address
    /// @param wavesAmount Initial WAVES liquidity
    /// @param cardAmount Initial card token liquidity
    function initializePool(uint256 cardId, address token, uint256 wavesAmount, uint256 cardAmount) external;

    /// @notice Swap exact input for output tokens (supports multi-route via WAVES hub)
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param amountIn Exact input amount
    /// @param minOut Minimum output (slippage protection)
    /// @return amountOut Actual output amount
    function swapExact(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256 amountOut);

    /// @notice Add card tokens to pool reserve (called by WhirlpoolStaking on stake)
    /// @param cardId Card identifier
    /// @param amount Tokens to add
    function addToCardReserve(uint256 cardId, uint256 amount) external;

    /// @notice Remove card tokens from pool reserve (called by WhirlpoolStaking on unstake)
    /// @param cardId Card identifier
    /// @param amount Tokens to remove
    function removeFromCardReserve(uint256 cardId, uint256 amount) external;

    /// @notice Add WETH to the WETH ↔ WAVES pool reserve
    /// @param amount WETH to add
    function addToWethReserve(uint256 amount) external;

    /// @notice Remove WETH from the WETH ↔ WAVES pool reserve
    /// @param amount WETH to remove
    function removeFromWethReserve(uint256 amount) external;

    /// @notice Remove WAVES from the WETH ↔ WAVES pool reserve (proportional LP withdrawal)
    /// @param amount WAVES to remove
    function removeFromWavesWethReserve(uint256 amount) external;

    /// @notice Get current price of card token in WAVES (per 1 token, 18 decimals)
    /// @param cardId Card identifier
    /// @return Price in WAVES
    function getPrice(uint256 cardId) external view returns (uint256);

    /// @notice Get reserve balances for a card pool
    /// @param cardId Card identifier
    /// @return wavesR WAVES in pool
    /// @return cardsR Card tokens in pool
    function getReserves(uint256 cardId) external view returns (uint256 wavesR, uint256 cardsR);

    /// @notice Get reserve balances for WETH ↔ WAVES pool
    /// @return wavesR WAVES in pool
    /// @return wethR WETH in pool
    function getWethReserves() external view returns (uint256 wavesR, uint256 wethR);

    /// @notice Check if an address is a registered card token
    /// @param token Address to check
    /// @return True if registered card token
    function isCardToken(address token) external view returns (bool);

    /// @notice Get the card ID for a given token address
    /// @param token Card token address
    /// @return Card identifier
    function tokenToCard(address token) external view returns (uint256);

    /// @notice Get the staked portion of a card's reserve
    /// @param cardId Card identifier
    /// @return Staked card tokens (subset of total cardReserve)
    function getStakedCards(uint256 cardId) external view returns (uint256);

    /// @notice Internal swap between two cards without token transfers (for swapStake)
    /// @param fromCardId Source card identifier
    /// @param toCardId Destination card identifier
    /// @param cardAmountIn Amount of source card tokens to swap
    /// @return cardAmountOut Amount of destination card tokens received
    function internalSwapCardToCard(
        uint256 fromCardId,
        uint256 toCardId,
        uint256 cardAmountIn
    ) external returns (uint256 cardAmountOut);
}
