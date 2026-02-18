// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./interfaces/ICardStaking.sol";

/// @title BidNFT — ERC-721 where ownerOf() dynamically reads from WhirlpoolStaking
/// @author Whirlpool Team
/// @notice Non-transferable NFT representing card ownership. The owner is always the
///         address with the most LP shares in WhirlpoolStaking (biggest staker = owner).
///         Transfers, approvals, and setApprovalForAll are all disabled.
/// @dev ownerOf() makes an external call to WhirlpoolStaking.ownerOfCard() on every query.
///      Only the Router can mint new NFTs (one per card creation).
contract BidNFT is ERC721 {
    /// @notice WhirlpoolStaking contract (source of truth for ownership)
    address public immutable cardStaking;
    /// @notice WhirlpoolRouter contract (only address that can mint)
    address public immutable router;

    /// @dev Token URI storage (set once at mint, immutable per token)
    mapping(uint256 => string) private _tokenURIs;
    /// @dev Existence check (prevents double-minting)
    mapping(uint256 => bool) private _exists;

    /// @param cardStaking_ CardStaking contract address
    /// @param router_ WhirlpoolRouter contract address
    constructor(address cardStaking_, address router_) ERC721("Whirlpool Cards", "WCARD") {
        cardStaking = cardStaking_;
        router = router_;
    }

    /// @notice Mint a new BidNFT for a card (only callable by Router)
    /// @dev Emits Transfer(address(0), currentOwner, cardId) to comply with ERC-721 standard.
    ///      Does NOT call _mint() internally — ownership is virtual (read from Whirlpool).
    /// @param cardId Card identifier (must not already exist)
    /// @param tokenURI_ Metadata URI (e.g., IPFS hash)
    function mint(uint256 cardId, string calldata tokenURI_) external {
        require(msg.sender == router, "Only router");
        require(!_exists[cardId], "Already minted");
        _exists[cardId] = true;
        _tokenURIs[cardId] = tokenURI_;
        emit Transfer(address(0), ICardStaking(cardStaking).ownerOfCard(cardId), cardId);
    }

    /// @notice Get the current owner of a card NFT (reads from WhirlpoolStaking)
    /// @dev This is a view function that makes an external call to WhirlpoolStaking.
    ///      Owner changes dynamically as staking positions change — no Transfer events emitted.
    /// @param tokenId Card identifier
    /// @return Current owner address (biggest LP shareholder)
    function ownerOf(uint256 tokenId) public view override returns (address) {
        require(_exists[tokenId], "Token does not exist");
        return ICardStaking(cardStaking).ownerOfCard(tokenId);
    }

    /// @notice Get the metadata URI for a card NFT
    /// @param tokenId Card identifier
    /// @return Metadata URI string
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists[tokenId], "Token does not exist");
        return _tokenURIs[tokenId];
    }

    /// @notice Check if a card NFT exists
    /// @param tokenId Card identifier
    /// @return True if minted
    function exists(uint256 tokenId) external view returns (bool) {
        return _exists[tokenId];
    }

    /// @notice Transfers are disabled — ownership is determined by staking position
    function transferFrom(address, address, uint256) public pure override {
        revert("Transfers disabled");
    }

    /// @notice Transfers are disabled — ownership is determined by staking position
    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert("Transfers disabled");
    }

    /// @notice Approvals are disabled — no delegation of non-transferable tokens
    function approve(address, uint256) public pure override {
        revert("Approvals disabled");
    }

    /// @notice Approvals are disabled — no delegation of non-transferable tokens
    function setApprovalForAll(address, bool) public pure override {
        revert("Approvals disabled");
    }

    /// @notice Always returns address(0) — approvals disabled
    /// @return address(0)
    function getApproved(uint256) public pure override returns (address) {
        return address(0);
    }

    /// @notice Always returns false — approvals disabled
    /// @return false
    function isApprovedForAll(address, address) public pure override returns (bool) {
        return false;
    }
}
