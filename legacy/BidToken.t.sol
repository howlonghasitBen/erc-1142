// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BidToken.sol";
import "../src/BidNFT.sol";
import "../src/interfaces/IBidToken.sol";

contract BidTokenTest is Test {
    BidToken public token;
    BidNFT public nft;
    
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");
    
    uint256 public constant TOTAL_SUPPLY = 1_000_000e18;

    function setUp() public {
        nft = new BidNFT("WavesTCG", "WAVES");
        token = new BidToken(
            "Test Card",
            "CARD",
            address(nft),
            0,
            TOTAL_SUPPLY,
            alice,           // Mint all to alice
            alice            // Alice is initial top holder
        );
    }

    function test_InitialState() public view {
        assertEq(token.name(), "Test Card");
        assertEq(token.symbol(), "CARD");
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
        assertEq(token.balanceOf(alice), TOTAL_SUPPLY);
        assertEq(token.topHolder(), alice);
    }

    function test_TopHolderUpdatesOnTransfer() public {
        // Alice transfers more than half to Bob
        vm.prank(alice);
        token.transfer(bob, 600_000e18);
        
        // Bob should now be top holder
        assertEq(token.topHolder(), bob);
        assertEq(token.balanceOf(bob), 600_000e18);
        assertEq(token.balanceOf(alice), 400_000e18);
    }

    function test_TopHolderRequiresStrictlyMore() public {
        // Alice transfers exactly half to Bob
        vm.prank(alice);
        token.transfer(bob, 500_000e18);
        
        // Alice should still be top holder (tie goes to incumbent)
        assertEq(token.topHolder(), alice);
    }

    function test_TopHolderCanChange() public {
        // Alice transfers 400k to Bob
        vm.prank(alice);
        token.transfer(bob, 400_000e18);
        assertEq(token.topHolder(), alice); // Alice: 600k, Bob: 400k
        
        // Alice transfers another 300k to Bob
        vm.prank(alice);
        token.transfer(bob, 300_000e18);
        assertEq(token.topHolder(), bob); // Alice: 300k, Bob: 700k
        
        // Bob transfers 500k to Carol
        vm.prank(bob);
        token.transfer(carol, 500_000e18);
        assertEq(token.topHolder(), carol); // Alice: 300k, Bob: 200k, Carol: 500k
    }

    function test_TopHolderChangedEvent() public {
        vm.prank(alice);
        
        vm.expectEmit(true, true, false, true);
        emit IBidToken.TopHolderChanged(alice, bob, 600_000e18);
        
        token.transfer(bob, 600_000e18);
    }

    function test_NFTOwnershipFollowsTopHolder() public {
        // Set up NFT
        nft.setFactory(address(this));
        nft.mint(alice, address(token), "ipfs://test");
        
        // Initially alice owns the NFT
        assertEq(nft.ownerOf(0), alice);
        
        // Transfer tokens to bob
        vm.prank(alice);
        token.transfer(bob, 600_000e18);
        
        // Now bob owns the NFT
        assertEq(nft.ownerOf(0), bob);
    }
}
