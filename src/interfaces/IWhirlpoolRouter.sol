// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWhirlpoolRouter {
    function createCard(string calldata name, string calldata symbol, string calldata tokenURI) external payable returns (uint256 cardId);
    function totalCards() external view returns (uint256);
    function cardToken(uint256 cardId) external view returns (address);
}
