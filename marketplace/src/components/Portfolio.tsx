/**
 * @module Portfolio
 * @description User's personal dashboard showing staked and owned Whirlpool cards.
 *
 * ## Layout
 * 1. **Stats row** — Three animated stat cards showing:
 *    - 🔒 Staked Cards — number of cards where user has LP shares
 *    - 👑 Owned Cards — number of cards where user is the NFT owner (biggest staker)
 *    - 🎁 Pending Rewards — total unclaimed WAVES rewards across all cards
 * 2. **Card grid** — Combined deduplicated list of staked + owned cards
 *
 * ## Data Flow
 * - Uses `useAllCards()` which fetches data for ALL cards, including user-specific
 *   fields (userShares, pendingRewards) based on the connected wallet
 * - Staked cards: `cards.filter(c => c.userShares > 0n)`
 * - Owned cards: `cards.filter(c => c.owner === address)`
 * - Portfolio cards: union of both, deduplicated by card ID using a Map
 *
 * ## Wallet Required
 * Shows a "Connect your wallet" prompt if no wallet is connected.
 *
 * @see useAllCards for how user-specific data is fetched
 * @see Card for the individual card display component
 */

import { motion } from 'framer-motion'
import { useAccount } from 'wagmi'
import { useAllCards } from '../hooks/useCards'
import { formatWaves } from '../lib/utils'
import Card from './Card'

/** @property onToast - Callback to trigger global toast notifications */
interface PortfolioProps {
  onToast: (msg: string, type: 'success' | 'error' | 'info') => void
}

export default function Portfolio({ onToast }: PortfolioProps) {
  const { address, isConnected } = useAccount()
  const { cards } = useAllCards()

  /* Prompt to connect wallet if not connected */
  if (!isConnected) {
    return (
      <div style={{ textAlign: 'center', padding: '80px 0', color: 'var(--text-muted)' }}>
        <p style={{ fontSize: '48px', marginBottom: '16px' }}>🔗</p>
        <p style={{ fontSize: '18px' }}>Connect your wallet to view portfolio</p>
      </div>
    )
  }

  /** Cards where the user has staked LP shares. */
  const stakedCards = cards.filter(c => c.userShares > 0n)

  /** Cards where the user is the current NFT owner (biggest staker). */
  const ownedCards = cards.filter(c => address && c.owner.toLowerCase() === address.toLowerCase())

  /** Total unclaimed WAVES rewards across all cards. */
  const totalPending = cards.reduce((sum, c) => sum + c.pendingRewards, 0n)

  /** Stats configuration for the dashboard cards. */
  const stats = [
    { label: 'Staked Cards', value: stakedCards.length, icon: '🔒', color: 'var(--sunset-orange)' },
    { label: 'Owned Cards', value: ownedCards.length, icon: '👑', color: 'var(--ocean-cyan)' },
    { label: 'Pending Rewards', value: formatWaves(totalPending) + ' WAVES', icon: '🎁', color: 'var(--sunset-gold)' },
  ]

  /**
   * Combined portfolio cards — union of staked and owned, deduplicated.
   * Uses a Map keyed by card ID to eliminate duplicates (a card can be both staked and owned).
   */
  const portfolioCards = [...new Map([...stakedCards, ...ownedCards].map(c => [c.id, c])).values()]

  return (
    <div>
      {/* ═══ Stats Dashboard ═══ */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
        gap: '16px',
        marginBottom: '32px',
      }}>
        {stats.map((s, i) => (
          <motion.div
            key={s.label}
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: i * 0.1 }}
            style={{
              background: 'var(--bg-card)',
              border: '1px solid var(--border)',
              borderRadius: '12px',
              padding: '20px',
            }}
          >
            <div style={{ fontSize: '28px', marginBottom: '8px' }}>{s.icon}</div>
            <div style={{ fontSize: '24px', fontWeight: 700, color: s.color, fontFamily: "'JetBrains Mono', monospace" }}>
              {s.value}
            </div>
            <div style={{ fontSize: '13px', color: 'var(--text-muted)', marginTop: '4px' }}>{s.label}</div>
          </motion.div>
        ))}
      </div>

      {/* ═══ Portfolio Card Grid ═══ */}
      {portfolioCards.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>
          <p>No staked or owned cards yet</p>
        </div>
      ) : (
        <div className="card-grid">
          {portfolioCards.map(card => (
            <Card key={card.id} card={card} allCards={cards} onToast={onToast} />
          ))}
        </div>
      )}
    </div>
  )
}
