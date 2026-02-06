// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IBidNFT is IERC721 {
    /// @notice Get the paired BidToken for an NFT
    function bidToken(uint256 tokenId) external view returns (address);
    
    /// @notice Mint a new NFT entry (only callable by factory)
    function mint(
        address creator,
        address bidToken_,
        string calldata tokenURI_
    ) external returns (uint256 tokenId);
}
