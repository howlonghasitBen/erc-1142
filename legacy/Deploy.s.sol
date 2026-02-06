// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BidNFT.sol";
import "../src/BidToken.sol";
import "../src/BidFactory.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy mock WAVES token (for testing)
        MockWAVES waves = new MockWAVES();
        
        // Deploy BidNFT
        BidNFT bidNFT = new BidNFT("WavesTCG", "WAVES");
        
        // Deploy BidFactory (using mock addresses for Uniswap on local)
        BidFactory factory = new BidFactory(
            address(bidNFT),
            address(waves),
            address(0), // Mock Uniswap factory
            address(0)  // Mock position manager
        );
        
        // Set factory on BidNFT
        bidNFT.setFactory(address(factory));
        
        vm.stopBroadcast();
        
        console.log("WAVES Token:", address(waves));
        console.log("BidNFT:", address(bidNFT));
        console.log("BidFactory:", address(factory));
    }
}

// Simple mock WAVES token for local testing
contract MockWAVES {
    string public name = "WAVES";
    string public symbol = "WAVES";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor() {
        // Mint 1M WAVES to deployer
        balanceOf[msg.sender] = 1_000_000e18;
        totalSupply = 1_000_000e18;
        emit Transfer(address(0), msg.sender, 1_000_000e18);
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
    
    // Faucet for testing
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}
