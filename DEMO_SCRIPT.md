# ERC-1142 / Whirlpool AMM — Demo Script

**Duration:** ~10 minutes  
**Audience:** DeFi devs, NFT enthusiasts, investors  
**Setup:** Local Anvil fork + cog-works frontend running

---

## Pre-Demo Setup

```bash
# Terminal 1: Start the full dev suite
cd ~/Projects/erc-1142
bash launch-dev.sh

# Terminal 2: Start cog-works frontend
cd ~/Projects/cog-works
npx vite --host 0.0.0.0
```

Import Anvil test accounts into MetaMask/Rabby:
- **Alice** (deployer): `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`
- **Bob** (challenger): `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d`
- **Charlie** (trader): `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a`

---

## ACT 1 — "The Problem" (1 min)

> **TALKING POINT:** NFT ownership today is binary — you either own it or you don't. There's no economic relationship between holder and asset. You buy a JPEG, it sits in your wallet, and the only thing you can do is hope someone pays more for it later.
>
> What if ownership itself was a competitive, liquid position? What if holding an NFT meant actively participating in a market — and losing your grip meant someone else takes it?

---

## ACT 2 — "Card Creation" (2 min)

**Show:** cog-works → Whirlpool satellite → Mint sub-cog → MintPage

> Every card in Whirlpool is its own micro-economy. Let's create one.

### On-screen (dev frontend):
1. Connect wallet as **Alice**
2. Click **Create Card**
   - Name: `Surfboard of Power`
   - Symbol: `SURFPOW`
   - Cost: 0.05 ETH

> Watch what happens on-chain:

### Narrate the terminal output:
```
✅ Card #3 Created: "Surfboard of Power" (SURFPOW)
   CardToken deployed:   0x... (10,000,000 SURFPOW)
   WAVES minted:         2,000 WAVES
   
   Distribution:
   ├─ AMM Pool:         7,500,000 SURFPOW + 500 WAVES (liquidity)
   ├─ Auto-staked:      2,000,000 SURFPOW (your LP position)
   └─ Protocol:         500,000 SURFPOW (treasury)
   
   You are now the OWNER of Card #3
   Your LP shares: 2,000,000 (100% of staked supply)
```

> **KEY POINT:** Alice didn't just "mint an NFT." She:
> 1. Created a token with real liquidity backing it
> 2. Seeded an AMM pool anyone can trade against
> 3. Staked tokens as single-sided LP — making her the owner
> 4. Her staked tokens ARE the liquidity — they're tradeable by anyone

---

## ACT 3 — "The Ownership Game" (3 min)

> Now let's see what makes this different from every other NFT system.

### Step 1: Bob buys CardTokens

**Switch wallet to Bob.**

1. Go to **Swap Page** (cog-works → Whirlpool → Swap sub-cog)
2. Swap 100 WAVES → SURFPOW tokens
3. Show the swap executing through SurfSwap AMM

> Bob just bought SURFPOW tokens from the AMM pool. Notice something: the tokens he bought **came from Alice's staked position**. Every buy erodes the existing owner's effective balance.

### Step 2: Bob stakes to challenge

1. Bob stakes his SURFPOW tokens via **Staking Dashboard**
2. Show the staking transaction

> Bob now has a staking position. Let's check: who owns the card?

### Step 3: Show ownership state

**Show:** Staking Dashboard → Click the card → Top holders overlay

```
Card #3: "Surfboard of Power"
╔══════════════════════════════════════╗
║  #1  Alice    1,847,322 shares  ★   ║  ← Still owner (eroded from 2M)
║  #2  Bob        145,891 shares      ║  ← Challenger
╚══════════════════════════════════════╝
```

> Alice is still the owner, but her position eroded from 2M to ~1.85M because Bob's buy pulled tokens from the pool (which included her staked liquidity). This is **active defense** — ownership degrades passively as the market trades.

### Step 4: Bob goes all-in

1. Bob buys a massive amount of SURFPOW (swap 500+ WAVES)
2. Bob stakes everything
3. **Ownership changes to Bob**

> 🔥 **OWNERSHIP TRANSFERRED.** Bob didn't "buy the NFT" — he out-staked Alice in the AMM. The BidNFT's `ownerOf()` now returns Bob's address. Alice still has her shares, still earns fees — but she's no longer the owner.

### Step 5: Alice fights back

**Switch wallet back to Alice.**

> Alice sees she lost ownership. She has options:
> 1. Buy more tokens from the pool and re-stake
> 2. Accept her position and keep earning fees as #2 staker
> 3. Unstake and exit entirely

1. Alice swaps WAVES → SURFPOW
2. Alice stakes additional tokens
3. **Ownership flips back to Alice**

> This is the **ownership game**. It's not who clicked "buy" first. It's who maintains the strongest economic position. Every swap, every stake, every unstake changes the balance of power.

---

## ACT 4 — "SwapStake: Atomic Position Swaps" (1.5 min)

> What if Alice doesn't want to fight for this card anymore? She can atomically move her entire position to a different card.

### On-screen:
1. Alice opens Swap Page
2. Source: Card #3 (Surfboard of Power) — toggle to "Staked" source  
3. Target: Card #0 (Fire Dragon)
4. Execute **SwapStake**

```
swapStake(fromCard=3, toCard=0, shares=1847322)

Result:
├─ Unstaked 1,847,322 shares from Card #3
├─ Received ~1,800,000 SURFPOW tokens
├─ Internally swapped: SURFPOW → WAVES → FDRAGON (via SurfSwap)
├─ Staked FDRAGON tokens into Card #0
└─ Alice is now the #1 staker on Card #0!
   Bob inherits ownership of Card #3
```

> **One transaction.** Alice abandoned Card #3 (Bob gets it by default) and took over Card #0. No manual unstake → swap → re-stake. The `swapStake` function handles the entire route atomically.

---

## ACT 5 — "Fee Distribution" (1.5 min)

> Every swap generates 0.3% fees. Every mint generates 0.05 ETH in fees. Where do they go?

### Show: Staking Dashboard → Rewards Breakdown panel

```
Fee Distribution (MasterChef):
╔══════════════════════════════════════╗
║  Card Pool Fees:      70%           ║  → Distributed to card stakers
║  ETH Staking Pool:    20%           ║  → WETH stakers (1.5x boost)  
║  Ownership Bonuses:   10%           ║  → Card owners
╚══════════════════════════════════════╝

Alice's Pending Rewards: 0.0023 ETH
Bob's Pending Rewards:   0.0008 ETH
```

> Notice: **both Alice and Bob earn fees**, even though only one of them owns the card. Every staker earns proportional to their share. Ownership gives a bonus, but even the #5 staker is earning yield. This means there's **economic incentive to stake even if you can't win ownership** — you're still providing liquidity and earning fees.

### Show WETH staking:

> There's also a WETH pool. Stake WETH to provide exit liquidity (WAVES → ETH bridge) and earn 1.5x boosted rewards. This incentivizes the "off-ramp" that makes the whole ecosystem liquid.

---

## ACT 6 — "The Bigger Picture" (1 min)

> Let's zoom out. What we just saw:

**Pull up the Architecture diagram (or Staking Dashboard overview)**

```
What ERC-1142 creates:

1. PERMISSIONLESS CARD CREATION
   Anyone can mint a card. 0.05 ETH. No gatekeepers.
   
2. INSTANT LIQUIDITY
   Every card has a live AMM pool from block 1.
   No need to find a buyer — the pool IS the buyer.

3. COMPETITIVE OWNERSHIP
   Ownership isn't a receipt. It's a position you defend.
   Biggest staker = owner. Period.

4. COMPOSABLE POSITIONS
   Staked tokens are AMM liquidity — not locked away.
   SwapStake lets you move between cards atomically.

5. ALIGNED INCENTIVES
   Stakers earn fees. Owners earn bonuses. Traders pay fees.
   Everyone's economic activity benefits everyone else.
```

> 5,000 card hard cap. 10M tokens per card. Immutable contracts. No admin keys. No proxy. No governance token. Just math.

---

## ACT 7 — "What's Next" (30 sec)

> Three integrations we're building:

1. **Farcaster Mini Apps** — Every ownership change auto-posts a battle frame. One-tap challenge from your feed. Viral loop.

2. **Auto-Defense Keepers** (Gelato/Chainlink) — Set a bot to auto-defend your card when challengers approach. Keeper wars drive TVL.

3. **Leveraged Ownership** (Morpho/Euler) — Borrow against your staked position. 2.5x your ownership through leverage loops. And here's the twist: if you get liquidated, your staking position evaporates and the #2 staker takes your card. Liquidation becomes an ownership attack vector.

> We're deploying to Ethereum mainnet. Immutable. Permissionless. The ownership game starts at mint.

---

## Quick Reference: Key Contract Calls

| Action | Contract | Function | Notes |
|--------|----------|----------|-------|
| Create card | WhirlpoolRouter | `createCard{0.05 ETH}(name, symbol, uri)` | Deploys token, seeds pool, auto-stakes |
| Buy tokens | SurfSwap | `swapExact(tokenIn, tokenOut, amount, minOut)` | Routes through WAVES hub |
| Stake | WhirlpoolStaking | `stake(cardId, amount)` | Must approve CardToken first |
| Unstake | WhirlpoolStaking | `unstake(cardId, shares)` | Returns CardTokens |
| Swap position | WhirlpoolStaking | `swapStake(fromCard, toCard, shares)` | Atomic unstake+swap+restake |
| Check owner | WhirlpoolStaking | `ownerOfCard(cardId)` | Also via BidNFT.ownerOf() |
| Check rewards | WhirlpoolStaking | `pendingRewards(cardId, user)` | Per-card rewards |
| Claim rewards | WhirlpoolStaking | `claimRewards(cardId)` | Sends ETH |
| Stake WETH | WhirlpoolStaking | `stakeWETH(amount)` | 1.5x reward boost |
| Pool reserves | SurfSwap | `getReserves(cardId)` | Returns (wavesR, cardsR) |
| Card price | SurfSwap | `getPrice(cardId)` | WAVES per CardToken |

## Cast Commands for Live Demo

```bash
# Check card owner
cast call $WHIRLPOOL "ownerOfCard(uint256)" 0 --rpc-url http://127.0.0.1:8545

# Check Alice's stake  
cast call $WHIRLPOOL "stakeOf(uint256,address)" 0 $ALICE --rpc-url http://127.0.0.1:8545

# Check pool reserves
cast call $SURFSWAP "getReserves(uint256)" 0 --rpc-url http://127.0.0.1:8545

# Bob buys tokens: approve WAVES → SurfSwap, then swap
cast send $WAVES "approve(address,uint256)" $SURFSWAP 100000000000000000000 --private-key $BOB_PK --rpc-url http://127.0.0.1:8545
cast send $SURFSWAP "swapExact(address,address,uint256,uint256)" $WAVES $CARD_TOKEN 100000000000000000000 0 --private-key $BOB_PK --rpc-url http://127.0.0.1:8545

# Bob stakes
cast send $CARD_TOKEN "approve(address,uint256)" $WHIRLPOOL 999999999999999999999999 --private-key $BOB_PK --rpc-url http://127.0.0.1:8545
cast send $WHIRLPOOL "stake(uint256,uint256)" 0 <AMOUNT> --private-key $BOB_PK --rpc-url http://127.0.0.1:8545

# Check if ownership changed
cast call $WHIRLPOOL "ownerOfCard(uint256)" 0 --rpc-url http://127.0.0.1:8545
```

---

## Environment Variables (for cast commands)

```bash
export ALICE=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export ALICE_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export BOB=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
export BOB_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
export CHARLIE=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
export CHARLIE_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a

# Set these after deployment (launch-dev.sh prints them)
export WHIRLPOOL=<address>
export SURFSWAP=<address>
export ROUTER=<address>
export WAVES=<address>
export WETH=<address>
export BIDNFT=<address>

# Get card token address
export CARD_TOKEN=$(cast call $ROUTER "cardToken(uint256)" 0 --rpc-url http://127.0.0.1:8545)
```
