// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/WAVES.sol";
import "../src/BidNFT.sol";
import "../src/SurfSwap.sol";
import "../src/WhirlpoolStaking.sol";
import "../src/WhirlpoolRouter.sol";

/// @title WhirlpoolDeployer — Factory for deploying the entire Whirlpool system
/// @notice Deploys all contracts in correct order with proper cross-references
contract WhirlpoolDeployer is Script {
    function run() external returns (
        address waves,
        address bidNFT,
        address surfSwap,
        address whirlpool,
        address router
    ) {
        address weth = vm.envAddress("WETH_ADDRESS");
        address protocol = vm.envAddress("PROTOCOL_ADDRESS");

        vm.startBroadcast();

        // Deploy in order with cross-references
        // 1. Deploy WAVES (needs router address - we'll use CREATE2 or deploy with placeholder then ignore)
        // Actually simpler: deploy router first with a temp address, then use that
        
        // We need to predict addresses or use a two-step deployment
        // Simplest: Deploy everything, then wire up
        
        // Step 1: Deploy implementation contracts
        // We'll deploy Router first (it doesn't need others in constructor)
        // Then deploy the rest pointing to Router
        
        // Actually, looking at the constructors:
        // - WAVES needs: router
        // - BidNFT needs: whirlpool, router
        // - SurfSwap needs: waves, weth, whirlpool, router
        // - Whirlpool needs: waves, weth, surfSwap, router
        // - Router needs: waves, bidNFT, surfSwap, whirlpool, weth, protocol
        
        // This is circular. We need to use CREATE2 to predict addresses
        // Or use a factory pattern that deploys in sequence
        
        // Simplest factory approach:
        // 1. Deploy Router (placeholder)
        // 2. Deploy WAVES with Router address
        // 3. Deploy Whirlpool with WAVES
        // 4. Deploy SurfSwap with WAVES, Whirlpool, Router
        // 5. Deploy BidNFT with Whirlpool, Router
        // 6. Deploy Router with all addresses
        
        // Actually even simpler: use address(0) as placeholder, then compute addresses
        // Let's use foundry's vm.computeCreateAddress
        
        address deployer = msg.sender;
        uint256 nonce = vm.getNonce(deployer);
        
        // Predict addresses
        address predictedRouter = vm.computeCreateAddress(deployer, nonce + 4);
        address predictedWhirlpool = vm.computeCreateAddress(deployer, nonce + 2);
        address predictedSurfSwap = vm.computeCreateAddress(deployer, nonce + 1);
        
        // Deploy in sequence
        waves = address(new WAVES(predictedRouter)); // nonce 0
        surfSwap = address(new SurfSwap(waves, weth, predictedWhirlpool, predictedRouter)); // nonce 1
        whirlpool = address(new WhirlpoolStaking(waves, weth, surfSwap, predictedRouter)); // nonce 2
        bidNFT = address(new BidNFT(whirlpool, predictedRouter)); // nonce 3
        router = address(new WhirlpoolRouter(waves, bidNFT, surfSwap, whirlpool, weth, protocol)); // nonce 4
        
        require(router == predictedRouter, "Router address mismatch");
        require(whirlpool == predictedWhirlpool, "Whirlpool address mismatch");
        require(surfSwap == predictedSurfSwap, "SurfSwap address mismatch");
        
        vm.stopBroadcast();
        
        console.log("Deployed Whirlpool system:");
        console.log("  WAVES:", waves);
        console.log("  BidNFT:", bidNFT);
        console.log("  SurfSwap:", surfSwap);
        console.log("  Whirlpool:", whirlpool);
        console.log("  Router:", router);
    }
}
