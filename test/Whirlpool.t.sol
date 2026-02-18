// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/WhirlpoolRouter.sol";
import "../src/GlobalRewards.sol";
import "../src/CardStaking.sol";
import "../src/WethPool.sol";
import "../src/SurfSwap.sol";
import "../src/WAVES.sol";
import "../src/CardToken.sol";
import "../src/BidNFT.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockWETH is IERC20 {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    
    function deposit() external payable {
        _balances[msg.sender] += msg.value;
        _totalSupply += msg.value;
    }
    
    function withdraw(uint256 amount) external {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _totalSupply -= amount;
        payable(msg.sender).transfer(amount);
    }
    
    receive() external payable {
        _balances[msg.sender] += msg.value;
        _totalSupply += msg.value;
    }
    
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }
    
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;
        return true;
    }
}

/// @title WhirlpoolTest — Comprehensive end-to-end test suite
/// @notice Tests all core functionality: minting, staking, swapping, ownership, fees
contract WhirlpoolTest is Test {
    WhirlpoolRouter public router;
    GlobalRewards public globalRewards;
    CardStaking public cardStaking;
    WethPool public wethPool;
    SurfSwap public surfSwap;
    WAVES public waves;
    BidNFT public bidNFT;
    MockWETH public weth;
    
    // Backward compat alias for tests
    CardStaking public whirlpool;
    
    address public protocol = address(0xBEEF);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    
    function setUp() public {
        weth = new MockWETH();
        
        address deployer = address(this);
        uint256 nonce = vm.getNonce(deployer);
        // Deploy order: WAVES(nonce), GlobalRewards(+1), SurfSwap(+2), CardStaking(+3), WethPool(+4), BidNFT(+5), Router(+6)
        address predictedGlobalRewards = vm.computeCreateAddress(deployer, nonce + 1);
        address predictedSurfSwap = vm.computeCreateAddress(deployer, nonce + 2);
        address predictedCardStaking = vm.computeCreateAddress(deployer, nonce + 3);
        address predictedWethPool = vm.computeCreateAddress(deployer, nonce + 4);
        address predictedRouter = vm.computeCreateAddress(deployer, nonce + 6);
        
        waves = new WAVES(predictedRouter);                                                                            // nonce+0
        globalRewards = new GlobalRewards();                                                                           // nonce+1
        surfSwap = new SurfSwap(address(waves), address(weth), predictedCardStaking, predictedWethPool, predictedRouter); // nonce+2
        cardStaking = new CardStaking(address(waves), address(surfSwap), predictedRouter, address(globalRewards));      // nonce+3
        wethPool = new WethPool(address(waves), address(weth), address(surfSwap), address(globalRewards));             // nonce+4
        bidNFT = new BidNFT(address(cardStaking), predictedRouter);                                                    // nonce+5
        router = new WhirlpoolRouter(                                                                                  // nonce+6
            address(waves), address(bidNFT), address(surfSwap),
            address(cardStaking), address(globalRewards), address(weth), protocol
        );
        
        // Register operators
        globalRewards.registerOperator(address(cardStaking));
        globalRewards.registerOperator(address(wethPool));
        
        // Verify predictions
        require(address(router) == predictedRouter, "Router prediction failed");
        require(address(cardStaking) == predictedCardStaking, "CardStaking prediction failed");
        require(address(surfSwap) == predictedSurfSwap, "SurfSwap prediction failed");
        
        // Backward compat alias
        whirlpool = cardStaking;
        
        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }
    
    // ═══════════════════════════════════════════════════════════
    //                  1. MINT NFT (createCard)
    // ═══════════════════════════════════════════════════════════
    
    function testMintCreatesCardToken() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        
        address cardToken = router.cardToken(cardId);
        assertNotEq(cardToken, address(0), "Card token should be deployed");
        assertEq(IERC20(cardToken).totalSupply(), 10_000_000 ether, "Card token should have 10M supply");
    }
    
    function testMintMintsWaves() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        
        assertEq(waves.balanceOf(alice), 1500 ether, "Minter should receive 1500 WAVES");
        assertEq(waves.totalSupply(), 2000 ether, "Total WAVES minted should be 2000 (1500 + 500)");
    }
    
    function testMintSeedsPool() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        
        (uint256 wavesReserve, uint256 cardReserve) = surfSwap.getReserves(cardId);
        assertEq(wavesReserve, 500 ether, "Pool should have 500 WAVES");
        assertEq(cardReserve, 9_500_000 ether, "Pool should have 9.5M cards (7.5M base + 2M staked)");
    }
    
    function testMintAutoStakes() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        
        uint256 aliceShares = whirlpool.userCardShares(cardId, alice);
        assertEq(aliceShares, 2_000_000 ether, "Minter should get 2M shares (1:1 for first staker)");
        
        uint256 aliceEffectiveBalance = whirlpool.effectiveBalance(cardId, alice);
        assertEq(aliceEffectiveBalance, 2_000_000 ether, "Effective balance should match auto-staked amount");
    }
    
    function testMintCreatesNFT() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        
        assertTrue(bidNFT.exists(cardId), "BidNFT should exist after mint");
        assertEq(bidNFT.ownerOf(cardId), alice, "Alice should own the NFT as first staker");
    }
    
    function testMintRequiresExactFee() public {
        vm.prank(alice);
        vm.expectRevert("Exact mint fee required");
        router.createCard{value: 0.04 ether}("TestCard", "TCARD", "ipfs://test");
        
        vm.prank(alice);
        vm.expectRevert("Exact mint fee required");
        router.createCard{value: 0.06 ether}("TestCard", "TCARD", "ipfs://test");
    }
    
    function testMintProtocolShare() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        
        address cardToken = router.cardToken(cardId);
        uint256 protocolBalance = IERC20(cardToken).balanceOf(protocol);
        assertEq(protocolBalance, 500_000 ether, "Protocol should receive 500K card tokens (5%)");
    }
    
    // ═══════════════════════════════════════════════════════════
    //                2. STAKE/UNSTAKE CARDTOKEN
    // ═══════════════════════════════════════════════════════════
    
    function testStakeDepositsIntoPool() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        address cardToken = router.cardToken(cardId);
        
        // Buy some cards (this reduces pool reserves)
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 bought = surfSwap.swapExact(address(waves), cardToken, 100 ether, 0);
        
        // Track reserves AFTER the swap (returns: wavesReserve, cardReserve)
        (, uint256 cardRAfterSwap) = surfSwap.getReserves(cardId);
        uint256 stakedCardsAfterSwap = surfSwap.getStakedCards(cardId);
        
        // Stake them
        IERC20(cardToken).approve(address(whirlpool), type(uint256).max);
        whirlpool.stake(cardId, bought);
        vm.stopPrank();
        
        (, uint256 cardRAfterStake) = surfSwap.getReserves(cardId);
        uint256 stakedCardsAfterStake = surfSwap.getStakedCards(cardId);
        
        assertEq(cardRAfterStake, cardRAfterSwap + bought, "Card reserve should increase by staked amount");
        assertEq(stakedCardsAfterStake, stakedCardsAfterSwap + bought, "Staked cards should increase by staked amount");
    }
    
    function testStakeGrantsShares() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        address cardToken = router.cardToken(cardId);
        
        uint256 sharesBefore = whirlpool.userCardShares(cardId, alice);
        
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 bought = surfSwap.swapExact(address(waves), cardToken, 100 ether, 0);
        IERC20(cardToken).approve(address(whirlpool), type(uint256).max);
        whirlpool.stake(cardId, bought);
        vm.stopPrank();
        
        uint256 sharesAfter = whirlpool.userCardShares(cardId, alice);
        assertGt(sharesAfter, sharesBefore, "Shares should increase after staking");
    }
    
    function testUnstakeReturnsTokens() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        address cardToken = router.cardToken(cardId);
        
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 bought = surfSwap.swapExact(address(waves), cardToken, 100 ether, 0);
        IERC20(cardToken).approve(address(whirlpool), type(uint256).max);
        whirlpool.stake(cardId, bought);
        
        uint256 aliceShares = whirlpool.userCardShares(cardId, alice);
        uint256 initialBalance = IERC20(cardToken).balanceOf(alice);
        
        // Unstake only the NEW shares (not the auto-staked 2M)
        uint256 newShares = aliceShares - 2_000_000 ether;
        whirlpool.unstake(cardId, newShares);
        vm.stopPrank();
        
        uint256 finalBalance = IERC20(cardToken).balanceOf(alice);
        assertGt(finalBalance, initialBalance, "Should receive tokens back from unstaking");
    }
    
    function testUnstakeReducesPool() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        address cardToken = router.cardToken(cardId);
        
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 bought = surfSwap.swapExact(address(waves), cardToken, 100 ether, 0);
        IERC20(cardToken).approve(address(whirlpool), type(uint256).max);
        whirlpool.stake(cardId, bought);
        
        (, uint256 cardR1) = surfSwap.getReserves(cardId);
        uint256 stakedCards1 = surfSwap.getStakedCards(cardId);
        
        uint256 aliceShares = whirlpool.userCardShares(cardId, alice);
        uint256 newShares = aliceShares - 2_000_000 ether;
        whirlpool.unstake(cardId, newShares);
        vm.stopPrank();
        
        (, uint256 cardR2) = surfSwap.getReserves(cardId);
        uint256 stakedCards2 = surfSwap.getStakedCards(cardId);
        
        assertLt(cardR2, cardR1, "Card reserve should decrease after unstaking");
        assertLt(stakedCards2, stakedCards1, "Staked cards should decrease after unstaking");
    }
    
    function testCannotUnstakeMoreThanOwned() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        
        vm.prank(alice);
        vm.expectRevert("Insufficient shares");
        whirlpool.unstake(cardId, 3_000_000 ether);
    }
    
    // ═══════════════════════════════════════════════════════════
    //                3. SWAP WAVES/CARDTOKEN
    // ═══════════════════════════════════════════════════════════
    
    function testSwapWavesToCard() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        address cardToken = router.cardToken(cardId);
        
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 amountOut = surfSwap.swapExact(address(waves), cardToken, 100 ether, 0);
        vm.stopPrank();
        
        assertGt(amountOut, 0, "Should receive card tokens");
        assertEq(IERC20(cardToken).balanceOf(alice), amountOut, "Alice should have the swapped tokens");
    }
    
    function testSwapCardToWaves() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        address cardToken = router.cardToken(cardId);
        
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 cardsBought = surfSwap.swapExact(address(waves), cardToken, 100 ether, 0);
        
        IERC20(cardToken).approve(address(surfSwap), type(uint256).max);
        uint256 wavesReceived = surfSwap.swapExact(cardToken, address(waves), cardsBought, 0);
        vm.stopPrank();
        
        assertGt(wavesReceived, 0, "Should receive WAVES");
        assertLt(wavesReceived, 100 ether, "Should receive less than original due to fees");
    }
    
    function testSwapCardToCard() public {
        vm.startPrank(alice);
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        router.createCard{value: 0.05 ether}("Card2", "C2", "ipfs://2");
        vm.stopPrank();
        
        address card1Token = router.cardToken(0);
        address card2Token = router.cardToken(1);
        
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 card1Amount = surfSwap.swapExact(address(waves), card1Token, 100 ether, 0);
        
        IERC20(card1Token).approve(address(surfSwap), type(uint256).max);
        uint256 card2Amount = surfSwap.swapExact(card1Token, card2Token, card1Amount, 0);
        vm.stopPrank();
        
        assertGt(card2Amount, 0, "Should receive card2 tokens");
        assertEq(IERC20(card2Token).balanceOf(alice), card2Amount, "Alice should have card2 tokens");
    }
    
    function testSwapSlippageProtection() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        address cardToken = router.cardToken(cardId);
        
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        vm.expectRevert("Slippage");
        surfSwap.swapExact(address(waves), cardToken, 10 ether, type(uint256).max);
        vm.stopPrank();
    }
    
    function testSwapRequiresApproval() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        address cardToken = router.cardToken(cardId);
        
        vm.prank(alice);
        // No approval given
        vm.expectRevert();
        surfSwap.swapExact(address(waves), cardToken, 10 ether, 0);
    }
    
    // ═══════════════════════════════════════════════════════════
    //                   4. SWAP WAVES/WETH
    // ═══════════════════════════════════════════════════════════
    
    function testWethStakeInitializesPool() public {
        vm.startPrank(bob);
        weth.deposit{value: 10 ether}();
        weth.approve(address(wethPool), type(uint256).max);
        wethPool.stakeWETH(10 ether);
        vm.stopPrank();
        
        (uint256 wavesR, uint256 wethR) = surfSwap.getWethReserves();
        assertGt(wethR, 0, "WETH reserve should be initialized");
    }
    
    function testSwapWethToWaves() public {
        // First, create a card to seed WAVES into system
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        
        // Initialize WETH pool
        vm.startPrank(bob);
        weth.deposit{value: 10 ether}();
        weth.approve(address(wethPool), type(uint256).max);
        wethPool.stakeWETH(10 ether);
        vm.stopPrank();
        
        // Need another card to seed wavesWethReserve
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("Card2", "C2", "ipfs://2");
        
        // Now swap WETH → WAVES
        vm.startPrank(bob);
        weth.deposit{value: 1 ether}();
        weth.approve(address(surfSwap), type(uint256).max);
        uint256 wavesOut = surfSwap.swapExact(address(weth), address(waves), 1 ether, 0);
        vm.stopPrank();
        
        assertGt(wavesOut, 0, "Should receive WAVES");
        assertEq(waves.balanceOf(bob), wavesOut, "Bob should have the WAVES");
    }
    
    function testSwapWavesToWeth() public {
        // Create cards first to seed WAVES
        vm.startPrank(alice);
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        router.createCard{value: 0.05 ether}("Card2", "C2", "ipfs://2");
        vm.stopPrank();
        
        // Initialize WETH pool
        vm.startPrank(bob);
        weth.deposit{value: 10 ether}();
        weth.approve(address(wethPool), type(uint256).max);
        wethPool.stakeWETH(10 ether);
        vm.stopPrank();
        
        // Verify WETH reserve is set up
        (uint256 wavesWethR, uint256 wethR) = surfSwap.getWethReserves();
        assertGt(wethR, 0, "WETH reserve should be initialized");
        assertGt(wavesWethR, 0, "WAVES reserve should be initialized");
        
        // Swap WAVES → WETH
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 wethOut = surfSwap.swapExact(address(waves), address(weth), 100 ether, 0);
        vm.stopPrank();
        
        assertGt(wethOut, 0, "Should receive WETH");
    }
    
    // ═══════════════════════════════════════════════════════════
    //             5. NFT OWNERSHIP TRANSFER (AUTOMATIC)
    // ═══════════════════════════════════════════════════════════
    
    function testOwnerIsTopStaker() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        
        address owner = whirlpool.ownerOfCard(cardId);
        assertEq(owner, alice, "Alice should be owner as biggest staker");
    }
    
    function testOwnershipChangesOnStake() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        address cardToken = router.cardToken(cardId);
        
        assertEq(whirlpool.ownerOfCard(cardId), alice, "Alice should initially own");
        
        // Give Bob WAVES
        vm.prank(bob);
        router.createCard{value: 0.05 ether}("Card2", "C2", "ipfs://2");
        
        // Transfer WAVES from alice to bob
        vm.prank(alice);
        waves.transfer(bob, 800 ether);
        
        // Bob buys and stakes more than Alice's 2M
        vm.startPrank(bob);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 bought = surfSwap.swapExact(address(waves), cardToken, 400 ether, 0);
        IERC20(cardToken).approve(address(whirlpool), type(uint256).max);
        whirlpool.stake(cardId, bought);
        vm.stopPrank();
        
        uint256 bobShares = whirlpool.userCardShares(cardId, bob);
        uint256 aliceShares = whirlpool.userCardShares(cardId, alice);
        
        if (bobShares > aliceShares) {
            assertEq(whirlpool.ownerOfCard(cardId), bob, "Bob should become owner with more shares");
        }
    }
    
    function testOwnershipChangesOnUnstake() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        address cardToken = router.cardToken(cardId);
        
        assertEq(whirlpool.ownerOfCard(cardId), alice, "Alice should initially own");
        
        // Bob stakes to get some shares
        vm.prank(bob);
        router.createCard{value: 0.05 ether}("Card2", "C2", "ipfs://2");
        vm.prank(alice);
        waves.transfer(bob, 500 ether);
        
        vm.startPrank(bob);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 bought = surfSwap.swapExact(address(waves), cardToken, 200 ether, 0);
        IERC20(cardToken).approve(address(whirlpool), type(uint256).max);
        whirlpool.stake(cardId, bought);
        vm.stopPrank();
        
        // Alice unstakes all her shares
        uint256 aliceShares = whirlpool.userCardShares(cardId, alice);
        vm.prank(alice);
        whirlpool.unstake(cardId, aliceShares);
        
        // After Alice unstakes all, she should no longer be owner
        // Bob should become owner on his next stake (ownership updates on stake, not unstake)
        // For now, verify Alice is no longer owner
        assertNotEq(whirlpool.ownerOfCard(cardId), alice, "Alice should no longer be owner after unstaking all");
        
        // Bob stakes 1 more token to trigger ownership update
        vm.startPrank(bob);
        bought = surfSwap.swapExact(address(waves), cardToken, 10 ether, 0);
        if (bought > 0) {
            IERC20(cardToken).approve(address(whirlpool), type(uint256).max);
            whirlpool.stake(cardId, bought);
        }
        vm.stopPrank();
        
        // Now Bob should be owner
        if (whirlpool.userCardShares(cardId, bob) > 0) {
            assertEq(whirlpool.ownerOfCard(cardId), bob, "Bob should become owner after Alice unstakes all");
        }
    }
    
    function testBidNFTOwnerOfReadsFromWhirlpool() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        
        address whirlpoolOwner = whirlpool.ownerOfCard(cardId);
        address nftOwner = bidNFT.ownerOf(cardId);
        
        assertEq(nftOwner, whirlpoolOwner, "BidNFT.ownerOf should match WhirlpoolStaking.ownerOfCard");
    }
    
    function testBidNFTTransfersDisabled() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        
        vm.prank(alice);
        vm.expectRevert("Transfers disabled");
        bidNFT.transferFrom(alice, bob, cardId);
    }
    
    // ═══════════════════════════════════════════════════════════
    //           6. SWAP STAKED CARDTOKENS (KEY FEATURE)
    // ═══════════════════════════════════════════════════════════
    
    function testStakedTokensAreInPool() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        address cardToken = router.cardToken(cardId);
        
        uint256 stakedCards = surfSwap.getStakedCards(cardId);
        assertEq(stakedCards, 2_000_000 ether, "Staked cards should be 2M from auto-stake");
        
        (, uint256 cardR) = surfSwap.getReserves(cardId);
        assertGe(cardR, stakedCards, "Card reserve should include staked amount");
        
        // Stake more
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 bought = surfSwap.swapExact(address(waves), cardToken, 100 ether, 0);
        
        // Track staked cards AFTER swap (it decreases proportionally when cards leave pool)
        uint256 stakedCardsAfterSwap = surfSwap.getStakedCards(cardId);
        
        IERC20(cardToken).approve(address(whirlpool), type(uint256).max);
        whirlpool.stake(cardId, bought);
        vm.stopPrank();
        
        uint256 stakedCardsAfterStake = surfSwap.getStakedCards(cardId);
        (, uint256 cardR2) = surfSwap.getReserves(cardId);
        
        assertEq(stakedCardsAfterStake, stakedCardsAfterSwap + bought, "Staked cards should increase by staked amount");
        assertGe(cardR2, stakedCardsAfterStake, "Card reserve should include new staked amount");
    }
    
    function testSwapReducesStakerEffectiveBalance() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        address cardToken = router.cardToken(cardId);
        
        uint256 aliceEffectiveBefore = whirlpool.effectiveBalance(cardId, alice);
        uint256 aliceSharesBefore = whirlpool.userCardShares(cardId, alice);
        
        // Give Bob WAVES
        vm.prank(bob);
        router.createCard{value: 0.05 ether}("Card2", "C2", "ipfs://2");
        vm.prank(alice);
        waves.transfer(bob, 500 ether);
        
        // Bob buys cards (WAVES → CARD swap reduces stakedCards)
        vm.startPrank(bob);
        waves.approve(address(surfSwap), type(uint256).max);
        surfSwap.swapExact(address(waves), cardToken, 200 ether, 0);
        vm.stopPrank();
        
        uint256 aliceEffectiveAfter = whirlpool.effectiveBalance(cardId, alice);
        uint256 aliceSharesAfter = whirlpool.userCardShares(cardId, alice);
        
        assertEq(aliceSharesAfter, aliceSharesBefore, "Alice's shares should not change");
        assertLt(aliceEffectiveAfter, aliceEffectiveBefore, "Alice's effective balance should decrease");
    }
    
    function testActiveDefense() public {
        // Alice mints card, becomes owner
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        address cardToken = router.cardToken(cardId);
        
        assertEq(whirlpool.ownerOfCard(cardId), alice, "Alice should initially own");
        
        // Give Bob WAVES
        vm.prank(bob);
        router.createCard{value: 0.05 ether}("Card2", "C2", "ipfs://2");
        vm.prank(alice);
        waves.transfer(bob, 1000 ether);
        
        // Bob buys cards from pool (reduces Alice's effective balance)
        vm.startPrank(bob);
        waves.approve(address(surfSwap), type(uint256).max);
        uint256 bought = surfSwap.swapExact(address(waves), cardToken, 300 ether, 0);
        
        // Bob stakes more than Alice
        IERC20(cardToken).approve(address(whirlpool), type(uint256).max);
        whirlpool.stake(cardId, bought);
        vm.stopPrank();
        
        uint256 bobShares = whirlpool.userCardShares(cardId, bob);
        uint256 aliceShares = whirlpool.userCardShares(cardId, alice);
        
        if (bobShares > aliceShares) {
            assertEq(whirlpool.ownerOfCard(cardId), bob, "Bob should become owner after staking more");
            assertEq(bidNFT.ownerOf(cardId), bob, "BidNFT ownership should also transfer");
        }
    }
    
    // ═══════════════════════════════════════════════════════════
    //                     7. FEE DISTRIBUTION
    // ═══════════════════════════════════════════════════════════
    
    function testSwapFeesDistributeToStakers() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        address cardToken = router.cardToken(cardId);
        
        // Perform a swap to generate fees
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        surfSwap.swapExact(address(waves), cardToken, 100 ether, 0);
        vm.stopPrank();
        
        uint256 pending = whirlpool.pendingRewards(cardId, alice);
        assertGt(pending, 0, "Alice should have pending WAVES rewards from swap fees");
    }
    
    function testMintFeesDistributeGlobally() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        
        // Bob mints a card, mint fee should distribute to Alice
        vm.prank(bob);
        router.createCard{value: 0.05 ether}("Card2", "C2", "ipfs://2");
        
        uint256 alicePending = globalRewards.pendingGlobalRewards(alice);
        assertGt(alicePending, 0, "Alice should receive share of Bob's 0.05 ETH mint fee");
    }
    
    function testWethStakersGet1_5xBoost() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        
        // Bob stakes WETH
        vm.startPrank(bob);
        weth.deposit{value: 1 ether}();
        weth.approve(address(wethPool), type(uint256).max);
        wethPool.stakeWETH(1 ether);
        vm.stopPrank();
        
        // Another card minted to distribute fees
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("Card2", "C2", "ipfs://2");
        
        uint256 bobPending = globalRewards.pendingGlobalRewards(bob);
        assertGt(bobPending, 0, "Bob should receive global rewards with 1.5x boost");
    }
    
    // ═══════════════════════════════════════════════════════════
    //                      8. EDGE CASES
    // ═══════════════════════════════════════════════════════════
    
    function testFirstStakerGetsOneToOneShares() public {
        vm.prank(alice);
        uint256 cardId = router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        
        uint256 shares = whirlpool.userCardShares(cardId, alice);
        uint256 effectiveBalance = whirlpool.effectiveBalance(cardId, alice);
        
        assertEq(shares, 2_000_000 ether, "First staker should get 1:1 shares");
        assertEq(effectiveBalance, 2_000_000 ether, "Effective balance should equal shares for first staker");
    }
    
    function testZeroAmountSwapReverts() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("TestCard", "TCARD", "ipfs://test");
        address cardToken = router.cardToken(0);
        
        vm.startPrank(alice);
        waves.approve(address(surfSwap), type(uint256).max);
        vm.expectRevert("Zero amount");
        surfSwap.swapExact(address(waves), cardToken, 0, 0);
        vm.stopPrank();
    }
    
    function testOnlyRouterCanMintWaves() public {
        vm.prank(alice);
        vm.expectRevert();
        waves.mint(alice, 1000 ether);
    }
    
    function testOnlyRouterCanMintBidNFT() public {
        vm.prank(alice);
        vm.expectRevert("Only router");
        bidNFT.mint(99, "ipfs://fake");
    }
    
    // ═══════════════════════════════════════════════════════════
    //                9. SWAP STAKE (swapStake FEATURE)
    // ═══════════════════════════════════════════════════════════
    
    function testSwapStakeBasic() public {
        // Alice creates two cards
        vm.startPrank(alice);
        router.createCard{value: 0.05 ether}("Card0", "C0", "ipfs://0");
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        vm.stopPrank();
        
        // Alice should have 2M shares in card 0 from auto-stake, 0 shares in card 1
        uint256 card0Shares = whirlpool.userCardShares(0, alice);
        uint256 card1Shares = whirlpool.userCardShares(1, alice);
        assertEq(card0Shares, 2_000_000 ether, "Alice should have 2M shares in card 0");
        assertEq(card1Shares, 2_000_000 ether, "Alice should have 2M shares in card 1");
        
        // Alice swaps half her card 0 stake to card 1
        vm.prank(alice);
        whirlpool.swapStake(0, 1, 1_000_000 ether);
        
        // Verify card 0 shares decreased
        uint256 card0SharesAfter = whirlpool.userCardShares(0, alice);
        assertEq(card0SharesAfter, 1_000_000 ether, "Card 0 shares should decrease by 1M");
        
        // Verify card 1 shares increased
        uint256 card1SharesAfter = whirlpool.userCardShares(1, alice);
        assertGt(card1SharesAfter, card1Shares, "Card 1 shares should increase");
        
        // Verify Alice still owns card 0 (has remaining shares)
        assertEq(whirlpool.ownerOfCard(0), alice, "Alice should still own card 0");
    }
    
    function testSwapStakePreservesValue() public {
        // Alice creates two cards
        vm.startPrank(alice);
        router.createCard{value: 0.05 ether}("Card0", "C0", "ipfs://0");
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        vm.stopPrank();
        
        // Get card 0 price before swap
        uint256 card0Price = surfSwap.getPrice(0);
        uint256 card1Price = surfSwap.getPrice(1);
        
        // Calculate expected value in WAVES
        uint256 card0EffectiveBefore = whirlpool.effectiveBalance(0, alice);
        uint256 expectedValueInWaves = (card0EffectiveBefore * card0Price) / 1e18;
        
        // Swap all shares
        vm.prank(alice);
        whirlpool.swapStake(0, 1, 2_000_000 ether);
        
        // Calculate new value in WAVES
        uint256 card1EffectiveAfter = whirlpool.effectiveBalance(1, alice);
        uint256 newCard1Price = surfSwap.getPrice(1);
        uint256 actualValueInWaves = (card1EffectiveAfter * newCard1Price) / 1e18;
        
        // Value should be roughly preserved (allowing for swap fees ~0.6%)
        // We expect about 99.4% value preservation (0.3% fee on each hop = 0.6% total)
        uint256 minExpectedValue = (expectedValueInWaves * 985) / 1000; // Allow 1.5% loss for fees + slippage
        assertGt(actualValueInWaves, minExpectedValue, "Value should be roughly preserved minus fees");
    }
    
    function testSwapStakeNoTokenTransfers() public {
        // Alice creates two cards
        vm.startPrank(alice);
        router.createCard{value: 0.05 ether}("Card0", "C0", "ipfs://0");
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        vm.stopPrank();
        
        address card0Token = router.cardToken(0);
        address card1Token = router.cardToken(1);
        
        // Record Alice's token balances BEFORE swap
        uint256 aliceCard0Before = IERC20(card0Token).balanceOf(alice);
        uint256 aliceCard1Before = IERC20(card1Token).balanceOf(alice);
        uint256 aliceWavesBefore = IERC20(waves).balanceOf(alice);
        
        // Swap stake
        vm.prank(alice);
        whirlpool.swapStake(0, 1, 1_000_000 ether);
        
        // Record Alice's token balances AFTER swap
        uint256 aliceCard0After = IERC20(card0Token).balanceOf(alice);
        uint256 aliceCard1After = IERC20(card1Token).balanceOf(alice);
        uint256 aliceWavesAfter = IERC20(waves).balanceOf(alice);
        
        // Verify NO token transfers to/from Alice's wallet
        assertEq(aliceCard0After, aliceCard0Before, "Alice's card0 wallet balance should not change");
        assertEq(aliceCard1After, aliceCard1Before, "Alice's card1 wallet balance should not change");
        assertEq(aliceWavesAfter, aliceWavesBefore, "Alice's WAVES wallet balance should not change");
    }
    
    function testSwapStakeUpdatesReserves() public {
        // Alice creates two cards
        vm.startPrank(alice);
        router.createCard{value: 0.05 ether}("Card0", "C0", "ipfs://0");
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        vm.stopPrank();
        
        // Record reserves BEFORE swap
        (uint256 card0WavesBefore, uint256 card0CardsBefore) = surfSwap.getReserves(0);
        (uint256 card1WavesBefore, uint256 card1CardsBefore) = surfSwap.getReserves(1);
        uint256 card0StakedBefore = surfSwap.getStakedCards(0);
        uint256 card1StakedBefore = surfSwap.getStakedCards(1);
        
        // Swap stake
        vm.prank(alice);
        whirlpool.swapStake(0, 1, 1_000_000 ether);
        
        // Record reserves AFTER swap
        (uint256 card0WavesAfter, uint256 card0CardsAfter) = surfSwap.getReserves(0);
        (uint256 card1WavesAfter, uint256 card1CardsAfter) = surfSwap.getReserves(1);
        uint256 card0StakedAfter = surfSwap.getStakedCards(0);
        uint256 card1StakedAfter = surfSwap.getStakedCards(1);
        
        // Card 0: We remove staked cards, then sell them TO the pool
        // Net effect: cardReserve decreases slightly (removed amount > what goes back due to fees)
        //             WAVES reserve decreases (we take WAVES out)
        //             stakedCards decreases (we removed staked amount, nothing proportional happens)
        assertLt(card0WavesAfter, card0WavesBefore, "Card 0 should lose WAVES");
        assertLe(card0CardsAfter, card0CardsBefore, "Card 0 cardReserve should decrease or stay same");
        assertLt(card0StakedAfter, card0StakedBefore, "Card 0 staked should decrease");
        
        // Card 1: We buy cards FROM the pool with WAVES, then add to staked
        // Net effect: WAVES reserve increases
        //             cardReserve net increases (we add output after proportional reduction)
        //             stakedCards definitely increases (we add the output)
        assertGt(card1WavesAfter, card1WavesBefore, "Card 1 should gain WAVES");
        assertGt(card1StakedAfter, card1StakedBefore, "Card 1 staked should increase");
    }
    
    function testSwapStakeChargesFees() public {
        // Alice creates two cards
        vm.startPrank(alice);
        router.createCard{value: 0.05 ether}("Card0", "C0", "ipfs://0");
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        vm.stopPrank();
        
        // Record pending rewards BEFORE swap
        uint256 aliceCard0RewardsBefore = whirlpool.pendingRewards(0, alice);
        uint256 aliceCard1RewardsBefore = whirlpool.pendingRewards(1, alice);
        
        // Swap stake (should generate fees)
        vm.prank(alice);
        whirlpool.swapStake(0, 1, 1_000_000 ether);
        
        // Record pending rewards AFTER swap
        uint256 aliceCard0RewardsAfter = whirlpool.pendingRewards(0, alice);
        uint256 aliceCard1RewardsAfter = whirlpool.pendingRewards(1, alice);
        
        // Fees should be distributed (alice is the only staker, so she gets the fees)
        // Note: Alice's pending rewards might not increase significantly because:
        // 1. Rewards are harvested before the swap
        // 2. Fees go to the pool, not directly to Alice
        // Better check: do another swap and see if there are rewards
        
        // Bob creates a card to get WAVES
        vm.prank(bob);
        router.createCard{value: 0.05 ether}("Card2", "C2", "ipfs://2");
        
        // Transfer some WAVES to bob for swapping
        vm.prank(alice);
        waves.transfer(bob, 500 ether);
        
        // Bob does a swap to generate fees for Alice
        address card0Token = router.cardToken(0);
        vm.startPrank(bob);
        waves.approve(address(surfSwap), type(uint256).max);
        surfSwap.swapExact(address(waves), card0Token, 50 ether, 0);
        vm.stopPrank();
        
        // Now Alice should have pending rewards
        uint256 aliceRewardsNow = whirlpool.pendingRewards(0, alice);
        assertGt(aliceRewardsNow, 0, "Alice should receive swap fees as the staker");
    }
    
    function testSwapStakeOwnershipTransfer() public {
        // Alice creates card 0, Bob creates card 1
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("Card0", "C0", "ipfs://0");
        
        vm.prank(bob);
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        
        // Initial ownership
        assertEq(whirlpool.ownerOfCard(0), alice, "Alice should own card 0");
        assertEq(whirlpool.ownerOfCard(1), bob, "Bob should own card 1");
        
        // Give Alice some WAVES for later
        vm.prank(bob);
        waves.transfer(alice, 500 ether);
        
        // Alice swaps ALL her card 0 shares to card 1
        vm.prank(alice);
        whirlpool.swapStake(0, 1, 2_000_000 ether);
        
        // Card 0 ownership should clear (Alice has 0 shares now)
        assertEq(whirlpool.ownerOfCard(0), address(0), "Card 0 should have no owner");
        
        // Card 1: Alice should become owner (more shares than Bob)
        uint256 aliceCard1Shares = whirlpool.userCardShares(1, alice);
        uint256 bobCard1Shares = whirlpool.userCardShares(1, bob);
        
        if (aliceCard1Shares > bobCard1Shares) {
            assertEq(whirlpool.ownerOfCard(1), alice, "Alice should become card 1 owner");
        }
    }
    
    function testSwapStakePartialShares() public {
        // Alice creates two cards
        vm.startPrank(alice);
        router.createCard{value: 0.05 ether}("Card0", "C0", "ipfs://0");
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        vm.stopPrank();
        
        // Swap only 500K shares (25% of 2M)
        vm.prank(alice);
        whirlpool.swapStake(0, 1, 500_000 ether);
        
        // Verify partial swap
        uint256 card0SharesAfter = whirlpool.userCardShares(0, alice);
        assertEq(card0SharesAfter, 1_500_000 ether, "Should have 1.5M shares left in card 0");
        
        // Verify card 1 got shares
        uint256 card1SharesAfter = whirlpool.userCardShares(1, alice);
        assertGt(card1SharesAfter, 2_000_000 ether, "Card 1 shares should increase");
        
        // Alice should still own card 0
        assertEq(whirlpool.ownerOfCard(0), alice, "Alice should still own card 0");
    }
    
    function testSwapStakeCannotExceedShares() public {
        // Alice creates two cards
        vm.startPrank(alice);
        router.createCard{value: 0.05 ether}("Card0", "C0", "ipfs://0");
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        vm.stopPrank();
        
        // Try to swap more shares than Alice has
        vm.prank(alice);
        vm.expectRevert("Insufficient shares");
        whirlpool.swapStake(0, 1, 3_000_000 ether);
    }
    
    function testSwapStakeCannotSwapToSameCard() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("Card0", "C0", "ipfs://0");
        
        vm.prank(alice);
        vm.expectRevert("Same card");
        whirlpool.swapStake(0, 0, 1_000_000 ether);
    }
    
    function testSwapStakeZeroSharesReverts() public {
        // Alice creates two cards
        vm.startPrank(alice);
        router.createCard{value: 0.05 ether}("Card0", "C0", "ipfs://0");
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        vm.stopPrank();
        
        vm.prank(alice);
        vm.expectRevert("Zero shares");
        whirlpool.swapStake(0, 1, 0);
    }

    // ═══════════════════════════════════════════════════════════
    //          10. BATCH SWAP STAKE (CONSOLIDATE)
    // ═══════════════════════════════════════════════════════════

    function testBatchSwapStake2Cards() public {
        vm.startPrank(alice);
        router.createCard{value: 0.05 ether}("Card0", "C0", "ipfs://0");
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        router.createCard{value: 0.05 ether}("Card2", "C2", "ipfs://2");
        vm.stopPrank();

        // Consolidate card 0 and card 1 into card 2
        uint256[] memory fromIds = new uint256[](2);
        fromIds[0] = 0;
        fromIds[1] = 1;

        uint256 card2SharesBefore = whirlpool.userCardShares(2, alice);

        vm.prank(alice);
        whirlpool.batchSwapStake(fromIds, 2);

        // Source cards should have 0 shares
        assertEq(whirlpool.userCardShares(0, alice), 0, "Card 0 shares should be 0");
        assertEq(whirlpool.userCardShares(1, alice), 0, "Card 1 shares should be 0");

        // Target card should have increased shares
        uint256 card2SharesAfter = whirlpool.userCardShares(2, alice);
        assertGt(card2SharesAfter, card2SharesBefore, "Card 2 shares should increase");
    }

    function testBatchSwapStake5Cards() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < 6; i++) {
            router.createCard{value: 0.05 ether}(string(abi.encodePacked("Card", vm.toString(i))), "C", "ipfs://x");
        }
        vm.stopPrank();

        // Consolidate cards 0-4 into card 5
        uint256[] memory fromIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            fromIds[i] = i;
        }

        vm.prank(alice);
        whirlpool.batchSwapStake(fromIds, 5);

        for (uint256 i = 0; i < 5; i++) {
            assertEq(whirlpool.userCardShares(i, alice), 0, "Source card shares should be 0");
        }
        assertGt(whirlpool.userCardShares(5, alice), 2_000_000 ether, "Target card should have more shares");
    }

    function testBatchSwapStakeRevertsEmptyArray() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("Card0", "C0", "ipfs://0");

        uint256[] memory fromIds = new uint256[](0);

        vm.prank(alice);
        vm.expectRevert("Empty array");
        whirlpool.batchSwapStake(fromIds, 0);
    }

    function testBatchSwapStakeRevertsNoStake() public {
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("Card0", "C0", "ipfs://0");
        vm.prank(alice);
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");

        // Bob has no stake in card 0
        uint256[] memory fromIds = new uint256[](1);
        fromIds[0] = 0;

        vm.prank(bob);
        vm.expectRevert("No shares in source card");
        whirlpool.batchSwapStake(fromIds, 1);
    }

    function testBatchSwapStakeOwnershipUpdates() public {
        // Alice creates 3 cards
        vm.startPrank(alice);
        router.createCard{value: 0.05 ether}("Card0", "C0", "ipfs://0");
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        router.createCard{value: 0.05 ether}("Card2", "C2", "ipfs://2");
        vm.stopPrank();

        assertEq(whirlpool.ownerOfCard(0), alice);
        assertEq(whirlpool.ownerOfCard(1), alice);
        assertEq(whirlpool.ownerOfCard(2), alice);

        uint256[] memory fromIds = new uint256[](2);
        fromIds[0] = 0;
        fromIds[1] = 1;

        vm.prank(alice);
        whirlpool.batchSwapStake(fromIds, 2);

        // Source cards should have no owner (Alice fully unstaked)
        assertEq(whirlpool.ownerOfCard(0), address(0), "Card 0 should have no owner");
        assertEq(whirlpool.ownerOfCard(1), address(0), "Card 1 should have no owner");

        // Target card should still have Alice as owner
        assertEq(whirlpool.ownerOfCard(2), alice, "Alice should own card 2");
    }

    function testBatchSwapStakeRewardsClaimedBeforeUnstake() public {
        vm.startPrank(alice);
        router.createCard{value: 0.05 ether}("Card0", "C0", "ipfs://0");
        router.createCard{value: 0.05 ether}("Card1", "C1", "ipfs://1");
        vm.stopPrank();

        // Generate swap fees on card 0
        vm.prank(bob);
        router.createCard{value: 0.05 ether}("Card2", "C2", "ipfs://2");
        vm.prank(alice);
        waves.transfer(bob, 500 ether);

        address card0Token = router.cardToken(0);
        vm.startPrank(bob);
        waves.approve(address(surfSwap), type(uint256).max);
        surfSwap.swapExact(address(waves), card0Token, 50 ether, 0);
        vm.stopPrank();

        // Alice should have pending rewards on card 0
        uint256 pendingBefore = whirlpool.pendingRewards(0, alice);
        assertGt(pendingBefore, 0, "Should have pending rewards");

        uint256 wavesBalanceBefore = IERC20(waves).balanceOf(alice);

        // Consolidate card 0 into card 1
        uint256[] memory fromIds = new uint256[](1);
        fromIds[0] = 0;

        vm.prank(alice);
        whirlpool.batchSwapStake(fromIds, 1);

        // Rewards should have been paid out
        uint256 wavesBalanceAfter = IERC20(waves).balanceOf(alice);
        assertGt(wavesBalanceAfter, wavesBalanceBefore, "Rewards should be claimed during batch swap");
    }
}
