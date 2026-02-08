import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { useAccount, useWriteContract } from 'wagmi'
import { formatWaves, shortenAddress } from '../lib/utils'
import { WHIRLPOOL_ADDRESS, WHIRLPOOL_ABI } from '../lib/contracts'
import type { CardData } from '../hooks/useCards'

const GRADIENTS = [
  'linear-gradient(135deg, #8b5cf6, #a78bfa)',
  'linear-gradient(135deg, #FF613D, #FF5D38)',
  'linear-gradient(135deg, #06b6d4, #22d3ee)',
  'linear-gradient(135deg, #ec4899, #f472b6)',
  'linear-gradient(135deg, #10b981, #34d399)',
  'linear-gradient(135deg, #f59e0b, #fbbf24)',
  'linear-gradient(135deg, #ef4444, #f87171)',
  'linear-gradient(135deg, #6366f1, #818cf8)',
]

interface CardProps {
  card: CardData
  allCards: CardData[]
  onToast: (msg: string, type: 'success' | 'error' | 'info') => void
}

export default function Card({ card, allCards, onToast }: CardProps) {
  const { address } = useAccount()
  const { writeContract } = useWriteContract()
  const [showStats, setShowStats] = useState(false)
  const [swapPercent, setSwapPercent] = useState(100)
  const [fromCardId, setFromCardId] = useState<number | null>(null)

  const isOwner = address && card.owner.toLowerCase() === address.toLowerCase()
  const hasStake = card.userShares > 0n
  const gradient = GRADIENTS[(card.id - 1) % GRADIENTS.length]

  const handleSwap = () => {
    if (!fromCardId) { onToast('Select a source card', 'error'); return }
    const fromCard = allCards.find(c => c.id === fromCardId)
    if (!fromCard || fromCard.userShares === 0n) { onToast('No stake in source card', 'error'); return }
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

  const stakedCards = allCards.filter(c => c.userShares > 0n && c.id !== card.id)

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, delay: card.id * 0.05 }}
      className="card-hover-glow"
      style={{
        background: 'var(--bg-card)',
        borderRadius: '16px',
        border: '1px solid var(--border)',
        overflow: 'hidden',
      }}
    >
      {/* Card gradient header */}
      <div style={{
        position: 'relative',
        aspectRatio: '1',
        background: gradient,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}>
        <span style={{
          fontSize: '64px',
          fontWeight: 700,
          color: 'rgba(255,255,255,0.25)',
          fontFamily: "'DM Mono', monospace",
        }}>
          #{card.id}
        </span>

        {isOwner && (
          <div style={{
            position: 'absolute', top: '8px', left: '8px',
            background: 'rgba(255,255,255,0.9)', backdropFilter: 'blur(8px)',
            padding: '4px 8px', borderRadius: '8px', fontSize: '11px', color: '#111827',
          }}>
            👑 Owner
          </div>
        )}

        {hasStake && (
          <div style={{
            position: 'absolute', top: '8px', right: '8px',
            background: 'rgba(139, 92, 246, 0.9)', backdropFilter: 'blur(8px)',
            padding: '4px 8px', borderRadius: '8px', fontSize: '11px', fontWeight: 600, color: 'white',
          }}>
            🔒 Staked
          </div>
        )}
      </div>

      <div style={{ padding: '14px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: '4px' }}>
          <h3 style={{ fontSize: '16px', fontWeight: 600, color: 'var(--text-primary)', fontFamily: "'Inter Tight', sans-serif" }}>
            {card.name || `Card #${card.id}`}
          </h3>
          <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontFamily: "'DM Mono', monospace" }}>
            {card.symbol}
          </span>
        </div>

        <div style={{ fontSize: '14px', fontWeight: 600, color: '#8b5cf6', fontFamily: "'DM Mono', monospace" }}>
          {formatWaves(card.price)} WAVES
        </div>

        {/* SwapStake UI */}
        <div style={{ marginTop: '12px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
          <div style={{ display: 'flex', gap: '6px' }}>
            {[25, 50, 100].map(p => (
              <button
                key={p}
                className={`btn-secondary ${swapPercent === p ? 'active' : ''}`}
                onClick={() => setSwapPercent(p)}
                style={{ fontSize: '12px', padding: '3px 8px', flex: 1, borderRadius: '8px' }}
              >
                {p}%
              </button>
            ))}
          </div>

          <select
            value={fromCardId ?? ''}
            onChange={e => setFromCardId(e.target.value ? Number(e.target.value) : null)}
            style={{ width: '100%', height: '32px', fontSize: '12px', borderRadius: '8px' }}
          >
            <option value="">Select source card...</option>
            {stakedCards.map(c => (
              <option key={c.id} value={c.id}>
                #{c.id} {c.name} ({formatWaves(c.userShares)} staked)
              </option>
            ))}
          </select>

          <button onClick={handleSwap} className="btn-primary" style={{ width: '100%', fontSize: '13px', borderRadius: '10px' }}>
            ⚡ Swap Stake
          </button>
        </div>

        {card.pendingRewards > 0n && (
          <button
            onClick={handleClaim}
            style={{
              marginTop: '8px', width: '100%', padding: '6px',
              background: 'rgba(5, 223, 114, 0.1)', border: '1px solid #22C55E',
              borderRadius: '8px', color: '#22C55E', fontSize: '12px',
              fontWeight: 600, cursor: 'pointer',
            }}
          >
            🎁 Claim {formatWaves(card.pendingRewards)} WAVES
          </button>
        )}

        {/* Stats toggle */}
        <button
          onClick={() => setShowStats(!showStats)}
          style={{
            marginTop: '10px', width: '100%', padding: '6px',
            background: 'transparent', border: '1px solid var(--border)',
            borderRadius: '8px', color: 'var(--text-muted)', fontSize: '12px',
            cursor: 'pointer', display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          }}
        >
          <span>NFT Stats</span>
          <motion.span animate={{ rotate: showStats ? 180 : 0 }} transition={{ duration: 0.2 }}>▾</motion.span>
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
              <div style={{
                marginTop: '8px', padding: '10px',
                background: 'var(--bg-secondary)', borderRadius: '10px',
                fontSize: '12px', fontFamily: "'DM Mono', monospace",
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
                  <span style={{ color: hasStake ? '#8b5cf6' : 'inherit' }}>
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
