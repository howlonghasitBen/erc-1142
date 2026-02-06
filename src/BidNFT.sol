// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./interfaces/IWhirlpool.sol";

/// @title BidNFT — ERC-721 where ownerOf() reads from Whirlpool's biggest staker
/// @dev Transfers disabled. Only Router can mint.
contract BidNFT is ERC721 {
    address public immutable whirlpool;
    address public immutable router;
    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => bool) private _exists;

    constructor(address whirlpool_, address router_) ERC721("Whirlpool Cards", "WCARD") {
        whirlpool = whirlpool_;
        router = router_;
    }

    function mint(uint256 cardId, string calldata tokenURI_) external {
        require(msg.sender == router, "Only router");
        require(!_exists[cardId], "Already minted");
        _exists[cardId] = true;
        _tokenURIs[cardId] = tokenURI_;
        emit Transfer(address(0), IWhirlpool(whirlpool).ownerOfCard(cardId), cardId);
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        require(_exists[tokenId], "Token does not exist");
        return IWhirlpool(whirlpool).ownerOfCard(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists[tokenId], "Token does not exist");
        return _tokenURIs[tokenId];
    }

    function exists(uint256 tokenId) external view returns (bool) {
        return _exists[tokenId];
    }

    function transferFrom(address, address, uint256) public pure override {
        revert("Transfers disabled");
    }
    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert("Transfers disabled");
    }
    function approve(address, uint256) public pure override {
        revert("Approvals disabled");
    }
    function setApprovalForAll(address, bool) public pure override {
        revert("Approvals disabled");
    }
    function getApproved(uint256) public pure override returns (address) {
        return address(0);
    }
    function isApprovedForAll(address, address) public pure override returns (bool) {
        return false;
    }
}
