/**
 * @module Marketplace
 * @description Main explore/browse page showing all Whirlpool cards in a filterable grid.
 *
 * Layout:
 * - **Desktop**: Sidebar (200px) + card grid (flex: 1)
 * - **Mobile**: Inline filter buttons + card grid (sidebar hidden via `lg:hidden`)
 *
 * ## Features
 * - **Sort** by ID, price ascending, price descending, or name A-Z
 * - **Filter** by "Staked Only" (cards where user has LP shares) or "Owned by Me"
 * - **Loading state** with a CSS spinner animation
 * - **Empty state** with a wave emoji placeholder
 *
 * ## Data Flow
 * Uses the `useAllCards()` hook which fetches all card data via multicall.
 * The filtered/sorted list is memoized with `useMemo` to avoid re-sorting on
 * every render — only recalculates when cards, sort, filter, or address change.
 *
 * @see Sidebar for the desktop filter/sort panel
 * @see Card for the individual card component
 * @see useAllCards for the data loading strategy
 */

import { useState, useMemo } from 'react'
import { useAccount } from 'wagmi'
import { useAllCards } from '../hooks/useCards'
import Card from './Card'
import Sidebar from './Sidebar'

/** @property onToast - Callback to trigger global toast notifications */
interface MarketplaceProps {
  onToast: (msg: string, type: 'success' | 'error' | 'info') => void
}

export default function Marketplace({ onToast }: MarketplaceProps) {
  const { address } = useAccount()
  const { cards, totalCards, isLoading } = useAllCards()

  /** Current sort key — one of 'id', 'price-asc', 'price-desc', 'name'. */
  const [sortBy, setSortBy] = useState('id')

  /** When true, only show cards where the connected user has staked LP shares. */
  const [filterStaked, setFilterStaked] = useState(false)

  /** When true, only show cards owned by the connected wallet. */
  const [filterOwned, setFilterOwned] = useState(false)

  /**
   * Filtered and sorted card list.
   * Memoized to avoid re-computation on unrelated re-renders.
   * Filters are applied first (staked, owned), then sorting.
   */
  const filtered = useMemo(() => {
    let result = [...cards]
    if (filterStaked) result = result.filter(c => c.userShares > 0n)
    if (filterOwned && address) result = result.filter(c => c.owner.toLowerCase() === address.toLowerCase())
    switch (sortBy) {
      case 'price-asc': result.sort((a, b) => Number(a.price - b.price)); break
      case 'price-desc': result.sort((a, b) => Number(b.price - a.price)); break
      case 'name': result.sort((a, b) => a.name.localeCompare(b.name)); break
      default: result.sort((a, b) => a.id - b.id)
    }
    return result
  }, [cards, sortBy, filterStaked, filterOwned, address])

  return (
    <div style={{
      display: 'flex',
      flexDirection: 'row',
      gap: '24px',
      width: '100%',
    }}>
      {/* Desktop sidebar — hidden on screens smaller than lg breakpoint */}
      <div className="hidden lg:block">
        <Sidebar
          sortBy={sortBy}
          setSortBy={setSortBy}
          filterStaked={filterStaked}
          setFilterStaked={setFilterStaked}
          filterOwned={filterOwned}
          setFilterOwned={setFilterOwned}
        />
      </div>

      {/* Main content area */}
      <div style={{ flex: 1, minWidth: 0 }}>
        {/* Mobile-only inline filter/sort controls (replaces sidebar on small screens) */}
        <div className="lg:hidden" style={{ marginBottom: '16px', display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
          <button className={`btn-secondary ${filterStaked ? 'active' : ''}`} onClick={() => setFilterStaked(!filterStaked)} style={{ fontSize: '12px' }}>🔒 Staked</button>
          <button className={`btn-secondary ${filterOwned ? 'active' : ''}`} onClick={() => setFilterOwned(!filterOwned)} style={{ fontSize: '12px' }}>👤 Owned</button>
          <select value={sortBy} onChange={e => setSortBy(e.target.value)} style={{ fontSize: '12px', height: '32px' }}>
            <option value="id"># ID</option>
            <option value="price-asc">↑ Price</option>
            <option value="price-desc">↓ Price</option>
            <option value="name">A-Z</option>
          </select>
        </div>

        {/* Results count header */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
          <span style={{ fontSize: '14px', color: 'var(--text-muted)' }}>
            {isLoading ? 'Loading...' : `${filtered.length} of ${totalCards} cards`}
          </span>
        </div>

        {/* Card grid with loading and empty states */}
        {isLoading ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: '60px 0' }}>
            <div style={{
              width: '40px', height: '40px', border: '3px solid var(--border)',
              borderTopColor: 'var(--sunset-orange)', borderRadius: '50%',
              animation: 'spin 0.8s linear infinite',
            }} />
            <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
          </div>
        ) : filtered.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '60px 0', color: 'var(--text-muted)' }}>
            <p style={{ fontSize: '48px', marginBottom: '12px' }}>🌊</p>
            <p>No cards found</p>
          </div>
        ) : (
          <div className="card-grid">
            {filtered.map(card => (
              <Card key={card.id} card={card} allCards={cards} onToast={onToast} />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
