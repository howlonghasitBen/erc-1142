// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IBidToken.sol";

/// @title BidToken
/// @notice ERC-20 token that tracks top holder for NFT ownership
/// @dev Ownership automatically updates on every transfer
contract BidToken is ERC20, IBidToken {
    address public immutable override bidNFT;
    uint256 public immutable override nftTokenId;
    address public override topHolder;

    constructor(
        string memory name_,
        string memory symbol_,
        address bidNFT_,
        uint256 nftTokenId_,
        uint256 totalSupply_,
        address mintTo_,
        address initialTopHolder_
    ) ERC20(name_, symbol_) {
        bidNFT = bidNFT_;
        nftTokenId = nftTokenId_;
        topHolder = initialTopHolder_;
        _mint(mintTo_, totalSupply_);
    }

    /// @dev Override to track top holder on every transfer
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._update(from, to, amount);

        // Check if recipient becomes new top holder
        if (to != address(0) && balanceOf(to) > balanceOf(topHolder)) {
            address previous = topHolder;
            topHolder = to;
            emit TopHolderChanged(previous, to, balanceOf(to));
        }
    }
}
