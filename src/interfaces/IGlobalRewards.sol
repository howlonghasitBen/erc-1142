// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGlobalRewards {
    function addWeight(address user, uint256 weight) external;
    function removeWeight(address user, uint256 weight) external;
    function harvestGlobal(address user) external;
    function distributeMintFee() external payable;
    function pendingGlobalRewards(address user) external view returns (uint256);
}
