/**
 * @module Card
 * @description Individual NFT card component with swap-stake and claim-rewards interactions.
 *
 * This is the core interactive element of the marketplace. Each card displays:
 * - A colored gradient header (cycled by card ID)
 * - Owner/staked badges
 * - Card name, symbol, and current WAVES price
 * - **SwapStake UI** — percentage selector + source card dropdown + execute button
 * - **Claim rewards** button (shown only when pendingRewards > 0)
 * - Collapsible stats panel (owner address, reserves, stake, token address)
 *
 * ## SwapStake Flow (the key user interaction)
 *
 * SwapStake atomically moves your staked position from one card to another:
 *
 * 1. User selects a **percentage** (25%, 50%, or 100%) of shares to move
 * 2. User selects a **source card** from the dropdown (only cards they have stake in)
 * 3. User clicks "⚡ Swap Stake"
 * 4. Contract call: `WhirlpoolStaking.swapStake(fromCardId, toCardId, shares)`
 *    - Internally: unstakes from source → swaps CARD_A → WAVES → CARD_B via reserve math → stakes into destination
 *    - All in one transaction, no token transfers needed (pure accounting)
 *    - 0.6% fee (double hop through WAVES at 0.3% each)
 * 5. Both source and destination cards' ownership is rechecked (biggest staker = owner)
 *
 * ## Contract Interactions
 * - `WhirlpoolStaking.swapStake(fromCardId, toCardId, shares)` — atomic position swap
 * - `WhirlpoolStaking.claimRewards(cardId)` — claim accumulated MasterChef rewards
 *
 * ## Props
 * @see CardProps
 */

import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { useAccount, useWriteContract } from 'wagmi'
import { formatWaves, shortenAddress } from '../lib/utils'
import { WHIRLPOOL_ADDRESS, WHIRLPOOL_ABI } from '../lib/contracts'
import type { CardData } from '../hooks/useCards'

/**
 * Rotating gradient palette for card headers.
 * Cards cycle through these based on `(card.id - 1) % length`.
 */
const GRADIENTS = [
  'linear-gradient(135deg, #f97316, #d97706)',
  'linear-gradient(135deg, #0891b2, #22d3ee)',
  'linear-gradient(135deg, #8b5cf6, #a78bfa)',
  'linear-gradient(135deg, #ec4899, #f472b6)',
  'linear-gradient(135deg, #10b981, #34d399)',
  'linear-gradient(135deg, #f59e0b, #fbbf24)',
  'linear-gradient(135deg, #ef4444, #f87171)',
  'linear-gradient(135deg, #6366f1, #818cf8)',
]

/**
 * Props for the Card component.
 * @property card - The card data to display (from useAllCards hook)
 * @property allCards - All cards in the system, needed to populate the source card dropdown
 * @property onToast - Callback to show toast notifications for tx success/failure
 */
interface CardProps {
  card: CardData
  allCards: CardData[]
  onToast: (msg: string, type: 'success' | 'error' | 'info') => void
}

export default function Card({ card, allCards, onToast }: CardProps) {
  const { address } = useAccount()
  const { writeContract } = useWriteContract()

  /** Whether the collapsible stats panel is open. */
  const [showStats, setShowStats] = useState(false)

  /** Percentage of source card shares to swap (25, 50, or 100). */
  const [swapPercent, setSwapPercent] = useState(100)

  /** Selected source card ID for swapStake (null = none selected). */
  const [fromCardId, setFromCardId] = useState<number | null>(null)

  /** Whether the connected wallet is the current NFT owner of this card. */
  const isOwner = address && card.owner.toLowerCase() === address.toLowerCase()

  /** Whether the connected wallet has any LP shares staked in this card. */
  const hasStake = card.userShares > 0n

  /** Gradient for this card's header, cycling through the palette. */
  const gradient = GRADIENTS[(card.id - 1) % GRADIENTS.length]

  /**
   * Execute swapStake: move shares from a source card to this card.
   *
   * Validation:
   * - Source card must be selected
   * - Source card must have user stake > 0
   * - Calculated shares (percent of source stake) must be > 0
   *
   * Calls WhirlpoolStaking.swapStake(fromCardId, toCardId, shares).
   */
  const handleSwap = () => {
    if (!fromCardId) { onToast('Select a source card', 'error'); return }
    const fromCard = allCards.find(c => c.id === fromCardId)
    if (!fromCard || fromCard.userShares === 0n) { onToast('No stake in source card', 'error'); return }

    // Calculate shares to swap based on selected percentage
    const shares = (fromCard.userShares * BigInt(swapPercent)) / 100n
    if (shares === 0n) { onToast('Zero shares', 'error'); return }

    writeContract({
      address: WHIRLPOOL_ADDRESS,
      abi: WHIRLPOOL_ABI,
      functionName: 'swapStake',
      args: [BigInt(fromCardId), BigInt(card.id), shares],
    }, {
      onSuccess: () => onToast(`Swapped stake to ${card.name}!`, 'success'),
      onError: (e) => onToast(e.message.slice(0, 80), 'error'),
    })
  }

  /**
   * Claim accumulated MasterChef rewards for this card.
   * Rewards accrue from swap fees proportional to the user's LP share.
   * Calls WhirlpoolStaking.claimRewards(cardId).
   */
  const handleClaim = () => {
    writeContract({
      address: WHIRLPOOL_ADDRESS,
      abi: WHIRLPOOL_ABI,
      functionName: 'claimRewards',
      args: [BigInt(card.id)],
    }, {
      onSuccess: () => onToast(`Claimed rewards from ${card.name}!`, 'success'),
      onError: (e) => onToast(e.message.slice(0, 80), 'error'),
    })
  }

  /**
   * Cards the user has stake in (excluding this card) — these are valid
   * source cards for the swapStake dropdown.
   */
  const stakedCards = allCards.filter(c => c.userShares > 0n && c.id !== card.id)

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, delay: card.id * 0.05 }}
      className="card-hover-glow"
      style={{
        background: 'var(--bg-card)',
        borderRadius: '12px',
        border: '1px solid var(--border)',
        overflow: 'hidden',
      }}
    >
      {/* Card image/gradient area — shows card ID watermark + owner/staked badges */}
      <div style={{
        position: 'relative',
        aspectRatio: '1',
        background: gradient,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}>
        {/* Large watermark card number */}
        <span style={{
          fontSize: '64px',
          fontWeight: 700,
          color: 'rgba(255,255,255,0.2)',
          fontFamily: "'JetBrains Mono', monospace",
        }}>
          #{card.id}
        </span>

        {/* Owner badge — shown when connected wallet is the NFT owner */}
        {isOwner && (
          <div style={{
            position: 'absolute', top: '8px', left: '8px',
            background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(8px)',
            padding: '4px 8px', borderRadius: '6px', fontSize: '11px',
          }}>
            👑 Owner
          </div>
        )}

        {/* Staked badge — shown when connected wallet has LP shares in this card */}
        {hasStake && (
          <div style={{
            position: 'absolute', top: '8px', right: '8px',
            background: 'rgba(249, 115, 22, 0.8)', backdropFilter: 'blur(8px)',
            padding: '4px 8px', borderRadius: '6px', fontSize: '11px', fontWeight: 600,
          }}>
            🔒 Staked
          </div>
        )}
      </div>

      {/* Card info and interaction area */}
      <div style={{ padding: '14px' }}>
        {/* Name and symbol row */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: '4px' }}>
          <h3 style={{ fontSize: '16px', fontWeight: 600, color: 'var(--text-primary)' }}>
            {card.name || `Card #${card.id}`}
          </h3>
          <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontFamily: "'JetBrains Mono', monospace" }}>
            {card.symbol}
          </span>
        </div>

        {/* Current price in WAVES (derived from AMM reserves) */}
        <div style={{ fontSize: '14px', fontWeight: 600, color: 'var(--ocean-cyan)', fontFamily: "'JetBrains Mono', monospace" }}>
          {formatWaves(card.price)} WAVES
        </div>

        {/* ═══ SwapStake UI Section ═══ */}
        <div style={{ marginTop: '12px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
          {/* Percentage selector — choose what fraction of source stake to move */}
          <div style={{ display: 'flex', gap: '6px' }}>
            {[25, 50, 100].map(p => (
              <button
                key={p}
                className={`btn-secondary ${swapPercent === p ? 'active' : ''}`}
                onClick={() => setSwapPercent(p)}
                style={{ fontSize: '12px', padding: '3px 8px', flex: 1 }}
              >
                {p}%
              </button>
            ))}
          </div>

          {/* Source card dropdown — only shows cards where user has stake */}
          <select
            value={fromCardId ?? ''}
            onChange={e => setFromCardId(e.target.value ? Number(e.target.value) : null)}
            style={{ width: '100%', height: '32px', fontSize: '12px' }}
          >
            <option value="">Select source card...</option>
            {stakedCards.map(c => (
              <option key={c.id} value={c.id}>
                #{c.id} {c.name} ({formatWaves(c.userShares)} staked)
              </option>
            ))}
          </select>

          {/* Execute swapStake button */}
          <button onClick={handleSwap} className="btn-primary" style={{ width: '100%', fontSize: '13px' }}>
            ⚡ Swap Stake
          </button>
        </div>

        {/* Claim rewards button — only visible when there are pending rewards */}
        {card.pendingRewards > 0n && (
          <button
            onClick={handleClaim}
            style={{
              marginTop: '8px', width: '100%', padding: '6px',
              background: 'rgba(8, 145, 178, 0.15)', border: '1px solid var(--ocean-blue)',
              borderRadius: '6px', color: 'var(--ocean-cyan)', fontSize: '12px',
              fontWeight: 600, cursor: 'pointer',
            }}
          >
            🎁 Claim {formatWaves(card.pendingRewards)} WAVES
          </button>
        )}

        {/* ═══ Collapsible Stats Panel ═══ */}
        <button
          onClick={() => setShowStats(!showStats)}
          style={{
            marginTop: '10px', width: '100%', padding: '6px',
            background: 'transparent', border: '1px solid var(--border)',
            borderRadius: '6px', color: 'var(--text-muted)', fontSize: '12px',
            cursor: 'pointer', display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          }}
        >
          <span>NFT Stats</span>
          <motion.span animate={{ rotate: showStats ? 180 : 0 }} transition={{ duration: 0.2 }}>
            ▾
          </motion.span>
        </button>

        <AnimatePresence>
          {showStats && (
            <motion.div
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: 'auto', opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              transition={{ duration: 0.25 }}
              style={{ overflow: 'hidden' }}
            >
              {/* Stats grid: owner, reserves, stake, token address */}
              <div style={{
                marginTop: '8px', padding: '10px',
                background: 'var(--bg-secondary)', borderRadius: '8px',
                fontSize: '12px', fontFamily: "'JetBrains Mono', monospace",
                display: 'flex', flexDirection: 'column', gap: '6px',
              }}>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: 'var(--text-muted)' }}>Owner</span>
                  <span>{shortenAddress(card.owner)}</span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: 'var(--text-muted)' }}>Reserves (WAVES)</span>
                  <span>{formatWaves(card.reserves.waves)}</span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: 'var(--text-muted)' }}>Reserves (Cards)</span>
                  <span>{formatWaves(card.reserves.cards)}</span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: 'var(--text-muted)' }}>Your Stake</span>
                  <span style={{ color: hasStake ? 'var(--sunset-orange)' : 'inherit' }}>
                    {formatWaves(card.userShares)}
                  </span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: 'var(--text-muted)' }}>Token</span>
                  <span>{shortenAddress(card.tokenAddress)}</span>
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </motion.div>
  )
}
