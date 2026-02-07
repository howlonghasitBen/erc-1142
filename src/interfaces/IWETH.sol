// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IWETH — Interface for Wrapped Ether (WETH) token
/// @notice Standard WETH interface extending IERC20 with deposit/withdraw
interface IWETH is IERC20 {
    /// @notice Wrap ETH into WETH (msg.value → WETH balance)
    function deposit() external payable;

    /// @notice Unwrap WETH back to ETH
    /// @param amount WETH to unwrap
    function withdraw(uint256 amount) external;
}
