// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBidFactory {
    /// @notice Emitted when a new card is created
    event CardCreated(
        uint256 indexed tokenId,
        address indexed bidToken,
        address indexed pool,
        address creator
    );

    /// @notice WAVES token address
    function wavesToken() external view returns (address);
    
    /// @notice The BidNFT contract
    function bidNFT() external view returns (address);

    /// @notice Create a new card with paired token and liquidity
    /// @param name Token/card name
    /// @param symbol Token symbol  
    /// @param totalSupply Total token supply
    /// @param tokenURI NFT metadata URI
    function createCard(
        string calldata name,
        string calldata symbol,
        uint256 totalSupply,
        string calldata tokenURI
    ) external payable returns (
        uint256 tokenId,
        address bidToken,
        address pool
    );
    
    /// @notice Get Uniswap pool for a token
    function getPool(uint256 tokenId) external view returns (address);
}
