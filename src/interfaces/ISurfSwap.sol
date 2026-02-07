// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISurfSwap {
    function initializePool(uint256 cardId, address token, uint256 wavesAmount, uint256 cardAmount) external;
    function swapExact(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256 amountOut);
    function addToCardReserve(uint256 cardId, uint256 amount) external;
    function removeFromCardReserve(uint256 cardId, uint256 amount) external;
    function addToWethReserve(uint256 amount) external;
    function removeFromWethReserve(uint256 amount) external;
    
    function getPrice(uint256 cardId) external view returns (uint256);
    function getReserves(uint256 cardId) external view returns (uint256 wavesR, uint256 cardsR);
    function getWethReserves() external view returns (uint256 wavesR, uint256 wethR);
    function isCardToken(address token) external view returns (bool);
    function tokenToCard(address token) external view returns (uint256);
    function getStakedCards(uint256 cardId) external view returns (uint256);
    
    function internalSwapCardToCard(
        uint256 fromCardId,
        uint256 toCardId,
        uint256 cardAmountIn
    ) external returns (uint256 cardAmountOut);
}
