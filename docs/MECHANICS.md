# Mechanics Deep Dive

## Constant Product AMM Math

Whirlpool uses the standard constant product formula: **x × y = k**

### Basic Swap Calculation

Given reserves `R_in` and `R_out`:

```
k = R_in × R_out

After adding Δ_in:
k = (R_in + Δ_in) × (R_out - Δ_out)

Solving for Δ_out:
Δ_out = R_out - (R_in × R_out) / (R_in + Δ_in)
```

### With Fees (0.3%)

Whirlpool applies a **0.3% fee** (30 basis points):

```
fee = Δ_in × 0.003
Δ_in_after_fee = Δ_in - fee

Δ_out_gross = R_out - (R_in × R_out) / (R_in + Δ_in_after_fee)
Δ_out_net = Δ_out_gross - (Δ_out_gross × 0.003)

Fee is distributed to stakers.
```

**Example**: Swap 100 WAVES for CARD

```
Initial pool: 500 WAVES, 7.5M CARD
fee = 100 × 0.003 = 0.3 WAVES
Δ_in_after_fee = 99.7 WAVES

New WAVES reserve = 500 + 99.7 = 599.7
Δ_out_gross = 7.5M - (500 × 7.5M) / 599.7
            = 7.5M - 6,252,085
            = 1,247,915 CARD

fee = 1,247,915 × 0.003 = 3,744 CARD (in WAVES equivalent)
Δ_out_net ≈ 1,244,171 CARD

User receives: 1,244,171 CARD
Fee distributed: 3,744 CARD worth of WAVES to stakers
```

### Multi-hop Swaps

For CARD → CARD swaps, the route is **CARD_A → WAVES → CARD_B**, applying fees twice:

```
Swap 1: CARD_A → WAVES (0.3% fee)
Swap 2: WAVES → CARD_B (0.3% fee)

Total fee ≈ 0.6% (not exactly due to compounding)
```

**Example**: Swap 1M CARD_A for CARD_B

```
Pool A: 500 WAVES, 7.5M CARD_A
Pool B: 500 WAVES, 7.5M CARD_B

Step 1: 1M CARD_A → WAVES
  fee = 3,000 CARD_A
  amountIn_after_fee = 997,000 CARD_A
  WAVES_out = 500 - (500 × 7.5M) / (7.5M + 997k)
            ≈ 58.77 WAVES (before fee)
  fee = 0.176 WAVES
  Net WAVES = 58.59 WAVES

Step 2: 58.59 WAVES → CARD_B
  fee = 0.176 WAVES
  amountIn_after_fee = 58.42 WAVES
  CARD_B_out = 7.5M - (500 × 7.5M) / (500 + 58.42)
             ≈ 785,000 CARD_B (before fee)
  fee = 2,355 CARD_B (in WAVES)
  Net CARD_B ≈ 782,645 CARD_B

Round-trip loss: ~21.7% (1M → 782k)
```

This harsh penalty creates **strong liquidity barriers** between cards.

## LP Share Calculation

### First Staker (Bootstrap)

The first staker gets **1:1 shares**:

```solidity
if (totalShares == 0) {
    sharesToMint = amount;  // 1:1
}
```

**Example**: Card creation auto-stakes 2M tokens for minter.

```
totalShares = 0
amount = 2,000,000 ether
sharesToMint = 2,000,000 ether

Result: User gets 2M shares representing 2M tokens.
```

### Subsequent Stakers

Subsequent stakers get **proportional shares** based on current staked liquidity:

```solidity
currentStaked = SurfSwap.getStakedCards(cardId);
sharesToMint = amount * totalShares / currentStaked;
```

**Example**: Alice has 2M shares, pool has 2M staked tokens. Bob stakes 1M.

```
totalShares = 2,000,000 ether
currentStaked = 2,000,000 ether (Alice's tokens)
amount = 1,000,000 ether (Bob's stake)

sharesToMint = 1M × 2M / 2M = 1,000,000 ether

Bob gets 1M shares.
Total shares now = 3M
Alice: 2M shares (66.67%)
Bob:   1M shares (33.33%)
```

### After Swaps (Effective Balance Changes)

When swaps occur, `stakedCards` changes but **shares do not**:

```
Before swap:
  stakedCards = 2M
  Alice shares = 2M (100%)
  Alice effective = 2M × 2M / 2M = 2M tokens

Charlie buys 500K tokens from pool (WAVES → CARD):
  stakedCards reduces proportionally
  Reduction = 500k × 2M / 9.5M ≈ 105,263 tokens
  stakedCards = 2M - 105,263 = 1,894,737 tokens

After swap:
  stakedCards = 1,894,737
  Alice shares = 2M (still 100%)
  Alice effective = 2M × 1.895M / 2M = 1,894,737 tokens
  
Alice lost ~105K tokens (5.26%) without doing anything!
```

This is the **active defense** mechanic in action.

### Share Value Accrual

Unlike traditional LP, shares do **not** directly accrue value from fees. Instead:

1. Swap fees go to MasterChef accumulator
2. Users harvest fees separately
3. Share value only changes via swaps affecting `stakedCards`

**Why?** This creates volatility in effective balance, forcing active participation.

## Effective Balance Formula

```solidity
effectiveBalance = (userShares × stakedCards) / totalShares
```

**Key insight**: Your token count varies with `stakedCards`, which is affected by:

1. **Staking**: Increases `stakedCards` 1:1
2. **Unstaking**: Decreases `stakedCards` 1:1
3. **Swaps (WAVES → CARD)**: Decreases `stakedCards` proportionally
4. **Swaps (CARD → WAVES)**: Increases `stakedCards` proportionally (rare)

### Proportional Reduction Math

When CARD is bought from the pool:

```solidity
stakedReduction = amountOut × stakedCards / cardReserve
stakedCards -= stakedReduction
```

**Example**: Pool has 9.5M total (7.5M base + 2M staked)

```
Before:
  cardReserve = 9,500,000
  stakedCards = 2,000,000

User buys 500,000 tokens:
  stakedReduction = 500k × 2M / 9.5M
                  = 105,263 tokens
  
  stakedCards = 2M - 105,263 = 1,894,737
  cardReserve = 9.5M - 500k = 9M

Staked portion: 1.895M / 9M = 21.05% (was 21.05% before)
```

The **percentage** stays constant, but **absolute amount** decreases.

### Proportional Increase Math

When CARD is sold to the pool (rare for stakers, but possible):

```solidity
stakedIncrease = addedCards × stakedCards / cardReserve
stakedCards += stakedIncrease
```

**Example**: User sells 1M tokens back

```
Before:
  cardReserve = 9,000,000
  stakedCards = 1,894,737

User sells 1,000,000 tokens:
  stakedIncrease = 1M × 1.895M / 9M
                 = 210,526 tokens
  
  stakedCards = 1.895M + 210,526 = 2,105,263
  cardReserve = 9M + 1M = 10M

Staked portion: 2.105M / 10M = 21.05% (still constant!)
```

Again, percentage stays constant. This maintains fairness.

## Active Defense Dynamics

### Scenario: Bob Takes Over Alice's Card

**Initial State**:
- Alice owns Card #1 (2M shares, 2M tokens staked)
- Pool: 500 WAVES, 9.5M CARD (7.5M base + 2M staked)

**Bob's Attack**:

1. Bob buys 1M CARD tokens:
   ```
   Cost: ~58 WAVES
   Alice effective: 2M → 1.79M (10.5% loss)
   ```

2. Bob stakes 1M CARD tokens:
   ```
   Bob shares = 1M × 2M / 1.79M = 1,117,318 shares
   Total shares = 3,117,318
   
   Alice: 2M shares (64.16%)
   Bob:   1.12M shares (35.84%)
   
   Alice still owns NFT.
   ```

3. Bob buys another 1M CARD tokens:
   ```
   Cost: ~68 WAVES (price went up)
   stakedCards = 2.79M → 2.49M (10.75% loss)
   
   Alice effective: 1.79M → 1.60M
   Bob effective: 1M → 893k
   ```

4. Bob stakes another 1M CARD:
   ```
   Bob new shares = 1M × 3.12M / 2.49M = 1,252,008 shares
   Bob total shares = 2,369,326
   Total shares = 5,486,644
   
   Alice: 2M shares (36.45%)
   Bob:   2.37M shares (43.19%)
   
   Bob now has more shares → Bob owns NFT!
   ```

**Bob's cost**: ~126 WAVES (~$315 at $2.50/WAVES)  
**Alice's defense cost**: Must buy + stake >370K tokens to reclaim

### Mathematical Threshold

To overtake an owner with `O` shares and total `T` shares:

```
Attacker needs: A > O shares

Given currentStaked = S, to get A shares requires staking:
  amount = A × S / T

If A = O (break even):
  amount = O × S / T
```

But swaps occur first, reducing S, so actual amount needed is higher.

### Defense Strategies

**Alice's Options**:

1. **Pre-emptive staking**: Increase her shares before attack
2. **Immediate response**: Frontrun Bob's second stake
3. **Counter-attack**: After ownership lost, buy cheap and restake
4. **Fee harvesting**: Let Bob take ownership, harvest fees, buy back later

## Fee Distribution (MasterChef Pattern)

### Accumulator Math

Standard MasterChef pattern for O(1) gas:

```solidity
accRewardPerShare += newRewards × ACC_PRECISION / totalShares
```

Where `ACC_PRECISION = 1e18` for precision.

### User Pending Rewards

```solidity
pending = userShares × accRewardPerShare / ACC_PRECISION - userDebt
```

### Debt Tracking

After harvest or stake/unstake:

```solidity
userDebt = userShares × accRewardPerShare / ACC_PRECISION
```

This "resets" pending to 0 without changing accumulator.

### Example: Fee Distribution

**Initial State**:
- Alice: 2M shares
- Bob: 1M shares
- Total: 3M shares
- accRewardPerShare = 0

**Swap occurs, 10 WAVES fee collected**:

```
accRewardPerShare += 10 × 1e18 / 3M
                   = 10 × 1e18 / 3,000,000
                   = 3,333,333,333,333,333

Alice pending = 2M × 3.33e15 / 1e18 - 0
              = 6.67 WAVES
              
Bob pending = 1M × 3.33e15 / 1e18 - 0
            = 3.33 WAVES

Total = 10 WAVES ✓
```

**Alice harvests**:

```
Transfer 6.67 WAVES to Alice
aliceDebt = 2M × 3.33e15 / 1e18 = 6.67e18

Alice pending = 2M × 3.33e15 / 1e18 - 6.67e18 = 0
```

**Another swap, 15 WAVES fee**:

```
accRewardPerShare += 15 × 1e18 / 3M
                   = 5e15
                   
Total accumulator = 3.33e15 + 5e15 = 8.33e15

Alice pending = 2M × 8.33e15 / 1e18 - 6.67e18
              = 16.67 - 6.67 = 10 WAVES
              
Bob pending = 1M × 8.33e15 / 1e18 - 0
            = 8.33 WAVES
            
(Bob never harvested, so his debt is still 0)
```

### WETH Boost Math

WETH stakers get **1.5x weight** in global mint fee distribution:

```solidity
weightAdded = wethAmount × WETH_BOOST / 10
            = wethAmount × 15 / 10
            = wethAmount × 1.5
```

**Example**: Alice stakes 10 WETH

```
Alice cardShares (weight) = 2M
Alice WETH stake (weight) = 10 × 1.5 = 15
Alice total weight = 2,000,015

If totalGlobalWeight = 5M:
  Alice's share of mint fees = 2,000,015 / 5M = 0.04%
```

WETH stakers also earn from WAVES ↔ WETH swap fees (unboosted).

## Gas Costs

Estimated gas costs (based on tests):

| Operation | Gas | Notes |
|-----------|-----|-------|
| Create card | ~1.5M | Includes deploy + init + stake |
| Swap (single route) | ~150K | CARD ↔ WAVES |
| Swap (multi-route) | ~280K | CARD ↔ CARD |
| Stake | ~180K | Includes harvest |
| Unstake | ~200K | Includes harvest + transfer |
| Harvest rewards | ~80K | Claim only |
| WETH stake/unstake | ~150K | Lower than card staking |

**Gas optimization opportunities**:
- Batch harvesting across multiple cards
- Combine stake + harvest into atomic operation (already done)
- Reduce storage reads in swap functions

## Edge Cases

### 1. First Staker Advantage

First staker gets 1:1 shares, subsequent stakers get proportional. Is this unfair?

**Analysis**:
- First staker takes **price risk** (no market yet)
- First staker's tokens are immediately tradeable
- Subsequent stakers get **fair market price** via shares

**Conclusion**: Not an advantage, just different risk profiles.

### 2. Dust Shares

Can an attacker create many tiny stakes to inflate `totalShares` and dilute others?

**No**:
- Shares calculated as: `amount × totalShares / currentStaked`
- If attacker adds 1 wei, they get `1 × T / S` shares
- Their ownership % = `(1 × T / S) / (T + 1 × T / S)` = `1 / (S + 1)` → negligible

**Mitigation**: `MIN_STAKE = 1` (placeholder, could be higher).

### 3. Zero Staked Cards

What if all stakers unstake? `stakedCards = 0`, but pool still has base 7.5M?

**Current behavior**:
- `getStakedCards()` returns 0
- Next staker calculates: `shares = amount × 0 / 0` → reverts!

**Fix needed**: Bootstrap back to 1:1 if `stakedCards == 0`.

### 4. Rounding Errors

All divisions round down (Solidity default). Over many swaps, does this hurt stakers?

**Analysis**:
- Rounding < 1 wei per operation
- Favors existing stakers (slightly)
- Self-corrects when staking/unstaking

**Impact**: Negligible (< $0.0001 over 10,000 swaps).

### 5. Ownership Race Conditions

Two users stake simultaneously, who owns the NFT?

**Resolution**: Transaction ordering (higher gas = first). Standard MEV situation.

**Mitigation**: Users can frontrun each other indefinitely (intended behavior).

## Summary

Whirlpool's mechanics create a **competitive ownership game** where:

1. **Staking is depositing LP** (single-sided)
2. **Swaps erode your position** (proportional to trade volume)
3. **You must actively defend** (re-buy and restake)
4. **Fees reward participation** (MasterChef O(1) gas)
5. **WETH provides exit liquidity** (1.5x boosted rewards)

The math is intentionally simple (constant product AMM) but the **dynamics are complex** due to the coupling of ownership and liquidity.
