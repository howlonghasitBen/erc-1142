// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BidNFT.sol";
import "../src/BidToken.sol";

/// @notice Simple factory for local testing (no Uniswap)
contract SimpleFactory {
    BidNFT public bidNFT;
    
    constructor(BidNFT _bidNFT) {
        bidNFT = _bidNFT;
    }
    
    function createCard(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        string memory tokenURI,
        address recipient
    ) external returns (uint256 tokenId, address bidToken) {
        tokenId = bidNFT.nextTokenId();
        
        BidToken token = new BidToken(
            name,
            symbol,
            address(bidNFT),
            tokenId,
            totalSupply,
            recipient,  // Tokens go to recipient
            recipient   // Recipient is initial top holder
        );
        bidToken = address(token);
        
        bidNFT.mint(recipient, bidToken, tokenURI);
    }
}

/// @notice Local deploy script - creates cards without Uniswap integration
contract LocalDeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy BidNFT
        BidNFT bidNFT = new BidNFT("WavesTCG", "WAVES");
        
        // Deploy simple factory
        SimpleFactory factory = new SimpleFactory(bidNFT);
        
        // Set factory on BidNFT
        bidNFT.setFactory(address(factory));
        
        // Create 3 sample cards
        (uint256 id1, address card1) = factory.createCard(
            "Fire Dragon",
            "FDRAGON",
            1_000_000e18,
            "ipfs://QmFireDragon",
            deployer
        );
        
        (uint256 id2, address card2) = factory.createCard(
            "Ice Phoenix",
            "IPHOENIX",
            1_000_000e18,
            "ipfs://QmIcePhoenix",
            deployer
        );
        
        (uint256 id3, address card3) = factory.createCard(
            "Thunder Wolf",
            "TWOLF",
            1_000_000e18,
            "ipfs://QmThunderWolf",
            deployer
        );
        
        vm.stopBroadcast();
        
        console.log("=== Deployed Contracts ===");
        console.log("BidNFT:", address(bidNFT));
        console.log("Factory:", address(factory));
        console.log("");
        console.log("=== Cards ===");
        console.log("Card 0 (Fire Dragon):", card1);
        console.log("Card 1 (Ice Phoenix):", card2);
        console.log("Card 2 (Thunder Wolf):", card3);
        console.log("");
        console.log("Deployer:", deployer);
    }
}
