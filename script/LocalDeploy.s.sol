// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/WAVES.sol";
import "../src/BidNFT.sol";
import "../src/SurfSwap.sol";
import "../src/WhirlpoolStaking.sol";
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
        uint256 nonce = vm.getNonce(deployer);
        address predictedRouter = vm.computeCreateAddress(deployer, nonce + 4);
        address predictedWhirlpool = vm.computeCreateAddress(deployer, nonce + 2);
        address predictedSurfSwap = vm.computeCreateAddress(deployer, nonce + 1);

        // Deploy system
        WAVES waves = new WAVES(predictedRouter);
        SurfSwap surfSwap = new SurfSwap(address(waves), address(weth), predictedWhirlpool, predictedRouter);
        WhirlpoolStaking whirlpool = new WhirlpoolStaking(address(waves), address(weth), address(surfSwap), predictedRouter);
        BidNFT bidNFT = new BidNFT(address(whirlpool), predictedRouter);
        WhirlpoolRouter router = new WhirlpoolRouter(address(waves), address(bidNFT), address(surfSwap), address(whirlpool), address(weth), deployer);

        require(address(router) == predictedRouter, "Router mismatch");
        require(address(whirlpool) == predictedWhirlpool, "Whirlpool mismatch");
        require(address(surfSwap) == predictedSurfSwap, "SurfSwap mismatch");

        // Create 3 sample cards
        router.createCard{value: 0.05 ether}("Fire Dragon", "FDRAGON", "ipfs://fire");
        router.createCard{value: 0.05 ether}("Ice Phoenix", "IPHOENIX", "ipfs://ice");
        router.createCard{value: 0.05 ether}("Thunder Wolf", "TWOLF", "ipfs://wolf");

        vm.stopBroadcast();

        console.log("=== Whirlpool System Deployed ===");
        console.log("WETH:       ", address(weth));
        console.log("WAVES:      ", address(waves));
        console.log("SurfSwap:   ", address(surfSwap));
        console.log("Whirlpool:  ", address(whirlpool));
        console.log("BidNFT:     ", address(bidNFT));
        console.log("Router:     ", address(router));
        console.log("Cards:      ", router.totalCards());
    }
}
