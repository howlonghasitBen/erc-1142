/**
 * @module App
 * @description Root application component for the Whirlpool NFT Marketplace.
 *
 * Provides top-level page routing between three views:
 * - **Explore** — Browse and interact with all Whirlpool cards (Marketplace)
 * - **Portfolio** — View your staked/owned cards and pending rewards
 * - **Create** — Mint new cards into the Whirlpool system
 *
 * Also manages a global toast notification system that child components
 * can trigger via the `onToast` callback prop.
 *
 * Layout structure:
 * ```
 * ┌─────────────────────────────┐
 * │  Header (fixed, z-50)       │
 * ├─────────────────────────────┤
 * │  Nav Tabs (sticky, z-40)    │
 * ├─────────────────────────────┤
 * │  Page Content (animated)    │
 * │  ┌─────────────────────┐    │
 * │  │ Marketplace / Port- │    │
 * │  │ folio / MintCard    │    │
 * │  └─────────────────────┘    │
 * └─────────────────────────────┘
 * Toast (fixed bottom-right)
 * ```
 *
 * Uses Framer Motion `AnimatePresence` for smooth page transitions
 * with a fade+slide animation (opacity + translateY).
 */

import { useState, useCallback } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import Header from './components/Header'
import Marketplace from './components/Marketplace'
import Portfolio from './components/Portfolio'
import MintCard from './components/MintCard'
import Toast from './components/Toast'

/** Union type for the three navigable pages in the app. */
type Page = 'explore' | 'portfolio' | 'create'

export default function App() {
  /** Currently active page tab. */
  const [page, setPage] = useState<Page>('explore')

  /**
   * Global toast state. Components call `onToast(message, type)` to show
   * a notification; it auto-dismisses after 4 seconds (handled by Toast).
   */
  const [toast, setToast] = useState({ message: '', type: 'info' as 'success' | 'error' | 'info', visible: false })

  /**
   * Memoized toast trigger — passed down to Marketplace, Portfolio, and MintCard
   * so they can surface transaction results and validation errors to the user.
   */
  const onToast = useCallback((message: string, type: 'success' | 'error' | 'info') => {
    setToast({ message, type, visible: true })
  }, [])

  /** Tab configuration: key maps to Page type, icon is emoji prefix. */
  const tabs: { key: Page; label: string; icon: string }[] = [
    { key: 'explore', label: 'Explore', icon: '🔍' },
    { key: 'portfolio', label: 'Portfolio', icon: '💼' },
    { key: 'create', label: 'Create', icon: '✨' },
  ]

  return (
    <div style={{ minHeight: '100vh', background: 'var(--bg-primary)' }}>
      <Header />

      {/* Spacer to offset the fixed-position header (64px tall) */}
      <div style={{ height: '64px' }} />

      {/* Navigation tabs — sticky below header so they remain visible on scroll */}
      <nav style={{
        display: 'flex',
        flexDirection: 'row',
        justifyContent: 'center',
        gap: '4px',
        padding: '12px 24px',
        borderBottom: '1px solid var(--border)',
        background: 'var(--bg-primary)',
        position: 'sticky',
        top: '64px',
        zIndex: 40,
      }}>
        {tabs.map(t => (
          <button
            key={t.key}
            onClick={() => setPage(t.key)}
            style={{
              padding: '8px 20px',
              borderRadius: '8px',
              border: 'none',
              background: page === t.key ? 'rgba(249, 115, 22, 0.12)' : 'transparent',
              color: page === t.key ? 'var(--sunset-orange)' : 'var(--text-secondary)',
              fontWeight: page === t.key ? 600 : 400,
              fontSize: '14px',
              cursor: 'pointer',
              transition: 'all 0.15s',
              fontFamily: "'Space Grotesk', sans-serif",
            }}
          >
            {t.icon} {t.label}
          </button>
        ))}
      </nav>

      {/* Page content — max-width container with animated transitions */}
      <main style={{
        maxWidth: '1400px',
        margin: '0 auto',
        padding: '24px',
      }}>
        <AnimatePresence mode="wait">
          <motion.div
            key={page}
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -12 }}
            transition={{ duration: 0.2 }}
          >
            {page === 'explore' && <Marketplace onToast={onToast} />}
            {page === 'portfolio' && <Portfolio onToast={onToast} />}
            {page === 'create' && <MintCard onToast={onToast} />}
          </motion.div>
        </AnimatePresence>
      </main>

      {/* Global toast notification — fixed bottom-right overlay */}
      <Toast
        message={toast.message}
        type={toast.type}
        visible={toast.visible}
        onClose={() => setToast(t => ({ ...t, visible: false }))}
      />
    </div>
  )
}
