// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWhirlpool {
    function stake(uint256 cardId, uint256 amount) external;
    function unstake(uint256 cardId, uint256 amount) external;
    function stakeWETH(uint256 amount) external;
    function unstakeWETH(uint256 amount) external;
    function distributeMintFee() external payable;
    function distributeSwapFees(uint256 cardId, uint256 wavesFee) external;
    function distributeWethSwapFees(uint256 wavesFee) external;
    function registerCard(uint256 cardId, address token) external;
    function autoStake(uint256 cardId, address user, uint256 amount) external;
    
    function ownerOfCard(uint256 cardId) external view returns (address);
    function stakeOf(uint256 cardId, address user) external view returns (uint256);
    function pendingRewards(uint256 cardId, address user) external view returns (uint256);
    function pendingGlobalRewards(address user) external view returns (uint256);
}
