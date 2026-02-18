// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICardStaking {
    function stake(uint256 cardId, uint256 amount) external;
    function unstake(uint256 cardId, uint256 shares) external;
    function registerCard(uint256 cardId, address token) external;
    function autoStake(uint256 cardId, address user, uint256 amount) external;
    function distributeSwapFees(uint256 cardId, uint256 wavesFee) external;
    function ownerOfCard(uint256 cardId) external view returns (address);
    function pendingRewards(uint256 cardId, address user) external view returns (uint256);
}
