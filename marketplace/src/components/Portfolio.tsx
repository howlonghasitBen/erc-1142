import { motion } from 'framer-motion'
import { useAccount } from 'wagmi'
import { useAllCards } from '../hooks/useCards'
import { formatWaves } from '../lib/utils'
import Card from './Card'

interface PortfolioProps {
  onToast: (msg: string, type: 'success' | 'error' | 'info') => void
}

export default function Portfolio({ onToast }: PortfolioProps) {
  const { address, isConnected } = useAccount()
  const { cards } = useAllCards()

  if (!isConnected) {
    return (
      <div style={{ textAlign: 'center', padding: '80px 0', color: 'var(--text-muted)' }}>
        <p style={{ fontSize: '48px', marginBottom: '16px' }}>🔗</p>
        <p style={{ fontSize: '18px' }}>Connect your wallet to view portfolio</p>
      </div>
    )
  }

  const stakedCards = cards.filter(c => c.userShares > 0n)
  const ownedCards = cards.filter(c => address && c.owner.toLowerCase() === address.toLowerCase())
  const totalPending = cards.reduce((sum, c) => sum + c.pendingRewards, 0n)

  const stats = [
    { label: 'Staked Cards', value: stakedCards.length, icon: '🔒', color: '#8b5cf6' },
    { label: 'Owned Cards', value: ownedCards.length, icon: '👑', color: '#FF613D' },
    { label: 'Pending Rewards', value: formatWaves(totalPending) + ' WAVES', icon: '🎁', color: '#22C55E' },
  ]

  const portfolioCards = [...new Map([...stakedCards, ...ownedCards].map(c => [c.id, c])).values()]

  return (
    <div>
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
              borderRadius: '16px',
              padding: '20px',
            }}
          >
            <div style={{ fontSize: '28px', marginBottom: '8px' }}>{s.icon}</div>
            <div style={{ fontSize: '24px', fontWeight: 700, color: s.color, fontFamily: "'DM Mono', monospace" }}>
              {s.value}
            </div>
            <div style={{ fontSize: '13px', color: 'var(--text-muted)', marginTop: '4px' }}>{s.label}</div>
          </motion.div>
        ))}
      </div>

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
