// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IWhirlpoolRouter — Interface for the card creation orchestrator
/// @notice Defines card creation and registry query functions
interface IWhirlpoolRouter {
    /// @notice Create a new card (deploy token, seed AMM, auto-stake, mint NFT)
    /// @param name Card token name
    /// @param symbol Card token symbol
    /// @param tokenURI Metadata URI for the BidNFT
    /// @return cardId Unique identifier for the new card
    function createCard(string calldata name, string calldata symbol, string calldata tokenURI) external payable returns (uint256 cardId);

    /// @notice Get total number of cards created
    /// @return Total card count
    function totalCards() external view returns (uint256);

    /// @notice Get the ERC-20 token address for a card
    /// @param cardId Card identifier
    /// @return Card token address
    function cardToken(uint256 cardId) external view returns (address);
}
