# Items Under Review

This document tracks issues, edge cases, and optimizations that need review before mainnet deployment.

## Status

**Current Test Results**: ✅ 51/51 passing (includes swapStake, batch etc.)

**Contract Sizes** (post-refactor + viaIR):
- WhirlpoolRouter: ~7.2 KB ✅
- CardStaking: ~10.4 KB ✅
- SurfSwap: ~6.7 KB ✅ (no longer near limit)
- WethPool: ~4.7 KB ✅
- BidNFT: ~3 KB ✅
- WAVES: ~2 KB ✅
- CardToken: ~1.7 KB ✅
- GlobalRewards: ~1.8 KB ✅

## Fixed Issues

### 1. Test Failures (RESOLVED ✅)

**Issue**: Two tests were failing due to outdated expectations after refactoring to LP-staking architecture.

#### testGetPrice

**Expected**: Price = `500e18 * 1e18 / 7.5Me18` (assuming only base AMM liquidity)  
**Actual**: Price = `500e18 * 1e18 / 9.5Me18` (includes staked tokens)

**Root Cause**: Test written before LP-staking was implemented. The pool reserve includes both:
- 7.5M base AMM liquidity
- 2M auto-staked tokens (from minter)

**Resolution**: Updated test expectation to reflect actual pool composition (9.5M total).

**Contract Behavior**: ✅ Correct. The price formula uses total `cardReserve`, which includes staked tokens that are tradeable.

#### testSubsequentStakersGetProportionalShares

**Expected**: `shares = bought * totalShares / cardReserve`  
**Actual**: `shares = bought * totalShares / stakedCards`

**Root Cause**: Share calculation should use `stakedCards` (the staked portion) not `cardReserve` (total pool).

**Why**: When you stake, your share of ownership is relative to the **staked liquidity**, not the entire pool. The base 7.5M AMM liquidity is permanent and not part of the ownership game.

**Resolution**: Updated test to use `surfSwap.getStakedCards(0)` for expected calculation.

**Contract Behavior**: ✅ Correct. `WhirlpoolStaking.sol` correctly uses:
```solidity
uint256 currentStaked = ISurfSwap(surfSwap).getStakedCards(cardId);
sharesToMint = amount * cs.totalShares / currentStaked;
```

## Active Review Items

### 2. Contract Size Optimization

**Status**: ✅ RESOLVED (no longer a blocker)

**Issue**: Previously ~22KB (required code-size override), but after full refactor + optimizer/viaIR, now ~6.7KB.

**Current**: All contracts comfortably under EIP-170 (SurfSwap 6.7KB, CardStaking 10.4KB etc). See sizes above.

**Recommendation**: No further action required for size. (Optimizations like custom errors could still be applied for future cleanliness if desired.)

### 3. stakedCards Proportional Tracking

**Status**: 🔍 NEEDS REVIEW

**Implementation**: When swaps occur, `stakedCards` adjusts proportionally to maintain constant percentage:

```solidity
// When tokens LEAVE pool (WAVES → CARD):
uint256 stakedReduction = amountOut * pool.stakedCards / pool.cardReserve;
pool.stakedCards -= stakedReduction;

// When tokens ENTER pool (CARD → WAVES):
uint256 stakedIncrease = addedCards * pool.stakedCards / pool.cardReserve;
pool.stakedCards += stakedIncrease;
```

**Intended Behavior**: Maintain `stakedCards / cardReserve` ratio constant across swaps.

**Edge Cases to Consider**:

1. **Rounding Errors**: Integer division rounds down. Over thousands of swaps, does drift occur?
   
   **Analysis**:
   - Each swap: < 1 wei loss
   - 10,000 swaps: < 10,000 wei = 0.00001 tokens
   - **Impact**: Negligible
   
2. **Zero Division**: If `cardReserve = 0` (impossible) or `stakedCards = 0`:
   ```solidity
   stakedReduction = amountOut * 0 / pool.cardReserve = 0 ✅
   ```
   Handles gracefully.

3. **Overflow**: If `stakedReduction > stakedCards`:
   ```solidity
   if (stakedReduction > pool.stakedCards) stakedReduction = pool.stakedCards;
   pool.stakedCards -= stakedReduction;
   ```
   ✅ Already protected.

4. **Large Swaps**: If someone buys entire staked portion:
   ```solidity
   // Before: stakedCards = 2M, cardReserve = 9.5M
   // User buys 2M tokens
   stakedReduction = 2M * 2M / 9.5M = 421,052
   // After: stakedCards = 1.578M
   ```
   ✅ Proportional reduction is correct.

**Recommendation**: ✅ Logic is sound. Add fuzzing tests for edge cases:
```solidity
function testFuzz_StakedCardsRatio(uint256 swapAmount) public {
    // Verify stakedCards / cardReserve stays constant
}
```

### 4. Gas Optimization Opportunities

**Status**: 💡 NICE-TO-HAVE

**Current Costs** (from tests):
- Card-to-card swap: ~280K gas ⚠️
- Single swap: ~150K gas ✅
- Stake: ~180K gas ✅
- Unstake: ~200K gas ✅

**Comparison** (Uniswap V2 swap: ~110K gas)

**Optimizations**:

1. **Reduce Card-to-Card Swap Cost**:
   - Current: Two full swaps (CARD_A → WAVES → CARD_B)
   - Optimization: Combine into single transaction with shared state
   - Potential savings: ~50K gas (18%)

2. **Cache Storage Reads**:
   ```solidity
   // Before:
   pool.cardReserve += amount;  // SLOAD + SSTORE
   pool.stakedCards += amount;  // SLOAD + SSTORE
   
   // After:
   uint256 cardR = pool.cardReserve;  // SLOAD
   uint256 stakedC = pool.stakedCards; // SLOAD
   cardR += amount;
   stakedC += amount;
   pool.cardReserve = cardR;  // SSTORE
   pool.stakedCards = stakedC; // SSTORE
   ```
   Savings: ~5K gas per swap

3. **Batch Harvesting**:
   - Add `harvestAll(uint256[] cardIds)` to claim rewards from multiple cards
   - Savings: ~30K gas per additional card (vs separate calls)

**Priority**: Low (gas costs are acceptable, mainnet users will optimize themselves)

### 5. Share Calculation Rounding

**Status**: 🔍 NEEDS REVIEW

**Issue**: All division rounds down (Solidity default). Does this favor certain parties?

**Example**:
```solidity
// Bob stakes 1 wei when pool has 1M shares and 1M tokens staked
sharesToMint = 1 * 1,000,000 / 1,000,000 = 1

// Later, Bob stakes 1 wei when pool has 1M shares and 999,999 tokens staked
sharesToMint = 1 * 1,000,000 / 999,999 = 1.000001 → rounds to 1
```

**Who Benefits**: Slight advantage to existing stakers (rounding down prevents dilution).

**Impact Analysis**:
- Per stake: < 1 wei advantage
- Over 1000 stakes: < 1000 wei = 0.000001 tokens
- **Conclusion**: Negligible

**Alternative**: Round up for new stakers?
```solidity
sharesToMint = (amount * totalShares + currentStaked - 1) / currentStaked;
```
**Risk**: Opens attack vector (stake 1 wei, get 2 shares, repeat).

**Recommendation**: ✅ Keep current rounding (down). Document in code comments.

### 6. First Staker Advantage/Disadvantage

**Status**: 🤔 DESIGN DECISION

**Observation**: First staker gets 1:1 shares, subsequent stakers get proportional shares based on swap-affected pool.

**Scenario**: 
1. Alice creates card → auto-stakes 2M tokens → 2M shares
2. Bob buys 1M tokens from pool (WAVES → CARD)
3. `stakedCards` reduced to ~1.79M
4. Charlie stakes 1M tokens → gets `1M * 2M / 1.79M = 1.117M shares`

**Analysis**:
- Charlie gets MORE shares per token than Alice (1.117 vs 1.0)
- BUT Charlie paid market price for his tokens (expensive)
- Alice got her tokens at creation price (free, just mint fee)

**Is This Fair?**
- **Pro Alice**: Took initial risk, no market yet
- **Pro Charlie**: Paid fair market price for liquidity

**Conclusion**: ✅ Design is fair. Different risk/reward profiles.

**Documentation Needed**: Explain in MECHANICS.md (already done).

### 7. WETH Pool Bootstrap Risk

**Status**: ⚠️ ECONOMIC RISK

**Issue**: First WETH staker initializes pool with 500 WAVES virtual liquidity:

```solidity
if (wavesWethReserve == 0 && wethReserve > 0) {
    wavesWethReserve = 500 ether; // bootstrap
}
```

**Risk**: First WETH staker is vulnerable to immediate arbitrage.

**Example**:
1. Alice stakes 1 WETH
2. Pool: 500 WAVES (virtual), 1 WETH (real)
3. Implied price: 500 WAVES/WETH
4. If real price is 1000 WAVES/WETH:
   - Attacker swaps 500 WAVES → gets ~0.5 WETH
   - Attacker profits ~$1000
   - Alice loses half her WETH

**Mitigation Options**:

1. **Higher bootstrap** (e.g., 5000 WAVES):
   - Reduces arbitrage profit
   - But delays price discovery

2. **Initial WETH seeding** in Router deployment:
   - Protocol seeds 10 WETH + 5000 WAVES at deployment
   - Costs ~$20K upfront

3. **Time-lock** first WETH staker:
   - First WETH stake locked for 24h
   - Prevents immediate exit
   - Allows arbitrageurs to bring to fair price

4. **Accept risk**:
   - First WETH staker is sophisticated (knows risk)
   - Market naturally finds equilibrium
   - Loss limited to first staker only

**Recommendation**: Option 4 (accept risk). Document clearly in UI: "⚠️ First WETH staker: Check market price first!"

### 8. Zero Staked Cards Edge Case

**Status**: ✅ FIXED (low severity bug)

**Scenario**: All stakers unstake → `stakedCards = 0`, but pool still has 7.5M base.

**What Happens**:
```solidity
currentStaked = surfSwap.getStakedCards(0); // returns 0
sharesToMint = amount * totalShares / currentStaked; // 0 / 0 → reverts!
```

**Impact**: Next staker cannot stake → ownership frozen → NFT becomes unclaimed.

**Likelihood**: Low (requires all stakers to exit, unlikely if card has value).

**Fix**:
```solidity
function _stakeInternal(uint256 cardId, address user, uint256 amount) internal {
    // ...
    if (cs.totalShares == 0) {
        sharesToMint = amount; // Bootstrap
    } else {
        uint256 currentStaked = ISurfSwap(surfSwap).getStakedCards(cardId);
        require(currentStaked > 0, "No staked liquidity"); // ← Already here!
        sharesToMint = amount * cs.totalShares / currentStaked;
    }
    // ...
}
```

**Wait, it's already protected!** The `require(currentStaked > 0)` prevents the revert.

**But...** if `currentStaked = 0` and `totalShares > 0`, we can't bootstrap. Need:

```solidity
if (cs.totalShares == 0 || currentStaked == 0) {
    sharesToMint = amount; // Bootstrap (re-bootstrap if drained)
    if (currentStaked == 0) {
        cs.totalShares = 0; // Reset shares when no staked liquidity
    }
}
```

**Recommendation**: ✅ Add re-bootstrap logic before mainnet.

**Fix Applied (2026)**: Re-bootstrap logic added to `_stakeInternal`, `swapStake`, `batchSwapStake`, `unstake`, and `effectiveBalance` in `CardStaking.sol`:
- If `currentStaked == 0` but shares exist, reset `totalShares=0` and bootstrap 1:1.
- Prevents div-by-zero and stuck NFT ownership when staked liquidity fully drains.
- All tests (51) pass post-fix.

## Security Review Needed

- [ ] **External audit** by reputable firm (Trail of Bits, OpenZeppelin, etc.)
- [ ] **Formal verification** of core math (optional, expensive)
- [ ] **Economic simulation** (agent-based modeling of ownership dynamics)
- [ ] **Mainnet rehearsal** on testnet with real users
- [ ] **Bug bounty program** ($50K+ rewards)

## Pre-Mainnet Checklist

- [x] Fix contract size (SurfSwap <24KB) — already resolved post-refactor (~6.7KB runtime)
- [x] Add re-bootstrap logic for zero staked cards (FIXED in CardStaking.sol)
- [x] Fix CRITICAL unbacked WETH bootstrap drain (real WAVES seed via router + no invented reserves)
- [x] Fix HIGH cross-operator reentrancy in GlobalRewards (effects-before-interactions + guard)
- [x] Fix MEDIUM BidNFT.balanceOf (override with guidance)
- [ ] Implement fuzzing tests for proportional tracking
- [ ] Document all rounding behavior in code comments
- [ ] Add WETH bootstrap warning in UI
- [ ] Write migration plan (in case bugs found post-deploy)
- [ ] Set up monitoring (events, TVL, ownership changes)
- [ ] Deploy to multiple testnets (Sepolia, Goerli, Arbitrum Sepolia)
- [ ] Gather community feedback
- [ ] Legal review (is this securities? consult lawyer)

## Issues from External Audit (2026) — Fixed

The following were reported via manual static review and have been patched:

- **CRITICAL**: Unbacked WETH-pool bootstrap drain (SurfSwap.addToWethReserve invented 500 WAVES virtual with no backing transfer; first staker could drain real WAVES belonging to card pools).
  - **Fix**: Removed all automatic invention of `wavesWethReserve`. Added explicit `seedWethLiquidity(uint256)` (router-only, does real WAVES transfer). Router now seeds 500 WAVES on first card creation. WETH pool requires real backing.
  - Updated `initializePool` bootstrap comment. Added seed call + interface. Deployment now safe.

- **HIGH**: Cross-contract reentrancy in GlobalRewards._harvest (debt updated *after* ETH `.call`; multiple operators (CardStaking + WethPool) bypass individual nonReentrant guards).
  - **Fix**: Moved `userGlobalDebt` update before the external call (effects-before-interactions). Added `ReentrancyGuard` inheritance + `nonReentrant` on `harvestGlobal`.

- **MEDIUM**: BidNFT.balanceOf() always returned 0 (never called _mint; virtual ownership via CardStaking).
  - **Fix**: Override `balanceOf()` to revert with clear message directing callers to per-card `ownerOfCard` / CardStaking queries.

- Legacy `WhirlpoolStaking.sol` marked `@deprecated` + note that it contained the same bootstrap bug (not used by current deploys).

See also the detailed audit report provided for full context and exploit paths.

## Known Non-Issues

These were considered and determined to be acceptable:

1. ✅ **NFT Transfers Disabled**: Intentional (ownership via staking)
2. ✅ **No Admin Functions**: Intentional (immutability)
3. ✅ **High Card-to-Card Swap Costs**: Trade-off for multi-route design
4. ✅ **First Staker 1:1 Shares**: Fair compensation for risk
5. ✅ **WETH Stakers Don't Get NFT**: Intentional (different product)
6. ✅ **Mint Fee to All Stakers**: Incentivizes early participation
7. ✅ **Rounding Down**: Standard practice, negligible impact

## Post-Mainnet Monitoring

Watch for:
1. **Unexpected ownership changes** (check OwnerChanged events)
2. **stakedCards drift** (compare to expected values)
3. **Gas spikes** (frontrunning wars?)
4. **Zero staked cards scenario** (monitor totalShares vs stakedCards)
5. **WETH pool arbitrage** (track first WETH staker P&L)

---

**Last Updated**: 2026-07-02 (re-bootstrap patch applied; sizes/docs refreshed)  
**Next Review**: After external audit  
**Status**: ⚠️ NOT PRODUCTION READY (major security patches from external audit applied: WETH bootstrap, GlobalRewards reentrancy, BidNFT; zero-staked also fixed earlier)

**Contact**: [Your contact info here]
