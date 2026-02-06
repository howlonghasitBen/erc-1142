// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BidNFT.sol";
import "../src/BidToken.sol";
import "../src/BidFactory.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @notice Mock ERC-20 for WAVES token in tests
contract MockWAVES {
    string public name = "WAVES";
    string public symbol = "WAVES";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice Fork test using Uniswap V3 on Sepolia
contract BidFactoryForkTest is Test {
    // Uniswap V3 Sepolia addresses
    address constant UNI_FACTORY = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
    address constant UNI_POSITION_MANAGER = 0x1238536071E1c677A632429e3655c799b22cDA52;

    BidNFT public bidNFT;
    BidFactory public factory;
    MockWAVES public waves;

    address public deployer;
    address public alice;
    address public bob;

    function setUp() public {
        // Fork Sepolia
        // If SEPOLIA_RPC_URL not set, skip
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            return;
        }
        vm.createSelectFork(rpc);

        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.startPrank(deployer);

        // Deploy WAVES mock
        waves = new MockWAVES();
        waves.mint(deployer, 1_000_000e18);

        // Deploy system
        bidNFT = new BidNFT("WavesTCG", "WAVES");
        factory = new BidFactory(
            address(bidNFT),
            address(waves),
            UNI_FACTORY,
            UNI_POSITION_MANAGER
        );
        bidNFT.setFactory(address(factory));

        // Approve WAVES for factory
        waves.approve(address(factory), type(uint256).max);

        vm.stopPrank();
    }

    function test_CreateCardWithPool() public {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            // Skip test if no RPC
            return;
        }

        vm.prank(deployer);
        (uint256 tokenId, address bidTokenAddr, address pool) = factory.createCard{value: 0}(
            "Fire Dragon",
            "FDRAGON",
            1_000_000e18,
            "ipfs://QmFireDragon"
        );

        // Verify card was created
        assertEq(tokenId, 0);
        assertTrue(bidTokenAddr != address(0));
        assertTrue(pool != address(0));

        // Verify NFT ownership
        assertEq(bidNFT.ownerOf(0), deployer);

        // Verify token state
        BidToken token = BidToken(bidTokenAddr);
        assertEq(token.topHolder(), deployer);
    }
}

/// @notice Unit tests for BidFactory without Uniswap (using SimpleFactory from deploy script)
contract BidFactoryUnitTest is Test {
    BidNFT public bidNFT;

    address public deployer = makeAddr("deployer");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        vm.prank(deployer);
        bidNFT = new BidNFT("WavesTCG", "WAVES");
    }

    function test_CreateMultipleCards() public {
        // Use a simple helper contract as factory
        SimpleTestFactory testFactory = new SimpleTestFactory(bidNFT);
        vm.prank(deployer);
        bidNFT.setFactory(address(testFactory));

        // Create 3 cards
        (uint256 id0, address token0) = testFactory.createCard("Fire Dragon", "FDRAGON", 1_000_000e18, "ipfs://fire", alice);
        (uint256 id1, address token1) = testFactory.createCard("Ice Phoenix", "IPHOENIX", 1_000_000e18, "ipfs://ice", bob);
        (uint256 id2, address token2) = testFactory.createCard("Thunder Wolf", "TWOLF", 1_000_000e18, "ipfs://thunder", deployer);

        // Verify IDs
        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(id2, 2);

        // Verify ownership
        assertEq(bidNFT.ownerOf(0), alice);
        assertEq(bidNFT.ownerOf(1), bob);
        assertEq(bidNFT.ownerOf(2), deployer);

        // Verify tokens are unique
        assertTrue(token0 != token1);
        assertTrue(token1 != token2);
    }

    function test_OwnershipTransferBetweenCards() public {
        SimpleTestFactory testFactory = new SimpleTestFactory(bidNFT);
        vm.prank(deployer);
        bidNFT.setFactory(address(testFactory));

        // Create 2 cards, both owned by alice
        (, address token0) = testFactory.createCard("Card A", "A", 1_000_000e18, "ipfs://a", alice);
        (, address token1) = testFactory.createCard("Card B", "B", 1_000_000e18, "ipfs://b", alice);

        // Both NFTs owned by alice
        assertEq(bidNFT.ownerOf(0), alice);
        assertEq(bidNFT.ownerOf(1), alice);

        // Alice transfers Card A tokens to bob
        vm.prank(alice);
        BidToken(token0).transfer(bob, 600_000e18);

        // Card A now owned by bob, Card B still alice
        assertEq(bidNFT.ownerOf(0), bob);
        assertEq(bidNFT.ownerOf(1), alice);
    }

    function test_CardCreationEmitsEvent() public {
        SimpleTestFactory testFactory = new SimpleTestFactory(bidNFT);
        vm.prank(deployer);
        bidNFT.setFactory(address(testFactory));

        // The NFT Transfer event (mint)
        vm.expectEmit(true, true, true, false);
        emit IERC721.Transfer(address(0), alice, 0);

        testFactory.createCard("Test Card", "TEST", 1_000_000e18, "ipfs://test", alice);
    }

    function test_TokenURIPerCard() public {
        SimpleTestFactory testFactory = new SimpleTestFactory(bidNFT);
        vm.prank(deployer);
        bidNFT.setFactory(address(testFactory));

        testFactory.createCard("Card A", "A", 1_000_000e18, "ipfs://QmAAAA", alice);
        testFactory.createCard("Card B", "B", 1_000_000e18, "ipfs://QmBBBB", bob);

        assertEq(bidNFT.tokenURI(0), "ipfs://QmAAAA");
        assertEq(bidNFT.tokenURI(1), "ipfs://QmBBBB");
    }

    function test_DifferentSupplies() public {
        SimpleTestFactory testFactory = new SimpleTestFactory(bidNFT);
        vm.prank(deployer);
        bidNFT.setFactory(address(testFactory));

        (, address token0) = testFactory.createCard("Rare", "RARE", 100e18, "ipfs://rare", alice);
        (, address token1) = testFactory.createCard("Common", "COMMON", 10_000_000e18, "ipfs://common", bob);

        assertEq(BidToken(token0).totalSupply(), 100e18);
        assertEq(BidToken(token1).totalSupply(), 10_000_000e18);
    }

    function test_BidTokenMappingOnNFT() public {
        SimpleTestFactory testFactory = new SimpleTestFactory(bidNFT);
        vm.prank(deployer);
        bidNFT.setFactory(address(testFactory));

        (, address token0) = testFactory.createCard("Card", "C", 1_000_000e18, "ipfs://c", alice);

        assertEq(bidNFT.bidToken(0), token0);
    }
}

/// @notice Helper factory for unit tests
contract SimpleTestFactory {
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
        BidToken token = new BidToken(name, symbol, address(bidNFT), tokenId, totalSupply, recipient, recipient);
        bidToken = address(token);
        bidNFT.mint(recipient, bidToken, tokenURI);
    }
}

// IERC721 imported from OpenZeppelin
