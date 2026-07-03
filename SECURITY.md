# Security & Audit Status — Whirlpool (ERC-1142)

**Status**: Post-audit hardening complete. **NOT AUDITED BY A PROFESSIONAL FIRM** — this is internal research + iterative security work.

## Critical & High Issues Fixed (from independent manual review)

### 1. CRITICAL — Unbacked WETH-pool bootstrap drain
- **Previously**: `addToWethReserve` (and first stake) invented `500 ether` virtual WAVES with no backing transfer.
- First WETH staker (even 1 wei) could immediately unstake and drain up to 500 real WAVES from the shared contract balance (card pool liquidity).
- Repeatable because `wavesWethReserve` reset on full unstake.

**Fix (this iteration)**:
- Removed all auto-bootstrap of `wavesWethReserve`.
- Added `seedWethLiquidity(uint256)` — **only callable by Router**, performs *real* WAVES transfer.
- Router now automatically seeds 500 WAVES (real) on the first `createCard`.
- Enforced minimum seed (1 ether).
- 1 wei of WAVES is permanently excluded from accounting on seed (locked minimum liquidity).
- New view: `isWethPoolSeeded()`.
- New event: `WethLiquiditySeeded`.

WETH pool now requires protocol-backed liquidity before use.

### 2. HIGH — Cross-contract reentrancy via GlobalRewards
- Debt was updated *after* the ETH `call`.
- CardStaking and WethPool had separate `nonReentrant` — attacker could bounce between them.

**Fix**:
- Effects-before-interactions: debt written before the send.
- `GlobalRewards` now inherits `ReentrancyGuard` and `harvestGlobal` is `nonReentrant`.

### 3. MEDIUM — BidNFT.balanceOf always 0
- Never called `_mint` (by design for virtual/dynamic ownership).

**Fix**:
- Proper override that reverts with a clear message directing to `CardStaking.ownerOfCard(cardId)`.

### Other Improvements in This Iteration
- Modern custom errors throughout SurfSwap (gas + clarity).
- `isWethPoolSeeded()` view + proper seeding event.
- Locked minimum liquidity on WETH seed.
- Updated tests, router, interfaces, and docs.
- Previous zero-staked-cards re-bootstrap logic retained.

## Remaining / Known
- Contract sizes were previously a concern (now well under limit thanks to refactoring + viaIR).
- stakedCards proportional tracking rounding is negligible.
- No admin keys, immutable by design.
- High complexity around ownership + active defense — economic assumptions should be modeled.

## Recommendations (for real deployment)
- Professional audit (Trail of Bits / OpenZeppelin / etc.)
- Formal verification of AMM math + share calculations.
- Economic simulation of ownership warfare.
- Bug bounty.
- Monitoring for ownership events and WETH pool TVL.

## How to Verify the Fixes
- `forge test` (all pass)
- Look for `seedWethLiquidity`, `isWethPoolSeeded`, `WethLiquiditySeeded` event, updated `_harvest`, and `balanceOf` revert.
- In a fresh deploy, first card creation seeds the WETH pool safely.

**Last updated**: 2026-07-02 (iterative hardening pass)

This work was done in direct response to detailed static analysis. The paired frontend (cog-works) has also received UX improvements around slippage protection as a direct result.