// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/WAVES.sol";
import "../src/BidNFT.sol";
import "../src/SurfSwap.sol";
import "../src/GlobalRewards.sol";
import "../src/CardStaking.sol";
import "../src/WethPool.sol";
import "../src/WhirlpoolRouter.sol";

/// @title WhirlpoolDeployer — Factory for deploying the entire Whirlpool system (Option B)
/// @notice Deploys GlobalRewards + CardStaking + WethPool + SurfSwap + Router
contract WhirlpoolDeployer is Script {
    function run() external {
        address weth = vm.envAddress("WETH_ADDRESS");
        address protocol = vm.envAddress("PROTOCOL_ADDRESS");

        vm.startBroadcast();

        address deployer = msg.sender;
        uint256 nonce = vm.getNonce(deployer);

        address predictedGlobalRewards = vm.computeCreateAddress(deployer, nonce + 1);
        address predictedSurfSwap = vm.computeCreateAddress(deployer, nonce + 2);
        address predictedCardStaking = vm.computeCreateAddress(deployer, nonce + 3);
        address predictedWethPool = vm.computeCreateAddress(deployer, nonce + 4);
        address predictedRouter = vm.computeCreateAddress(deployer, nonce + 6);

        WAVES waves = new WAVES(predictedRouter);
        GlobalRewards globalRewards = new GlobalRewards();
        SurfSwap surfSwap = new SurfSwap(address(waves), weth, predictedCardStaking, predictedWethPool, predictedRouter);
        CardStaking cardStaking = new CardStaking(address(waves), address(surfSwap), predictedRouter, address(globalRewards));
        WethPool wethPool = new WethPool(address(waves), weth, address(surfSwap), address(globalRewards));
        BidNFT bidNFT = new BidNFT(address(cardStaking), predictedRouter);
        WhirlpoolRouter router = new WhirlpoolRouter(
            address(waves), address(bidNFT), address(surfSwap),
            address(cardStaking), address(globalRewards), weth, protocol
        );

        globalRewards.registerOperator(address(cardStaking));
        globalRewards.registerOperator(address(wethPool));

        require(address(router) == predictedRouter, "Router mismatch");

        vm.stopBroadcast();

        console.log("Deployed Whirlpool system (Option B):");
        console.log("  WAVES:", address(waves));
        console.log("  GlobalRewards:", address(globalRewards));
        console.log("  SurfSwap:", address(surfSwap));
        console.log("  CardStaking:", address(cardStaking));
        console.log("  WethPool:", address(wethPool));
        console.log("  BidNFT:", address(bidNFT));
        console.log("  Router:", address(router));
    }
}
