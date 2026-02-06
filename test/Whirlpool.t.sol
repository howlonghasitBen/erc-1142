// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/WhirlpoolRouter.sol";
import "../src/WhirlpoolStaking.sol";
import "../src/SurfSwap.sol";
import "../src/WAVES.sol";
import "../src/CardToken.sol";
import "../src/BidNFT.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped ETH", "WETH") {}
    function deposit() external payable { _mint(msg.sender, msg.value); }
    function withdraw(uint256 amount) external { _burn(msg.sender, amount); payable(msg.sender).transfer(amount); }
    receive() external payable {}
}

contract WhirlpoolTest is Test {
    WhirlpoolRouter public router;
    WhirlpoolStaking public whirlpool;
    SurfSwap public surfSwap;
    WAVES public waves;
    BidNFT public bidNFT;
    MockWETH public weth;
    
    address public protocol = address(0xBEEF);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public charlie = address(0xC0C0);

    function setUp() public {
        // Deploy using the factory pattern with address prediction
        weth = new MockWETH();
        
        address deployer = address(this);
        uint256 nonce = vm.getNonce(deployer);
        
        // Predict addresses
        address predictedRouter = vm.computeCreateAddress(deployer, nonce + 4);
        address predictedWhirlpool = vm.computeCreateAddress(deployer, nonce + 2);
        address predictedSurfSwap = vm.computeCreateAddress(deployer, nonce + 1);
        
        // Deploy in sequence
        waves = new WAVES(predictedRouter);
        surfSwap = new SurfSwap(address(waves), address(weth), predictedWhirlpool, predictedRouter);
        whirlpool = new WhirlpoolStaking(address(waves), address(weth), address(surfSwap), predictedRouter);
        bidNFT = new BidNFT(address(whirlpool), predictedRouter);
        router = new WhirlpoolRouter(address(waves), address(bidNFT), address(surfSwap), address(whirlpool), address(weth), protocol);
        
        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }

    // ═══ CARD CREATION ═══

    function testCreateCard() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("Card1", "C1", "uri://1");
        assertEq(cardId, 0);
        assertEq(router.totalCards(), 1);
        assertEq(waves.balanceOf(alice), 1500 ether);
        (uint256 wavesR, uint256 cardR) = surfSwap.getReserves(0);
        assertEq(wavesR, 500 ether);
        assertEq(cardR, 9_500_000 ether); // 7.5M AMM + 2M staked
        address ct = router.cardToken(0);
        assertEq(IERC20(ct).balanceOf(protocol), 500_000 ether);
        assertEq(whirlpool.stakeOf(0, alice), 2_000_000 ether); // First staker: 1:1 shares
        assertEq(whirlpool.effectiveBalance(0, alice), 2_000_000 ether); // Effective balance matches
        assertEq(whirlpool.ownerOfCard(0), alice);
        assertEq(bidNFT.ownerOf(0), alice);
    }

    function testCreateCardWrongFee() public {
        vm.prank(alice);
        vm.expectRevert("Exact mint fee required");
        router.createCard{value: 0.04 ether}("C", "C", "u");
    }

    // ═══ SWAPS ═══

    function testSwapWavesToCard() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("Card1", "C1", "uri://1");
        address ct = router.cardToken(0);
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 out = surfSwap.swapExact(address(waves), ct, 50 ether, 0);
        vm.stopPrank();
        assertGt(out, 0);
        assertEq(IERC20(ct).balanceOf(alice), out);
    }

    function testSwapCardToWaves() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("Card1", "C1", "uri://1");
        address ct = router.cardToken(0);
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 cards = surfSwap.swapExact(address(waves), ct, 100 ether, 0);
        IERC20(ct).approve(address(surfSwap), type(uint256).max);
        uint256 wavesBack = surfSwap.swapExact(ct, address(waves), cards, 0);
        vm.stopPrank();
        assertGt(wavesBack, 0);
        assertLt(wavesBack, 100 ether); // round trip loss from fees
    }

    function testSwapCardToCard() public {
        vm.startPrank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        router.createCard{value: 0.05 ether}("C2", "C2", "u2");
        address c1 = router.cardToken(0);
        address c2 = router.cardToken(1);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 c1Amt = surfSwap.swapExact(address(waves), c1, 100 ether, 0);
        IERC20(c1).approve(address(surfSwap), type(uint256).max);
        uint256 c2Amt = surfSwap.swapExact(c1, c2, c1Amt, 0);
        vm.stopPrank();
        assertGt(c2Amt, 0);
        assertEq(IERC20(c2).balanceOf(alice), c2Amt);
    }

    function testSwapWethToWaves() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        // Stake WETH to init pool
        vm.startPrank(bob);
        weth.deposit{value: 10 ether}();
        weth.approve(address(whirlpool), type(uint256).max);
        whirlpool.stakeWETH(10 ether);
        vm.stopPrank();
        // Create another card to seed wavesWethReserve
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C2", "C2", "u2");
        // Swap
        vm.startPrank(bob);
        weth.deposit{value: 1 ether}();
        weth.approve(address(surfSwap), type(uint256).max);
        uint256 out = surfSwap.swapExact(address(weth), address(waves), 1 ether, 0);
        vm.stopPrank();
        assertGt(out, 0);
    }

    // ═══ STAKING ═══

    function testStakeAndUnstake() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        address ct = router.cardToken(0);
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 bought = surfSwap.swapExact(address(waves), ct, 100 ether, 0);
        
        // After minting: pool has 7.5M + 2M (staked) = 9.5M card tokens
        // Alice should have 2M shares initially
        uint256 aliceSharesBefore = whirlpool.stakeOf(0, alice);
        
        IERC20(ct).approve(address(whirlpool), type(uint256).max);
        whirlpool.stake(0, bought);
        
        uint256 aliceSharesAfter = whirlpool.stakeOf(0, alice);
        assertGt(aliceSharesAfter, aliceSharesBefore, "Shares should increase");
        
        // Unstake half the new shares
        uint256 newShares = aliceSharesAfter - aliceSharesBefore;
        whirlpool.unstake(0, newShares / 2);
        
        assertEq(whirlpool.stakeOf(0, alice), aliceSharesAfter - newShares / 2);
        vm.stopPrank();
    }

    // ═══ OWNERSHIP ═══

    function testOwnershipBiggestStaker() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        assertEq(whirlpool.ownerOfCard(0), alice);
        address ct = router.cardToken(0);
        // Bob gets WAVES
        vm.prank(bob);
        router.createCard{value: 0.05 ether}("C2", "C2", "u2");
        vm.prank(alice);
        waves.transfer(bob, 500 ether);
        // Bob buys >2M cards and stakes
        vm.startPrank(bob);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 bought = surfSwap.swapExact(address(waves), ct, 300 ether, 0);
        assertGt(bought, 2_000_000 ether);
        IERC20(ct).approve(address(whirlpool), type(uint256).max);
        whirlpool.stake(0, bought);
        vm.stopPrank();
        assertEq(whirlpool.ownerOfCard(0), bob);
        assertEq(bidNFT.ownerOf(0), bob);
    }

    function testActiveDefense() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        address ct = router.cardToken(0);
        vm.prank(bob);
        router.createCard{value: 0.05 ether}("C2", "C2", "u2");
        vm.prank(alice);
        waves.transfer(bob, 500 ether);
        // Bob takes ownership
        vm.startPrank(bob);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 bought = surfSwap.swapExact(address(waves), ct, 300 ether, 0);
        IERC20(ct).approve(address(whirlpool), type(uint256).max);
        whirlpool.stake(0, bought);
        vm.stopPrank();
        assertEq(whirlpool.ownerOfCard(0), bob);
        // Alice defends
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 aliceBought = surfSwap.swapExact(address(waves), ct, 400 ether, 0);
        IERC20(ct).approve(address(whirlpool), type(uint256).max);
        whirlpool.stake(0, aliceBought);
        vm.stopPrank();
        if (whirlpool.stakeOf(0, alice) > whirlpool.stakeOf(0, bob)) {
            assertEq(whirlpool.ownerOfCard(0), alice);
        }
    }

    // ═══ FEES ═══

    function testSwapFeesToCardStakers() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        address ct = router.cardToken(0);
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        surfSwap.swapExact(address(waves), ct, 100 ether, 0);
        vm.stopPrank();
        uint256 pending = whirlpool.pendingRewards(0, alice);
        assertGt(pending, 0, "Should have pending rewards from swap fees");
    }

    function testMintFeeDistribution() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        vm.prank(bob);
        router.createCard{value: 0.05 ether}("C2", "C2", "u2");
        uint256 pending = whirlpool.pendingGlobalRewards(alice);
        assertGt(pending, 0, "Alice should get share of Bob's mint fee");
    }

    function testWethStakerBoost() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        vm.startPrank(bob);
        weth.deposit{value: 1 ether}();
        weth.approve(address(whirlpool), type(uint256).max);
        whirlpool.stakeWETH(1 ether);
        vm.stopPrank();
        // Bob weight = 1.5 ether; Alice weight = 2M ether
        vm.prank(charlie);
        router.createCard{value: 0.05 ether}("C2", "C2", "u2");
        uint256 bobPending = whirlpool.pendingGlobalRewards(bob);
        assertGt(bobPending, 0, "WETH staker should get mint fee share");
    }

    // ═══ EDGE CASES ═══

    function testZeroAmountReverts() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        address ct = router.cardToken(0);
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        vm.expectRevert("Zero amount");
        surfSwap.swapExact(address(waves), ct, 0, 0);
        vm.stopPrank();
    }

    function testSlippageProtection() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        address ct = router.cardToken(0);
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        vm.expectRevert("Slippage");
        surfSwap.swapExact(address(waves), ct, 10 ether, type(uint256).max);
        vm.stopPrank();
    }

    function testInsufficientUnstake() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        vm.prank(alice);
        vm.expectRevert("Insufficient shares");
        whirlpool.unstake(0, 3_000_000 ether);
    }

    // ═══ LP STAKING MECHANICS ═══

    function testStakeDepositsIntoPool() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        
        // Initial pool: 7.5M AMM + 2M staked = 9.5M
        (uint256 wavesR, uint256 cardR) = surfSwap.getReserves(0);
        assertEq(cardR, 9_500_000 ether, "Initial reserve should be 9.5M");
        
        // Alice buys more and stakes
        address ct = router.cardToken(0);
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 bought = surfSwap.swapExact(address(waves), ct, 100 ether, 0);
        
        (, uint256 cardRAfterBuy) = surfSwap.getReserves(0);
        
        IERC20(ct).approve(address(whirlpool), type(uint256).max);
        whirlpool.stake(0, bought);
        vm.stopPrank();
        
        (, uint256 cardRAfterStake) = surfSwap.getReserves(0);
        assertEq(cardRAfterStake, cardRAfterBuy + bought, "Reserve should increase by staked amount");
    }

    function testSwapsAffectEffectiveBalance() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        
        // Alice has 2M shares representing 2M tokens out of 9.5M pool
        uint256 aliceShares = whirlpool.stakeOf(0, alice);
        uint256 aliceEffectiveBefore = whirlpool.effectiveBalance(0, alice);
        assertEq(aliceEffectiveBefore, 2_000_000 ether, "Initial effective balance should be 2M");
        
        // Bob buys a lot of tokens (WAVES→CARD), reducing the pool's card reserve
        address ct = router.cardToken(0);
        vm.prank(bob);
        router.createCard{value: 0.05 ether}("C2", "C2", "u2");
        vm.prank(alice);
        waves.transfer(bob, 500 ether);
        
        vm.startPrank(bob);
        waves.approve(address(surfSwap), type(uint256).max);
        surfSwap.swapExact(address(waves), ct, 200 ether, 0);
        vm.stopPrank();
        
        // Alice's shares stay the same, but effective balance decreased
        uint256 aliceSharesAfter = whirlpool.stakeOf(0, alice);
        uint256 aliceEffectiveAfter = whirlpool.effectiveBalance(0, alice);
        
        assertEq(aliceSharesAfter, aliceShares, "Shares should not change");
        assertLt(aliceEffectiveAfter, aliceEffectiveBefore, "Effective balance should decrease after swaps");
    }

    function testFirstStakerGetsOneToOneShares() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        
        // Alice is the first staker with 2M tokens
        uint256 shares = whirlpool.stakeOf(0, alice);
        assertEq(shares, 2_000_000 ether, "First staker should get 1:1 shares");
    }

    function testSubsequentStakersGetProportionalShares() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        
        // Bob gets WAVES and buys tokens
        vm.prank(bob);
        router.createCard{value: 0.05 ether}("C2", "C2", "u2");
        vm.prank(alice);
        waves.transfer(bob, 500 ether);
        
        address ct = router.cardToken(0);
        vm.startPrank(bob);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 bought = surfSwap.swapExact(address(waves), ct, 100 ether, 0);
        
        (uint256 wavesR, uint256 cardR) = surfSwap.getReserves(0);
        uint256 totalSharesBefore = whirlpool.stakeOf(0, alice); // Only Alice has shares
        
        IERC20(ct).approve(address(whirlpool), type(uint256).max);
        whirlpool.stake(0, bought);
        vm.stopPrank();
        
        uint256 bobShares = whirlpool.stakeOf(0, bob);
        // Bob should get: bought * totalShares / cardReserve
        uint256 expectedShares = bought * totalSharesBefore / cardR;
        
        assertApproxEqAbs(bobShares, expectedShares, 1e18, "Bob should get proportional shares");
    }

    function testActiveDefenseViaSwaps() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        address ct = router.cardToken(0);
        
        // Alice initially owns card with 2M shares
        assertEq(whirlpool.ownerOfCard(0), alice);
        uint256 aliceShares = whirlpool.stakeOf(0, alice);
        
        // Bob gets WAVES and buys+stakes MORE shares than Alice
        vm.prank(bob);
        router.createCard{value: 0.05 ether}("C2", "C2", "u2");
        vm.prank(alice);
        waves.transfer(bob, 800 ether);
        
        vm.startPrank(bob);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 bought = surfSwap.swapExact(address(waves), ct, 400 ether, 0);
        IERC20(ct).approve(address(whirlpool), type(uint256).max);
        whirlpool.stake(0, bought);
        vm.stopPrank();
        
        uint256 bobShares = whirlpool.stakeOf(0, bob);
        
        // Bob should now own the card if he has more shares
        if (bobShares > aliceShares) {
            assertEq(whirlpool.ownerOfCard(0), bob, "Bob should own the card with more shares");
        }
    }

    // ═══ WETH STAKING ═══

    function testWethStakeUnstake() public {
        vm.startPrank(alice);
        weth.deposit{value: 5 ether}();
        weth.approve(address(whirlpool), type(uint256).max);
        whirlpool.stakeWETH(5 ether);
        assertEq(whirlpool.userWethStake(alice), 5 ether);
        whirlpool.unstakeWETH(3 ether);
        assertEq(whirlpool.userWethStake(alice), 2 ether);
        assertEq(weth.balanceOf(alice), 3 ether);
        vm.stopPrank();
    }

    // ═══ SECURITY ═══

    function testBidNFTTransfersDisabled() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        vm.prank(alice);
        vm.expectRevert("Transfers disabled");
        bidNFT.transferFrom(alice, bob, 0);
    }

    function testOnlyRouterMintsBidNFT() public {
        vm.prank(alice);
        vm.expectRevert("Only router");
        bidNFT.mint(99, "fake");
    }

    function testOnlyRouterMintsWaves() public {
        vm.expectRevert(abi.encodeWithSignature("OnlyRouter()"));
        waves.mint(alice, 1000 ether);
    }

    // ═══ VIEW FUNCTIONS ═══

    function testGetPrice() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        uint256 price = surfSwap.getPrice(0);
        assertEq(price, uint256(500 ether) * 1e18 / uint256(7_500_000 ether));
    }

    function testTotalCards() public {
        assertEq(router.totalCards(), 0);
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("C1", "C1", "u1");
        assertEq(router.totalCards(), 1);
    }
}
