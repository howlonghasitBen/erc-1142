/**
 * @module useCards
 * @description Custom React hook for loading all Whirlpool card data via multicall.
 *
 * ## 3-Phase Data Loading Strategy
 *
 * This hook uses wagmi's `useReadContracts` (multicall) to batch on-chain reads
 * efficiently. Data is loaded in three sequential phases:
 *
 * ### Phase 1: Total Cards Count
 * - Reads `WhirlpoolRouter.totalCards()` to know how many cards exist
 * - Single RPC call
 *
 * ### Phase 2: Token Addresses
 * - Reads `WhirlpoolRouter.cardToken(i)` for i = 1..MAX_CARDS
 * - Uses a fixed-size call list (MAX_CARDS = 100) to keep React hooks stable
 *   (hooks can't be called conditionally, so we always prepare 100 slots)
 * - Only enabled when totalCards > 0
 * - Returns the ERC-20 token address for each card
 *
 * ### Phase 3: Batch Card Data
 * - For each card with a known token address, fetches 8 fields in one multicall:
 *   1. `CardToken.name()` — card display name
 *   2. `CardToken.symbol()` — token ticker
 *   3. `SurfSwap.getPrice(cardId)` — current WAVES price from AMM
 *   4. `SurfSwap.getReserves(cardId)` — WAVES and card token reserves
 *   5. `WhirlpoolStaking.ownerOfCard(cardId)` — current NFT owner (biggest staker)
 *   6. `WhirlpoolStaking.stakeOf(cardId, user)` — connected user's LP shares
 *   7. `WhirlpoolStaking.pendingRewards(cardId, user)` — unclaimed rewards
 *   8. `BidNFT.tokenURI(cardId)` — NFT metadata URI
 *
 * ## Why Fixed-Size Call Lists?
 * React hooks must be called in the same order every render. If we used
 * `totalCards` to dynamically size the Phase 2 array, the hook call count
 * would change when totalCards updates, violating the Rules of Hooks.
 * Using MAX_CARDS = 100 as a fixed upper bound avoids this.
 *
 * ## User Context
 * When no wallet is connected, `userAddr` falls back to the zero address.
 * This means stakeOf and pendingRewards return 0, which is correct behavior.
 *
 * @returns {Object} { cards: CardData[], totalCards: number, isLoading: boolean }
 */

import { useReadContract, useReadContracts, useAccount } from 'wagmi'
import { useMemo } from 'react'
import { 
  ROUTER_ADDRESS, ROUTER_ABI, 
  SURFSWAP_ABI, SURFSWAP_ADDRESS,
  WHIRLPOOL_ABI, WHIRLPOOL_ADDRESS,
  CARD_TOKEN_ABI, BIDNFT_ABI, BIDNFT_ADDRESS
} from '../lib/contracts'

/**
 * Represents all on-chain data for a single Whirlpool card.
 *
 * @property id - Card ID (1-indexed, assigned sequentially by the Router)
 * @property name - Display name from the CardToken ERC-20
 * @property symbol - Token ticker symbol from the CardToken ERC-20
 * @property tokenAddress - Address of this card's ERC-20 token contract
 * @property price - Current price in WAVES (18 decimals) from SurfSwap AMM
 * @property reserves - AMM pool reserves: { waves, cards } both in 18 decimals
 * @property owner - Address of the current NFT owner (biggest LP staker)
 * @property userShares - Connected user's LP shares in this card's staking pool
 * @property pendingRewards - Connected user's unclaimed WAVES rewards for this card
 * @property tokenURI - Metadata URI from BidNFT (typically an IPFS link)
 */
export interface CardData {
  id: number
  name: string
  symbol: string
  tokenAddress: string
  price: bigint
  reserves: { waves: bigint; cards: bigint }
  owner: string
  userShares: bigint
  pendingRewards: bigint
  tokenURI: string
}

/** Zero address used as fallback when no wallet is connected. */
const ZERO_ADDR = '0x0000000000000000000000000000000000000000' as `0x${string}`

/**
 * Fixed upper bound for token address queries.
 * Must be >= MAX_CARDS in the contract (5000), but we use 100 for dev.
 * Keeps React hook call count stable across renders.
 */
const MAX_CARDS = 100

/**
 * Hook to fetch all Whirlpool card data via batched multicall reads.
 *
 * @returns cards - Array of CardData for all existing cards
 * @returns totalCards - Total number of cards created in the system
 * @returns isLoading - Whether the Phase 3 batch data is still loading
 */
export function useAllCards() {
  const { address } = useAccount()
  /** Use zero address when disconnected so stakeOf/pendingRewards return 0. */
  const userAddr = address || ZERO_ADDR

  // ═══ Phase 1: Get total card count from the Router ═══
  const { data: totalCardsRaw } = useReadContract({
    address: ROUTER_ADDRESS,
    abi: ROUTER_ABI,
    functionName: 'totalCards',
  })
  const totalCards = totalCardsRaw ? Number(totalCardsRaw) : 0

  // ═══ Phase 2: Fetch all token addresses (fixed-size for hook stability) ═══
  const tokenAddrContracts = useMemo(() => {
    const calls = []
    for (let i = 1; i <= MAX_CARDS; i++) {
      calls.push({
        address: ROUTER_ADDRESS,
        abi: ROUTER_ABI,
        functionName: 'cardToken',
        args: [BigInt(i)],
      } as const)
    }
    return calls
  }, [])

  const { data: tokenAddrsRaw } = useReadContracts({
    contracts: tokenAddrContracts,
    query: { enabled: totalCards > 0 },
  })

  // ═══ Phase 3: Build per-card data queries from known token addresses ═══
  const cardDataContracts = useMemo(() => {
    if (!tokenAddrsRaw || totalCards === 0) return []
    const calls: any[] = []
    for (let i = 0; i < totalCards; i++) {
      const tokenAddr = tokenAddrsRaw[i]?.result as `0x${string}` | undefined
      if (!tokenAddr) continue
      const cardId = BigInt(i + 1)

      // 8 calls per card — order matters for parsing in Phase 4
      calls.push(
        { address: tokenAddr, abi: CARD_TOKEN_ABI, functionName: 'name' } as const,           // [0] name
        { address: tokenAddr, abi: CARD_TOKEN_ABI, functionName: 'symbol' } as const,         // [1] symbol
        { address: SURFSWAP_ADDRESS, abi: SURFSWAP_ABI, functionName: 'getPrice', args: [cardId] } as const,      // [2] price
        { address: SURFSWAP_ADDRESS, abi: SURFSWAP_ABI, functionName: 'getReserves', args: [cardId] } as const,    // [3] reserves
        { address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'ownerOfCard', args: [cardId] } as const,  // [4] owner
        { address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'stakeOf', args: [cardId, userAddr] } as const,        // [5] userShares
        { address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'pendingRewards', args: [cardId, userAddr] } as const, // [6] pendingRewards
        { address: BIDNFT_ADDRESS, abi: BIDNFT_ABI, functionName: 'tokenURI', args: [cardId] } as const,          // [7] tokenURI
      )
    }
    return calls
  }, [tokenAddrsRaw, totalCards, userAddr])

  const { data: cardDataRaw, isLoading } = useReadContracts({
    contracts: cardDataContracts.length > 0 ? cardDataContracts : undefined,
    query: { enabled: cardDataContracts.length > 0 },
  })

  // ═══ Phase 4: Parse multicall results into CardData[] ═══
  const cards = useMemo(() => {
    if (!cardDataRaw || !tokenAddrsRaw || totalCards === 0) return []
    const result: CardData[] = []
    const FIELDS = 8 // number of calls per card (must match Phase 3)

    for (let i = 0; i < totalCards; i++) {
      const tokenAddr = tokenAddrsRaw[i]?.result as string | undefined
      if (!tokenAddr) continue
      const base = i * FIELDS
      if (base + FIELDS > cardDataRaw.length) break

      const reserves = cardDataRaw[base + 3]?.result as unknown as [bigint, bigint] | undefined

      result.push({
        id: i + 1,
        name: (cardDataRaw[base]?.result as string) ?? '',
        symbol: (cardDataRaw[base + 1]?.result as string) ?? '',
        tokenAddress: tokenAddr,
        price: (cardDataRaw[base + 2]?.result as bigint) ?? 0n,
        reserves: {
          waves: reserves?.[0] ?? 0n,
          cards: reserves?.[1] ?? 0n,
        },
        owner: (cardDataRaw[base + 4]?.result as string) ?? '',
        userShares: (cardDataRaw[base + 5]?.result as bigint) ?? 0n,
        pendingRewards: (cardDataRaw[base + 6]?.result as bigint) ?? 0n,
        tokenURI: (cardDataRaw[base + 7]?.result as string) ?? '',
      })
    }
    return result
  }, [cardDataRaw, tokenAddrsRaw, totalCards])

  return { cards, totalCards, isLoading }
}
