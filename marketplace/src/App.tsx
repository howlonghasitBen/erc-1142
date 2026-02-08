import { useState, useCallback } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import Header from './components/Header'
import Marketplace from './components/Marketplace'
import Portfolio from './components/Portfolio'
import MintCard from './components/MintCard'
import Toast from './components/Toast'

type Page = 'explore' | 'portfolio' | 'create'

export default function App() {
  const [page, setPage] = useState<Page>('explore')
  const [toast, setToast] = useState({ message: '', type: 'info' as 'success' | 'error' | 'info', visible: false })

  const onToast = useCallback((message: string, type: 'success' | 'error' | 'info') => {
    setToast({ message, type, visible: true })
  }, [])

  const tabs: { key: Page; label: string; icon: string }[] = [
    { key: 'explore', label: 'Explore', icon: '🔍' },
    { key: 'portfolio', label: 'Portfolio', icon: '💼' },
    { key: 'create', label: 'Create', icon: '✨' },
  ]

  return (
    <div style={{ minHeight: '100vh', background: 'var(--bg-primary)' }}>
      <Header />
      <div style={{ height: '64px' }} />

      {/* Navigation tabs */}
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
              borderRadius: '12px',
              border: 'none',
              background: page === t.key ? 'rgba(139, 92, 246, 0.08)' : 'transparent',
              color: page === t.key ? '#8b5cf6' : 'var(--text-secondary)',
              fontWeight: page === t.key ? 600 : 400,
              fontSize: '14px',
              cursor: 'pointer',
              transition: 'all 0.15s',
              fontFamily: "'Inter Tight', sans-serif",
            }}
          >
            {t.icon} {t.label}
          </button>
        ))}
      </nav>

      <main style={{ maxWidth: '1400px', margin: '0 auto', padding: '24px' }}>
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

      <Toast
        message={toast.message}
        type={toast.type}
        visible={toast.visible}
        onClose={() => setToast(t => ({ ...t, visible: false }))}
      />
    </div>
  )
}
