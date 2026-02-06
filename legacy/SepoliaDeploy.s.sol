// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BidNFT.sol";
import "../src/BidToken.sol";
import "../src/BidFactory.sol";

/// @notice Deploy to Sepolia with real Uniswap V3
contract SepoliaDeployScript is Script {
    // Uniswap V3 Sepolia
    address constant UNI_FACTORY = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
    address constant UNI_POSITION_MANAGER = 0x1238536071E1c677A632429e3655c799b22cDA52;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy a WAVES token for testing
        MockWAVES waves = new MockWAVES();
        waves.mint(deployer, 1_000_000e18);

        // Deploy BidNFT
        BidNFT bidNFT = new BidNFT("WavesTCG", "WAVES");

        // Deploy BidFactory with real Uniswap addresses
        BidFactory factory = new BidFactory(
            address(bidNFT),
            address(waves),
            UNI_FACTORY,
            UNI_POSITION_MANAGER
        );

        // Connect factory to NFT
        bidNFT.setFactory(address(factory));

        // Approve WAVES spending
        waves.approve(address(factory), type(uint256).max);

        vm.stopBroadcast();

        console.log("=== Sepolia Deployment ===");
        console.log("WAVES Token:", address(waves));
        console.log("BidNFT:", address(bidNFT));
        console.log("BidFactory:", address(factory));
        console.log("");
        console.log("To create a card:");
        console.log("  forge script script/CreateCard.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast");
    }
}

/// @notice Simple ERC-20 for testnet
contract MockWAVES {
    string public name = "WAVES";
    string public symbol = "WAVES";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
