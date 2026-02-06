// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BidToken.sol";
import "../src/BidNFT.sol";

contract BidNFTTest is Test {
    BidToken public token;
    BidNFT public nft;
    
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    
    uint256 public constant TOTAL_SUPPLY = 1_000_000e18;

    function setUp() public {
        nft = new BidNFT("WavesTCG", "WAVES");
        nft.setFactory(address(this));
        
        token = new BidToken(
            "Test Card",
            "CARD",
            address(nft),
            0,
            TOTAL_SUPPLY,
            alice,
            alice
        );
        
        nft.mint(alice, address(token), "ipfs://test");
    }

    function test_OwnerOfReturnsTopHolder() public view {
        assertEq(nft.ownerOf(0), alice);
        assertEq(nft.ownerOf(0), token.topHolder());
    }

    function test_OwnerOfUpdatesWithTokenTransfer() public {
        vm.prank(alice);
        token.transfer(bob, 600_000e18);
        
        assertEq(nft.ownerOf(0), bob);
    }

    function test_TransfersAreDisabled() public {
        vm.prank(alice);
        vm.expectRevert("Transfers disabled");
        nft.transferFrom(alice, bob, 0);
    }

    function test_SafeTransfersAreDisabled() public {
        vm.prank(alice);
        vm.expectRevert("Transfers disabled");
        nft.safeTransferFrom(alice, bob, 0);
    }

    function test_ApprovalsAreDisabled() public {
        vm.prank(alice);
        vm.expectRevert("Approvals disabled");
        nft.approve(bob, 0);
    }

    function test_SetApprovalForAllIsDisabled() public {
        vm.prank(alice);
        vm.expectRevert("Approvals disabled");
        nft.setApprovalForAll(bob, true);
    }

    function test_TokenURI() public view {
        assertEq(nft.tokenURI(0), "ipfs://test");
    }

    function test_BidToken() public view {
        assertEq(nft.bidToken(0), address(token));
    }

    function test_NonExistentTokenReverts() public {
        vm.expectRevert("Token does not exist");
        nft.ownerOf(999);
    }

    function test_OnlyFactoryCanMint() public {
        vm.prank(alice);
        vm.expectRevert("Only factory");
        nft.mint(alice, address(token), "ipfs://test2");
    }

    function test_FactoryCanOnlyBeSetOnce() public {
        vm.expectRevert("Factory already set");
        nft.setFactory(bob);
    }
}
