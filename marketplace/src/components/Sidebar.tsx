interface SidebarProps {
  sortBy: string
  setSortBy: (s: string) => void
  filterStaked: boolean
  setFilterStaked: (b: boolean) => void
  filterOwned: boolean
  setFilterOwned: (b: boolean) => void
}

export default function Sidebar({ sortBy, setSortBy, filterStaked, setFilterStaked, filterOwned, setFilterOwned }: SidebarProps) {
  return (
    <aside style={{
      width: '200px',
      flexShrink: 0,
      display: 'flex',
      flexDirection: 'column',
      gap: '20px',
      padding: '0 16px 0 0',
    }}>
      <div>
        <h3 style={{ fontSize: '11px', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '1px', color: 'var(--text-muted)', marginBottom: '10px', fontFamily: "'Inter Tight', sans-serif" }}>
          Filters
        </h3>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
          <button
            className={`btn-secondary ${filterStaked ? 'active' : ''}`}
            onClick={() => setFilterStaked(!filterStaked)}
            style={{ fontSize: '13px', textAlign: 'left', borderRadius: '10px' }}
          >
            🔒 Staked Only
          </button>
          <button
            className={`btn-secondary ${filterOwned ? 'active' : ''}`}
            onClick={() => setFilterOwned(!filterOwned)}
            style={{ fontSize: '13px', textAlign: 'left', borderRadius: '10px' }}
          >
            👤 Owned by Me
          </button>
        </div>
      </div>

      <div>
        <h3 style={{ fontSize: '11px', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '1px', color: 'var(--text-muted)', marginBottom: '10px', fontFamily: "'Inter Tight', sans-serif" }}>
          Sort By
        </h3>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
          {[
            { key: 'id', label: '# ID' },
            { key: 'price-asc', label: '↑ Price Low' },
            { key: 'price-desc', label: '↓ Price High' },
            { key: 'name', label: 'A-Z Name' },
          ].map(s => (
            <button
              key={s.key}
              className={`btn-secondary ${sortBy === s.key ? 'active' : ''}`}
              onClick={() => setSortBy(s.key)}
              style={{ fontSize: '13px', textAlign: 'left', borderRadius: '10px' }}
            >
              {s.label}
            </button>
          ))}
        </div>
      </div>
    </aside>
  )
}
