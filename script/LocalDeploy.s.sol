// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/WAVES.sol";
import "../src/BidNFT.sol";
import "../src/SurfSwap.sol";
import "../src/GlobalRewards.sol";
import "../src/CardStaking.sol";
import "../src/WethPool.sol";
import "../src/WhirlpoolRouter.sol";

contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}
    function deposit() external payable { _mint(msg.sender, msg.value); }
    function withdraw(uint256 amount) external { _burn(msg.sender, amount); payable(msg.sender).transfer(amount); }
    receive() external payable { _mint(msg.sender, msg.value); }
}

contract LocalDeployScript is Script {
    uint256 constant PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external {
        address deployer = vm.addr(PK);
        vm.startBroadcast(PK);

        // Deploy mock WETH first
        MockWETH weth = new MockWETH();
        console.log("WETH:", address(weth));

        // Predict addresses for circular refs
        // Deploy order: WETH(0), WAVES(1), GlobalRewards(2), SurfSwap(3), CardStaking(4), WethPool(5), BidNFT(6), Router(7)
        uint256 nonce = vm.getNonce(deployer);
        address predictedGlobalRewards = vm.computeCreateAddress(deployer, nonce + 1);
        address predictedSurfSwap = vm.computeCreateAddress(deployer, nonce + 2);
        address predictedCardStaking = vm.computeCreateAddress(deployer, nonce + 3);
        address predictedWethPool = vm.computeCreateAddress(deployer, nonce + 4);
        address predictedRouter = vm.computeCreateAddress(deployer, nonce + 6);

        // Deploy system
        WAVES waves = new WAVES(predictedRouter);                                                              // nonce+0
        GlobalRewards globalRewards = new GlobalRewards();                                                     // nonce+1
        SurfSwap surfSwap = new SurfSwap(address(waves), address(weth), predictedCardStaking, predictedWethPool, predictedRouter); // nonce+2
        CardStaking cardStaking = new CardStaking(address(waves), address(surfSwap), predictedRouter, address(globalRewards));     // nonce+3
        WethPool wethPool = new WethPool(address(waves), address(weth), address(surfSwap), address(globalRewards));               // nonce+4
        BidNFT bidNFT = new BidNFT(address(cardStaking), predictedRouter);                                    // nonce+5
        WhirlpoolRouter router = new WhirlpoolRouter(                                                          // nonce+6
            address(waves), address(bidNFT), address(surfSwap),
            address(cardStaking), address(globalRewards), address(weth), deployer
        );

        // Register operators on GlobalRewards
        globalRewards.registerOperator(address(cardStaking));
        globalRewards.registerOperator(address(wethPool));

        // Verify predictions
        require(address(globalRewards) == predictedGlobalRewards, "GlobalRewards mismatch");
        require(address(surfSwap) == predictedSurfSwap, "SurfSwap mismatch");
        require(address(cardStaking) == predictedCardStaking, "CardStaking mismatch");
        require(address(wethPool) == predictedWethPool, "WethPool mismatch");
        require(address(router) == predictedRouter, "Router mismatch");

        vm.stopBroadcast();

        console.log("=== Whirlpool System Deployed (Option B) ===");
        console.log("WETH:          ", address(weth));
        console.log("WAVES:         ", address(waves));
        console.log("GlobalRewards: ", address(globalRewards));
        console.log("SurfSwap:      ", address(surfSwap));
        console.log("CardStaking:   ", address(cardStaking));
        console.log("WethPool:      ", address(wethPool));
        console.log("BidNFT:        ", address(bidNFT));
        console.log("Router:        ", address(router));
        console.log("Cards:         ", router.totalCards());
    }
}
