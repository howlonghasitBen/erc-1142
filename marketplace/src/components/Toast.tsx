import { motion, AnimatePresence } from 'framer-motion'
import { useEffect } from 'react'

interface ToastProps {
  message: string
  type?: 'success' | 'error' | 'info'
  visible: boolean
  onClose: () => void
}

export default function Toast({ message, type = 'info', visible, onClose }: ToastProps) {
  useEffect(() => {
    if (visible) {
      const t = setTimeout(onClose, 4000)
      return () => clearTimeout(t)
    }
  }, [visible, onClose])

  const colors = {
    success: { bg: 'rgba(5, 223, 114, 0.1)', border: '#22C55E' },
    error: { bg: 'rgba(239, 68, 68, 0.1)', border: '#ef4444' },
    info: { bg: 'rgba(139, 92, 246, 0.1)', border: '#8b5cf6' },
  }

  return (
    <AnimatePresence>
      {visible && (
        <motion.div
          initial={{ opacity: 0, y: 50 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: 50 }}
          style={{
            position: 'fixed',
            bottom: '24px',
            right: '24px',
            zIndex: 100,
            padding: '12px 20px',
            borderRadius: '12px',
            background: colors[type].bg,
            border: `1px solid ${colors[type].border}`,
            backdropFilter: 'blur(12px)',
            fontSize: '14px',
            maxWidth: '360px',
            cursor: 'pointer',
            color: 'var(--text-primary)',
          }}
          onClick={onClose}
        >
          {message}
        </motion.div>
      )}
    </AnimatePresence>
  )
}
