/**
 * @module Sidebar
 * @description Desktop filter and sort panel for the Marketplace page.
 *
 * Renders a fixed-width (200px) aside with two sections:
 * 1. **Filters** — Toggle buttons for "Staked Only" and "Owned by Me"
 * 2. **Sort By** — Exclusive selection buttons for sort order
 *
 * This component is purely presentational — all state is owned by the
 * parent Marketplace component and passed in via props. This keeps the
 * sidebar stateless and easy to hide on mobile (where inline controls
 * replace it).
 *
 * Hidden on mobile via the parent's `className="hidden lg:block"` wrapper.
 *
 * @see Marketplace for state management and how these props are used
 */

/**
 * Props for the Sidebar component.
 * All state is controlled by the parent Marketplace component.
 *
 * @property sortBy - Current sort key ('id' | 'price-asc' | 'price-desc' | 'name')
 * @property setSortBy - Callback to change sort order
 * @property filterStaked - Whether "Staked Only" filter is active
 * @property setFilterStaked - Toggle staked filter
 * @property filterOwned - Whether "Owned by Me" filter is active
 * @property setFilterOwned - Toggle owned filter
 */
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
      {/* ═══ Filter Section ═══ */}
      <div>
        <h3 style={{ fontSize: '11px', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '1px', color: 'var(--text-muted)', marginBottom: '10px' }}>
          Filters
        </h3>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
          {/* Toggle: show only cards where user has LP shares */}
          <button
            className={`btn-secondary ${filterStaked ? 'active' : ''}`}
            onClick={() => setFilterStaked(!filterStaked)}
            style={{ fontSize: '13px', textAlign: 'left' }}
          >
            🔒 Staked Only
          </button>
          {/* Toggle: show only cards where user is the NFT owner */}
          <button
            className={`btn-secondary ${filterOwned ? 'active' : ''}`}
            onClick={() => setFilterOwned(!filterOwned)}
            style={{ fontSize: '13px', textAlign: 'left' }}
          >
            👤 Owned by Me
          </button>
        </div>
      </div>

      {/* ═══ Sort Section ═══ */}
      <div>
        <h3 style={{ fontSize: '11px', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '1px', color: 'var(--text-muted)', marginBottom: '10px' }}>
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
              style={{ fontSize: '13px', textAlign: 'left' }}
            >
              {s.label}
            </button>
          ))}
        </div>
      </div>
    </aside>
  )
}
