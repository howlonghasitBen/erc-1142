# OpenSea vs Whirlpool Marketplace — Feature Comparison

> Last updated: 2026-02-07

## Feature Comparison

### Listing & Discovery

| Feature | OpenSea | Whirlpool | Status |
|---------|---------|-----------|--------|
| Browse all NFTs | Grid view with infinite scroll | Grid view with auto-fill responsive layout | ✅ Done |
| Search by name | Full-text search across all collections | Header search bar (UI only, not wired) | 🔧 Partial |
| Filter by traits | Sidebar trait filters per collection | Filter by staked / owned status | 🔧 Partial |
| Sort (price, recent, etc.) | Price, recently listed, most viewed, etc. | Sort by ID, price asc/desc, name A-Z | ✅ Done |
| Collection pages | Dedicated page per collection with stats | N/A — all cards are one collection (Whirlpool) | N/A |
| Categories | Art, Music, Gaming, PFPs, etc. | N/A — single card type system | N/A |
| Trending / Hot | Trending collections, top traders | No trending/hot algorithm yet | ❌ Missing |
| Infinite scroll / pagination | Infinite scroll with lazy loading | All cards loaded at once (max 100) | 🔧 Partial |

### Trading

| Feature | OpenSea | Whirlpool | Status |
|---------|---------|-----------|--------|
| Buy NFT | Fixed price or auction | N/A — ownership via staking, not purchase | N/A |
| Sell / List NFT | Set price, duration, fees | N/A — ownership is dynamic, not transferable | N/A |
| Make offer / Bid | Offer on any NFT | N/A — stake more to "bid" for ownership | N/A |
| Auction | English & Dutch auctions | N/A — continuous staking auction (always live) | N/A |
| **Swap Stake** | ❌ Not applicable | Atomic position swap between cards (CARD_A → WAVES → CARD_B) | ✅ Done |
| **Stake to Own** | ❌ Not applicable | LP staking determines NFT ownership | ✅ Done |
| **Claim Rewards** | ❌ Not applicable | Claim accumulated swap fee rewards per card | ✅ Done |
| Cart / Bulk buy | Add to cart, checkout multiple | No bulk operations yet | ❌ Missing |
| Direct swap (NFT↔NFT) | Via Seaport protocol | SwapStake is the equivalent (stake-level swap) | ✅ Done |

### NFT Details

| Feature | OpenSea | Whirlpool | Status |
|---------|---------|-----------|--------|
| Metadata display | Image, name, description, traits | Name, symbol, card ID, gradient placeholder | 🔧 Partial |
| Trait rarity | Rarity scores per trait | N/A — no trait system yet | ❌ Missing |
| Price history chart | Per-NFT price chart over time | No historical data tracking | ❌ Missing |
| Activity / tx history | Full transfer/sale history | No activity log in UI | ❌ Missing |
| Provenance | Chain of ownership | Owner shown, but no history | 🔧 Partial |
| Token standard info | ERC-721/1155 details | Shows token address, reserves, stake amounts | ✅ Done |
| Collapsible stats panel | Properties, levels, stats sections | Expandable "NFT Stats" with reserves/stake/owner | ✅ Done |

### User Profiles

| Feature | OpenSea | Whirlpool | Status |
|---------|---------|-----------|--------|
| Portfolio page | Collected, created, favorited tabs | Portfolio with staked + owned cards | ✅ Done |
| Portfolio stats | Total value, items count | Staked count, owned count, pending rewards | ✅ Done |
| Activity feed | All user transactions | No activity feed yet | ❌ Missing |
| Favorites / Watchlist | Heart NFTs to save | No favorites system | ❌ Missing |
| Offers made/received | Track open offers | N/A — no offer system (stake-based) | N/A |
| Profile customization | Banner, bio, social links | No user profiles | ❌ Missing |

### Social

| Feature | OpenSea | Whirlpool | Status |
|---------|---------|-----------|--------|
| Comments | ❌ No native comments | No comments | ❌ Missing |
| Likes / Hearts | Favorite count on NFTs | No social signals | ❌ Missing |
| Follow creators | Follow accounts | No follow system | ❌ Missing |
| Share links | Share to Twitter, copy link | No share functionality | ❌ Missing |
| User collections | Create themed collections | N/A — single collection | N/A |

### Analytics

| Feature | OpenSea | Whirlpool | Status |
|---------|---------|-----------|--------|
| Floor price | Per-collection floor | No floor price metric (AMM-priced) | N/A |
| Volume tracking | 24h, 7d, 30d, all-time | No volume tracking | ❌ Missing |
| Price charts | Collection + per-NFT charts | No charts | ❌ Missing |
| Top traders | Leaderboards | No leaderboard | ❌ Missing |
| Reserve/liquidity depth | N/A | Shows WAVES + card reserves per pool | ✅ Done |
| Staking leaderboard | N/A | No leaderboard for biggest stakers | ❌ Missing |

### Wallet

| Feature | OpenSea | Whirlpool | Status |
|---------|---------|-----------|--------|
| Wallet connect | MetaMask, WalletConnect, Coinbase, etc. | Injected wallet (MetaMask) via wagmi | ✅ Done |
| Multi-chain | Ethereum, Polygon, Arbitrum, etc. | Anvil localhost only (single chain) | 🔧 Partial |
| Portfolio value | Total ETH value of holdings | No portfolio valuation | ❌ Missing |
| ENS resolution | Shows ENS names | No ENS support | ❌ Missing |
| ETH + token balances | Shows ETH balance | Shows ETH + WAVES balance in header | ✅ Done |

### Admin / Creator Tools

| Feature | OpenSea | Whirlpool | Status |
|---------|---------|-----------|--------|
| Create NFT | Upload media, set properties | Create card form (name, symbol, URI) + 0.05 ETH | ✅ Done |
| Collection management | Edit collection details, banner | N/A — single system collection | N/A |
| Royalty settings | Set creator royalties | N/A — fees go to stakers, not creators | N/A |
| Verified badges | Blue checkmarks | No verification system | ❌ Missing |

---

## Implementation Priorities

### P0 — MVP (Must Have Before Public Launch)

- **Working search** — Wire header search to filter cards by name/symbol/ID in real-time
- **Transaction confirmations** — Show pending tx state, block confirmations, and explorer links
- **Error handling** — Graceful handling of RPC errors, rejected txs, and disconnected wallet
- **Multi-chain config** — Support Base mainnet (or target chain) instead of just Anvil localhost
- **Card images** — Render actual NFT artwork from tokenURI instead of gradient placeholders
- **Loading states per card** — Individual card loading skeletons during swapStake/claim transactions
- **Mobile responsive polish** — Test and fix layout on small screens (currently basic responsive)

### P1 — Important (Soon After Launch)

- **Activity feed** — Show recent swapStake/claim/mint events per card and per user
- **Price history** — Store and chart WAVES price over time for each card (needs indexer)
- **Staking leaderboard** — Show top stakers per card with ownership percentage bars
- **WETH staking UI** — Add interface for staking WETH (1.5x boosted rewards, exit liquidity)
- **Direct stake/unstake** — Allow staking raw CardTokens (not just swapStake between cards)
- **Pagination / virtual scroll** — Handle 5000 cards without loading all at once
- **WalletConnect support** — Add WalletConnect connector for mobile wallets
- **Share card links** — Deep links to individual cards (URL routing)

### P2 — Nice to Have (Future Features)

- **Notifications** — Toast on ownership change, reward accrual, large swaps against your position
- **Portfolio valuation** — Calculate total WAVES value of all staked positions
- **Card comparison** — Side-by-side view of two cards' reserves, stakers, and price
- **Ownership history** — Timeline showing who owned each card and when
- **Advanced filters** — Filter by price range, reserve depth, reward APY
- **Keyboard shortcuts** — Quick navigation (J/K to browse cards, Enter to expand)
- **Dark/light theme** — Currently dark-only; add light mode toggle
- **ENS + avatar support** — Show ENS names and avatars instead of 0x addresses

### P3 — Stretch (Dream Features)

- **Real-time updates** — WebSocket subscription to contract events for live price/ownership updates
- **Governance dashboard** — If governance is added, show proposals and voting UI
- **Multi-card swapStake** — Batch swapStake across multiple source → destination pairs
- **Card creator profiles** — Show all cards created by an address, their total volume
- **AI card art generator** — Generate card artwork from name/symbol using AI
- **Mobile app** — React Native or PWA with push notifications for ownership changes
- **Subgraph indexer** — The Graph subgraph for historical data, analytics, and fast queries
- **Social proof** — Integration with Farcaster/Lens for on-chain social identity
