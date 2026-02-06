// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBidToken is IERC20 {
    /// @notice Emitted when top holder changes
    event TopHolderChanged(
        address indexed previousHolder,
        address indexed newHolder,
        uint256 newBalance
    );

    /// @notice The paired BidNFT contract
    function bidNFT() external view returns (address);

    /// @notice The NFT token ID this token controls
    function nftTokenId() external view returns (uint256);

    /// @notice Current top holder (NFT owner)
    /// @dev Updated automatically on every transfer
    function topHolder() external view returns (address);
}
