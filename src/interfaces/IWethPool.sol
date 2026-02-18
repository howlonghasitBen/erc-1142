// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWethPool {
    function stakeWETH(uint256 amount) external;
    function unstakeWETH(uint256 shares) external;
    function distributeWethSwapFees(uint256 wavesFee) external;
    function claimableWeth(address user) external view returns (uint256);
    function claimableWethPool(address user) external view returns (uint256 wethAmount, uint256 wavesAmount);
    function userWethShares(address user) external view returns (uint256);
    function userWethStake(address user) external view returns (uint256);
}
