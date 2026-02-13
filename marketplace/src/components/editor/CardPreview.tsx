/** Live card preview rendering with theme support and stat badges */
import type { CardEditorData } from './types'
import './card-preview.css'

interface CardPreviewProps {
  card: CardEditorData
}

export default function CardPreview({ card }: CardPreviewProps) {
  const theme = card.theme || {}

  return (
    <div className="live-preview-container">
      <div className="preview-label">Live Preview</div>

      <div
        className="preview-card"
        style={{
          background: theme.background || 'linear-gradient(145deg, #2a2a2a, #1a1a1a)',
        }}
      >
        {/* Header */}
        <div
          className="preview-header"
          style={{
            background: theme.header?.background,
            color: theme.header?.color,
            textShadow: theme.header?.textShadow,
            boxShadow: theme.header?.boxShadow,
          }}
        >
          <div>
            {/* Stat orbs */}
            <div style={{ display: 'flex', gap: 4, marginBottom: 4 }}>
              {[
                { value: card.stats?.hp || 0, color: '#dc2626', shadow: '#991b1b' },
                { value: card.stats?.mana || 0, color: '#2563eb', shadow: '#1e40af' },
                { value: card.stats?.crit || 0, color: '#d97706', shadow: '#92400e' },
              ].map((orb, i) => (
                <div key={i} style={{
                  width: 24, height: 24, borderRadius: '50%',
                  background: `radial-gradient(circle at 35% 35%, ${orb.color}, ${orb.shadow})`,
                  border: '2px solid #1a1a1a',
                  boxShadow: '0 1px 3px rgba(0,0,0,0.4), inset 0 -1px 2px rgba(0,0,0,0.3)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}>
                  <span style={{ fontSize: 10, fontWeight: 900, color: '#fff', fontFamily: "'DM Mono', monospace", lineHeight: 1, textShadow: '0 1px 2px rgba(0,0,0,0.6)' }}>{orb.value}</span>
                </div>
              ))}
            </div>
            <div className="preview-mana-cost">
              {card.manaCost?.map((mana, idx) => (
                <div
                  key={idx}
                  className="preview-mana-orb"
                  style={{ background: mana.color, color: mana.textColor || '#fff' }}
                  title={mana.type}
                >
                  <div className="orb-value">{mana.value}</div>
                </div>
              ))}
            </div>
            <div className="preview-title">
              {card.name || 'Untitled'} {card.subtitle}
            </div>
          </div>
          <div
            className="preview-level"
            style={{
              background: theme.stat?.background,
              color: theme.stat?.color,
              boxShadow: theme.stat?.boxShadow,
              border: theme.stat?.border,
            }}
          >
            LVL {card.level}
          </div>
        </div>

        {/* Image */}
        <div
          className="preview-image-area"
          style={{
            background: theme.imageArea?.background,
            border: theme.imageArea?.border,
            boxShadow: theme.imageArea?.boxShadow,
          }}
        >
          {card.imageData ? (
            <img src={card.imageData} alt={card.name} className="preview-image" />
          ) : (
            <div className="preview-image-placeholder">
              <span>🖼️</span>
              <span>No Image</span>
            </div>
          )}
        </div>

        {/* Type & Power */}
        <div
          className="preview-type-section"
          style={{
            background: theme.typeSection?.background,
            color: theme.typeSection?.color,
            textShadow: theme.typeSection?.textShadow,
            boxShadow: theme.typeSection?.boxShadow,
          }}
        >
          <div>{card.type || 'Creature'}</div>
          <div className="preview-power-stats">
            <div
              className="preview-stat"
              style={{
                background: theme.stat?.background,
                border: theme.stat?.border,
                color: theme.stat?.color,
                boxShadow: theme.stat?.boxShadow,
              }}
            >
              ATK: {card.stats?.attack || 0}
            </div>
            <div
              className="preview-stat"
              style={{
                background: theme.stat?.background,
                border: theme.stat?.border,
                color: theme.stat?.color,
                boxShadow: theme.stat?.boxShadow,
              }}
            >
              DEF: {card.stats?.defense || 0}
            </div>
          </div>
        </div>

        {/* Flavor Text */}
        <div
          className="preview-flavor-text"
          style={{
            background: theme.flavorText?.background,
            color: theme.flavorText?.color,
            borderBottom: theme.flavorText?.border,
          }}
        >
          <div className="preview-flavor-content">
            {card.moveName && <div className="preview-move-name">{card.moveName}</div>}
            {card.flavorText || 'No flavor text yet...'}
          </div>
        </div>

        {/* Bottom */}
        <div
          className="preview-bottom"
          style={{ background: theme.bottomSection?.background }}
        >
          <div className="preview-artist" style={{ color: theme.flavorText?.color }}>
            {card.artist || '◆Waves TCG◆'}
          </div>
          <div
            className="preview-rarity"
            style={{
              background: theme.rarity?.background,
              color: theme.rarity?.color,
              border: theme.rarity?.border,
              boxShadow: theme.rarity?.boxShadow,
            }}
          >
            {card.rarity || '★1/1★'}
          </div>
        </div>
      </div>

      <div className="preview-stats-summary">
        <div className="stat-pill">
          <span className="stat-icon">HP</span>
          <span>{card.stats?.hp || 0}</span>
        </div>
        <div className="stat-pill">
          <span className="stat-icon">ATK</span>
          <span>{card.stats?.attack || 0}</span>
        </div>
        <div className="stat-pill">
          <span className="stat-icon">DEF</span>
          <span>{card.stats?.defense || 0}</span>
        </div>
        <div className="stat-pill">
          <span className="stat-icon">MP</span>
          <span>{card.stats?.mana || 0}</span>
        </div>
      </div>
    </div>
  )
}
