# Architecture Documentation

## System Overview

Whirlpool is a three-contract AMM system where NFT ownership is determined by staking position. The architecture separates concerns into:

1. **WhirlpoolRouter** — Entry point, orchestrates card creation
2. **SurfSwap** — AMM engine, handles all swaps and liquidity
3. **WhirlpoolStaking** — Staking, ownership tracking, fee distribution

Supporting contracts:
- **WAVES** — Hub token (ERC-20, 10M max supply)
- **CardToken** — Per-card ERC-20 (10M fixed supply each)
- **BidNFT** — Dynamic ownership NFT (non-transferable)

## Contract Interaction Diagram

```
                    User/Frontend
                          │
                          ↓
              ┌───────────────────────┐
              │  WhirlpoolRouter.sol  │
              │  ────────────────────  │
              │  createCard()          │
              └───────────────────────┘
                   │    │    │    │
        ┌──────────┘    │    │    └─────────┐
        ↓               ↓    ↓              ↓
   ┌─────────┐   ┌──────────┐   ┌──────────────┐
   │ WAVES   │   │CardToken │   │   BidNFT     │
   │ .mint() │   │ (deploy) │   │  .mint()     │
   └─────────┘   └──────────┘   └──────────────┘
                       │                  │
                       ↓                  │
              ┌────────────────┐          │
              │  SurfSwap.sol  │←─────────┤
              │  ─────────────  │          │
              │ initializePool()│          │
              └────────────────┘          │
                   ↕                      │
        ┌────────────────────────┐        │
        │ WhirlpoolStaking.sol   │←───────┘
        │ ─────────────────────   │
        │ registerCard()          │
        │ autoStake()             │
        │ ownerOfCard()           │
        └────────────────────────┘
                   ↕
        ┌────────────────────────┐
        │        Users           │
        │  ───────────────────    │
        │  stake() / unstake()   │
        │  swapExact()           │
        │  claimRewards()        │
        └────────────────────────┘
```

## Data Flow

### 1. Card Creation

**User → WhirlpoolRouter.createCard()**

```
Step 1: Router deploys new CardToken (10M supply to Router)
Step 2: Router calls WAVES.mint() for 2000 WAVES
        ├─ 500 WAVES to Router
        └─ 1500 WAVES to User

Step 3: Router calculates distributions
        CardToken (10M):
        ├─ 7.5M to Router (for AMM)
        ├─ 2M to Router (for auto-stake)
        └─ 500K to Protocol

Step 4: Router → WhirlpoolStaking.registerCard(cardId, token)
        (Registers token address)

Step 5: Router → SurfSwap.initializePool(cardId, token, 500 WAVES, 7.5M CARD)
        (Transfers tokens, initializes reserves)

Step 6: Router → WhirlpoolStaking.autoStake(cardId, user, 2M)
        (User becomes first staker → NFT owner)

Step 7: Router → BidNFT.mint(cardId, tokenURI)
        (Mints NFT, ownerOf() reads from Whirlpool)

Step 8: Router → WhirlpoolStaking.distributeMintFee{value: 0.05 ETH}
        (Mint fee distributed to all stakers)
```

### 2. Swapping (CARD → WAVES)

**User → SurfSwap.swapExact(cardToken, WAVES, amount, minOut)**

```
Step 1: User transfers CARD tokens to SurfSwap
Step 2: SurfSwap calculates output using constant product formula
        amountOut = wavesReserve - (wavesReserve * cardReserve) / (cardReserve + amountIn)
Step 3: Take 0.3% fee from output
Step 4: Update reserves:
        ├─ cardReserve += amountIn
        └─ wavesReserve -= amountOut
Step 5: Proportionally REDUCE stakedCards:
        stakedReduction = amountOut * stakedCards / cardReserve
        stakedCards -= stakedReduction
Step 6: Transfer fee to WhirlpoolStaking
Step 7: WhirlpoolStaking.distributeSwapFees(cardId, fee)
        ├─ Increment accWavesPerShare
        └─ Stakers can harvest later
Step 8: Transfer WAVES output to user
```

**Key**: `stakedCards` proportionally decreases when tokens leave the pool, reducing effective balance of all stakers.

### 3. Staking (Single-sided LP)

**User → WhirlpoolStaking.stake(cardId, amount)**

```
Step 1: User transfers CARD tokens to Whirlpool
Step 2: Harvest pending rewards for user
Step 3: Calculate LP shares to mint:
        IF totalShares == 0:
            shares = amount (1:1 bootstrap)
        ELSE:
            currentStaked = SurfSwap.getStakedCards(cardId)
            shares = amount * totalShares / currentStaked
Step 4: Whirlpool → SurfSwap.addToCardReserve(cardId, amount)
        ├─ cardReserve += amount
        └─ stakedCards += amount
Step 5: Update user's shares
Step 6: Update debts (MasterChef pattern)
Step 7: Check if user now has most shares
        IF userShares > currentOwnerShares:
            ├─ currentOwner = user
            ├─ Emit OwnerChanged event
            └─ BidNFT.ownerOf() now returns user
```

### 4. Unstaking

**User → WhirlpoolStaking.unstake(cardId, shares)**

```
Step 1: Harvest pending rewards
Step 2: Calculate proportional card tokens:
        stakedCards = SurfSwap.getStakedCards(cardId)
        cardAmount = shares * stakedCards / totalShares
Step 3: Update shares
Step 4: Whirlpool → SurfSwap.removeFromCardReserve(cardId, cardAmount)
        ├─ cardReserve -= cardAmount
        └─ stakedCards -= cardAmount
Step 5: Transfer CARD tokens to user
Step 6: IF user was owner AND userShares now < anotherUser:
            Owner changes (requires another call or frontrun)
```

### 5. Fee Distribution (MasterChef Pattern)

**Swap Fee Distribution:**

```
When swap occurs:
    fee = swapAmount * 0.003
    WhirlpoolStaking.distributeSwapFees(cardId, fee)
    
In distributeSwapFees():
    accWavesPerShare += fee * ACC_PRECISION / totalShares
    
When user harvests:
    pending = userShares * accWavesPerShare / ACC_PRECISION - userDebt
    Transfer pending WAVES to user
    userDebt = userShares * accWavesPerShare / ACC_PRECISION
```

**Mint Fee Distribution:**

```
When card created:
    WhirlpoolStaking.distributeMintFee{value: 0.05 ETH}
    
In distributeMintFee():
    accEthPerWeight += 0.05 ETH * ACC_PRECISION / totalGlobalWeight
    
Where totalGlobalWeight includes:
    ├─ All card LP shares (1x weight)
    └─ All WETH staked (1.5x weight)
    
When user harvests:
    pending = userWeight * accEthPerWeight / ACC_PRECISION - userDebt
    Transfer pending ETH to user
```

## Storage Layout

### SurfSwap

```solidity
struct CardPool {
    address token;          // Card token address
    uint256 wavesReserve;   // WAVES in pool
    uint256 cardReserve;    // Total card tokens (AMM + staked)
    uint256 stakedCards;    // Portion from staking (subset of cardReserve)
}

mapping(uint256 => CardPool) cards;
mapping(address => uint256) tokenToCard;
mapping(address => bool) isCardToken;

uint256 wavesWethReserve;  // WAVES in WETH pool
uint256 wethReserve;        // WETH in pool (virtual from staking)
```

### WhirlpoolStaking

```solidity
struct CardStake {
    address token;              // Card token address
    uint256 totalShares;        // Total LP shares issued
    uint256 totalStaked;        // Tracked separately (informational)
    address currentOwner;       // Current NFT owner
    uint256 ownerShares;        // Owner's share count
    uint256 accWavesPerShare;   // MasterChef accumulator
}

mapping(uint256 => CardStake) cardStakes;
mapping(uint256 => mapping(address => uint256)) userCardShares;
mapping(uint256 => mapping(address => uint256)) userCardDebt;

// WETH staking
uint256 totalWethStaked;
uint256 accWavesPerWethShare;
mapping(address => uint256) userWethStake;
mapping(address => uint256) userWethDebt;

// Global mint fee distribution
uint256 accEthPerWeight;
uint256 totalGlobalWeight;
mapping(address => uint256) userGlobalDebt;
mapping(address => uint256) userGlobalWeight;
```

### WhirlpoolRouter

```solidity
uint256 totalCards_;
mapping(uint256 => address) cardTokens;
```

### BidNFT

```solidity
mapping(uint256 => string) _tokenURIs;
mapping(uint256 => bool) _exists;
```

## Security Considerations

### Address Prediction Pattern

Router deployment uses CREATE address prediction to allow circular dependencies:

```solidity
uint256 nonce = vm.getNonce(deployer);
address predictedRouter = vm.computeCreateAddress(deployer, nonce + 4);
```

**Risk**: If nonce calculation is wrong, deployment fails. 
**Mitigation**: Deploy script uses fixed sequence, tested in Whirlpool.t.sol.

### Reentrancy Protection

All state-changing functions use `nonReentrant` modifier from OpenZeppelin.

**Critical paths**:
- stake/unstake (modifies shares + harvests rewards)
- swap (modifies reserves + distributes fees)
- WETH operations (sends ETH)

### Integer Arithmetic

Uses Solidity 0.8.20 built-in overflow protection.

**Precision loss**:
- MasterChef accumulators use `ACC_PRECISION = 1e18`
- Share calculations round down (favors existing stakers)

### Front-running

**Ownership Changes**: 
- User A unstakes → ownership threshold vulnerable
- Attacker can frontrun with stake() to claim ownership

**Slippage**:
- All swaps require `minAmountOut` parameter

### stakedCards Proportional Tracking

When swaps occur, `stakedCards` is adjusted proportionally. Edge case:

If `stakedCards > cardReserve` (should never happen), `removeFromCardReserve` clamps:
```solidity
if (stakedReduction > pool.stakedCards) stakedReduction = pool.stakedCards;
```

**Potential issue**: Rounding errors over many swaps could cause drift.
**Impact**: Minimal (< 1 wei per swap), self-correcting over time.

### WETH Pool Bootstrap

First WETH stake initializes with 500 WAVES virtual liquidity:

```solidity
if (wavesWethReserve == 0 && wethReserve > 0) {
    wavesWethReserve = 500 ether; // bootstrap
}
```

**Risk**: First WETH staker has no protection against immediate arbitrage.
**Mitigation**: Bootstrap value chosen to be minimal but sufficient for price discovery.

## Gas Optimization

### MasterChef Pattern

O(1) gas regardless of number of stakers:
- Per-share accumulator
- User debt tracking
- No loops over stakers

### Batch Operations

Not implemented. Users must:
- Harvest rewards per card separately
- Stake/unstake each card individually

**Future optimization**: `harvestAll()` function.

### View Functions

All view functions are free (off-chain):
- `getPrice()`
- `effectiveBalance()`
- `pendingRewards()`
- `ownerOfCard()`

## Upgrade Path

**There is none.** Contracts are immutable.

If bugs are found post-deployment:
1. Deploy new system
2. Migrate users manually
3. Original system continues forever

This is by design for trustlessness.

## Dependencies

- OpenZeppelin Contracts 5.1.0
  - ReentrancyGuard
  - SafeERC20
  - ERC20
  - ERC721
- Foundry (Forge, Anvil)

## Contract Addresses (Mainnet - TBD)

```
WAVES:             TBD
WhirlpoolRouter:   TBD
WhirlpoolStaking:  TBD
SurfSwap:          TBD
BidNFT:            TBD
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for deployment instructions.
