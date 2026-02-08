import { useState, useMemo } from 'react'
import { useAccount } from 'wagmi'
import { useAllCards } from '../hooks/useCards'
import Card from './Card'
import Sidebar from './Sidebar'

interface MarketplaceProps {
  onToast: (msg: string, type: 'success' | 'error' | 'info') => void
}

export default function Marketplace({ onToast }: MarketplaceProps) {
  const { address } = useAccount()
  const { cards, totalCards, isLoading } = useAllCards()
  const [sortBy, setSortBy] = useState('id')
  const [filterStaked, setFilterStaked] = useState(false)
  const [filterOwned, setFilterOwned] = useState(false)

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
    <div style={{ display: 'flex', flexDirection: 'row', gap: '24px', width: '100%' }}>
      <div className="hidden lg:block">
        <Sidebar
          sortBy={sortBy} setSortBy={setSortBy}
          filterStaked={filterStaked} setFilterStaked={setFilterStaked}
          filterOwned={filterOwned} setFilterOwned={setFilterOwned}
        />
      </div>

      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="lg:hidden" style={{ marginBottom: '16px', display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
          <button className={`btn-secondary ${filterStaked ? 'active' : ''}`} onClick={() => setFilterStaked(!filterStaked)} style={{ fontSize: '12px', borderRadius: '10px' }}>🔒 Staked</button>
          <button className={`btn-secondary ${filterOwned ? 'active' : ''}`} onClick={() => setFilterOwned(!filterOwned)} style={{ fontSize: '12px', borderRadius: '10px' }}>👤 Owned</button>
          <select value={sortBy} onChange={e => setSortBy(e.target.value)} style={{ fontSize: '12px', height: '32px', borderRadius: '10px' }}>
            <option value="id"># ID</option>
            <option value="price-asc">↑ Price</option>
            <option value="price-desc">↓ Price</option>
            <option value="name">A-Z</option>
          </select>
        </div>

        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
          <span style={{ fontSize: '14px', color: 'var(--text-muted)' }}>
            {isLoading ? 'Loading...' : `${filtered.length} of ${totalCards} cards`}
          </span>
        </div>

        {isLoading ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: '60px 0' }}>
            <div style={{
              width: '40px', height: '40px', border: '3px solid var(--border)',
              borderTopColor: '#8b5cf6', borderRadius: '50%',
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
