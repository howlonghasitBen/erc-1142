# Whirlpool AMM — ERC-1142 Bid-to-Own NFT System

⚠️ **UNDER REVIEW** — This project is currently under review. See [REVIEW.md](docs/REVIEW.md) for items requiring attention.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Forge Tests](https://img.shields.io/badge/tests-45%2F45%20passing-brightgreen)]()
[![Solidity](https://img.shields.io/badge/solidity-0.8.20-blue)]()

## Overview

Whirlpool is a custom AMM where **NFT ownership = biggest LP staker**. Staked tokens are tradeable (deposited as single-sided LP into the AMM), creating active defense dynamics where swaps erode your ownership position, forcing you to re-buy to maintain control.

### Key Innovation

Unlike traditional NFT ownership systems, Whirlpool makes ownership **liquid and dynamic**:

- **Stake to Own**: The address with the most LP shares owns the NFT
- **Active Defense**: Swaps reduce your effective token count, eroding your ownership position
- **Tradeable Staked Tokens**: Your staked tokens remain in the AMM pool and are traded against
- **Economic Warfare**: Maintaining ownership requires continuous market participation

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    WhirlpoolRouter.sol                      │
│              (Card Creation Orchestrator)                   │
│                                                             │
│  • Deploys CardToken (10M supply)                          │
│  • Mints 2000 WAVES (500→AMM, 1500→minter)                │
│  • Distributes: 75% AMM, 20% auto-staked, 5% protocol     │
│  • Mints BidNFT                                             │
└─────────────────────────────────────────────────────────────┘
                    ↓                      ↓
         ┌──────────────────┐    ┌──────────────────┐
         │  SurfSwap.sol    │    │ WhirlpoolStaking │
         │  (AMM Engine)    │←───│  .sol (LP + Fees)│
         └──────────────────┘    └──────────────────┘
         │                        │
         │  Constant product      │  LP share-based
         │  x * y = k             │  staking
         │  Multi-route swaps     │  Ownership tracking
         │  0.3% fees             │  MasterChef rewards
         │  stakedCards tracking  │  WETH 1.5x boost
         │                        │
         └────────────────────────┘
                    ↓
         ┌──────────────────────┐
         │     BidNFT.sol       │
         │ (Dynamic Ownership)  │
         │                      │
         │  ownerOf() → Whirl   │
         │  pool.ownerOfCard()  │
         └──────────────────────┘

Supporting Tokens:
├─ WAVES.sol      — Hub token (10M max supply)
├─ CardToken.sol  — Per-card ERC-20 (10M each)
└─ WETH           — External (for exit liquidity)
```

## Key Mechanics

### Card Creation

When you create a card (cost: **0.05 ETH**):

1. **CardToken deployed**: 10,000,000 tokens minted
2. **WAVES minted**: 2,000 WAVES created
   - 500 WAVES (25%) → AMM pool
   - 1,500 WAVES (75%) → You (the minter)
3. **Token distribution**:
   - 7,500,000 (75%) → AMM pool
   - 2,000,000 (20%) → Auto-staked for you
   - 500,000 (5%) → Protocol treasury
4. **You become owner**: Auto-staked tokens give you majority LP shares
5. **NFT minted**: BidNFT dynamic ownership linked to your stake

### Trading

All swaps route through **WAVES** as the hub token:

| Route | Path | Fee |
|-------|------|-----|
| CARD ↔ CARD | CARD → WAVES → CARD | 0.3% × 2 |
| CARD ↔ WAVES | Direct | 0.3% |
| CARD ↔ WETH | CARD → WAVES → WETH | 0.3% × 2 |
| WAVES ↔ WETH | Direct | 0.3% |

### LP Staking (Ownership System)

**Staking = Single-sided liquidity provision**

When you stake card tokens:

1. Tokens deposited into AMM pool as single-sided LP
2. You receive **LP shares** (first staker: 1:1, subsequent: proportional)
3. Your tokens remain in the pool and are **tradeable by everyone**
4. Swaps reduce the `stakedCards` portion, eroding your effective balance
5. **Biggest shareholder** = NFT owner

**Effective Balance Formula**:
```solidity
effectiveBalance = (userShares * stakedCards) / totalShares
```

Where `stakedCards` decreases when people buy from the pool.

### Active Defense

You must **actively defend** your ownership:

1. Bob buys 1M card tokens → Pool's staked reserve shrinks
2. Your shares stay the same, but effective balance drops
3. Your ownership percentage decreases
4. If another staker surpasses you → **NFT ownership transfers**

### SwapStake (Atomic Position Swap)

Move your staked position from one card to another in a single transaction:

- **No unstake/re-stake needed** — atomic CARD_A → WAVES → CARD_B via reserve math
- **No token transfers** — pure accounting changes in SurfSwap reserves
- **Lower gas** — ~280K gas vs ~580K for separate unstake + swap + stake
- **0.6% fee** — double hop through WAVES (0.3% × 2)
- **Ownership updates** — both source and destination cards checked for ownership change

```solidity
whirlpool.swapStake(fromCardId, toCardId, sharesToSwap);
```

### WETH Staking

Stake WETH to earn **1.5x boosted rewards**:

- Provides exit liquidity (WAVES ↔ WETH pool)
- Earns swap fees from WETH routes
- Gets 1.5x weight in global mint fee distribution
- Doesn't grant NFT ownership

### Fee Distribution

| Fee Type | Source | Recipients |
|----------|--------|------------|
| Swap fees (CARD) | 0.3% of swaps | Card-specific stakers (MasterChef) |
| Swap fees (WETH) | 0.3% of WETH swaps | WETH stakers (MasterChef) |
| Mint fees | 0.05 ETH per card | All stakers (weighted by LP shares + WETH) |

**MasterChef Pattern**: O(1) gas via accumulator:
```solidity
accRewardPerShare += newRewards / totalShares
pendingReward = userShares * accRewardPerShare - userDebt
```

## Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `MAX_CARDS` | 5,000 | Maximum cards in system |
| `MINT_FEE` | 0.05 ETH | Cost to create a card |
| `CARD_SUPPLY` | 10,000,000 | Tokens per card |
| `WAVES_PER_CARD` | 2,000 | WAVES minted per card |
| `SWAP_FEE` | 0.3% | Swap fee (30 bps) |
| `WETH_BOOST` | 1.5x | WETH staker reward multiplier |

### Distribution Breakdown

**WAVES** (2,000 per card):
- 25% (500) → AMM pool
- 75% (1,500) → Minter

**CARD** (10M per card):
- 75% (7.5M) → AMM pool
- 20% (2M) → Minter (auto-staked)
- 5% (500K) → Protocol

## Immutability

⚠️ **No admin. No proxy. No upgrades.**

- All contracts immutable once deployed
- Parameters hardcoded
- No pause function
- No emergency withdrawal
- What you deploy is what you get forever

## Quick Start

### Local Development

```bash
# Launch Anvil + deploy contracts
bash launch-dev.sh
```

This script:
1. Starts Anvil (local EVM)
2. Deploys all contracts
3. Creates 2 example cards
4. Prints contract addresses
5. Opens demo frontend (optional)

### Testing

```bash
forge test -vv
```

**Expected output**: `45/45 tests passing`

### Build

```bash
forge build
```

## Contract Sizes

All contracts fit within the EIP-170 limit (24,576 bytes):

| Contract | Size | Status |
|----------|------|--------|
| WhirlpoolRouter | ~19 KB | ✅ |
| WhirlpoolStaking | ~23 KB | ⚠️ Near limit |
| SurfSwap | ~22 KB | ⚠️ Uses --code-size-limit locally |
| BidNFT | ~8 KB | ✅ |
| WAVES | ~4 KB | ✅ |
| CardToken | ~3 KB | ✅ |

⚠️ SurfSwap currently requires `--code-size-limit` flag in foundry.toml for local compilation. See [REVIEW.md](docs/REVIEW.md).

## Marketplace Frontend

An OpenSea-style web UI for browsing, creating, and managing Whirlpool cards.

<!-- TODO: Add screenshot -->
![Marketplace Screenshot](docs/marketplace-screenshot.png)

### Features
- Browse all cards in a responsive grid with sort/filter
- **SwapStake UI** — atomic position swaps between cards with percentage controls
- **Portfolio** — view your staked/owned cards and pending rewards
- **Create** — mint new cards with name, symbol, and IPFS metadata

### Tech Stack
- React 18 + TypeScript + Vite
- wagmi v2 + viem (wallet + contract interactions)
- Framer Motion (animations)
- Tailwind CSS + CSS custom properties (sunset/ocean theme)
- Space Grotesk + JetBrains Mono fonts

### Quick Start

```bash
cd marketplace
npm install
npm run dev
```

Requires a running Anvil instance with deployed contracts (see `launch-dev.sh`).

See [marketplace/OPENSEA-COMPARISON.md](marketplace/OPENSEA-COMPARISON.md) for feature parity analysis vs OpenSea.

## Documentation

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — Detailed system architecture
- [MECHANICS.md](docs/MECHANICS.md) — Deep dive into AMM math and LP mechanics
- [DEPLOYMENT.md](docs/DEPLOYMENT.md) — Deployment guide
- [REVIEW.md](docs/REVIEW.md) — Items under review

## Security Considerations

⚠️ This is experimental software. Use at your own risk.

Recent iterative hardening (see `SECURITY.md` for full details):

- **Fixed CRITICAL unbacked WETH bootstrap drain** — protocol now seeds real WAVES on first card creation. No more invented reserves.
- **Fixed HIGH cross-operator reentrancy** in GlobalRewards.
- **Fixed MEDIUM** broken `balanceOf()` on BidNFT.
- Previous zero-staked re-bootstrap edge case also resolved.
- Modern custom errors + locked min liquidity.

- **No professional audit** yet — this is research-grade hardening.
- **Complexity** — Novel ownership mechanics (active defense via staked LP) may have subtle economic edge cases.
- **Immutability** — No admin, no upgrades, no emergency functions by design.

See:
- [SECURITY.md](SECURITY.md)
- [docs/REVIEW.md](docs/REVIEW.md) (includes older items + status of fixes)

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

This project is currently **under review**. Contributions welcome after initial audit.

## Credits

- Built on [Foundry](https://getfoundry.sh/)
- Uses [OpenZeppelin](https://openzeppelin.com/contracts/) contracts

---

**Remember**: With great power comes great gas costs. Defend your NFTs wisely. 🌊
