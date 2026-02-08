/**
 * @module Toast
 * @description Animated notification toast component for transaction feedback.
 *
 * Displays a color-coded notification in the bottom-right corner of the screen.
 * Auto-dismisses after 4 seconds, or can be dismissed by clicking.
 *
 * ## Color Coding
 * - **success** (green) — Transaction confirmed, action completed
 * - **error** (red) — Transaction reverted, validation failed
 * - **info** (cyan) — Informational messages
 *
 * ## Animation
 * Uses Framer Motion for enter/exit animations:
 * - Enter: slide up from below (y: 50 → 0) with fade in
 * - Exit: slide down with fade out
 *
 * ## Usage
 * Controlled by the parent App component's toast state.
 * Child components trigger toasts via `onToast(message, type)` callback.
 */

import { motion, AnimatePresence } from 'framer-motion'
import { useEffect } from 'react'

/**
 * Props for the Toast component.
 * @property message - Text to display in the toast
 * @property type - Color theme: 'success' (green), 'error' (red), or 'info' (cyan)
 * @property visible - Whether the toast is currently shown
 * @property onClose - Callback to dismiss the toast (called on click or after timeout)
 */
interface ToastProps {
  message: string
  type?: 'success' | 'error' | 'info'
  visible: boolean
  onClose: () => void
}

export default function Toast({ message, type = 'info', visible, onClose }: ToastProps) {
  /**
   * Auto-dismiss timer: hides the toast after 4 seconds.
   * Resets if visibility changes (e.g., new toast replaces old one).
   */
  useEffect(() => {
    if (visible) {
      const t = setTimeout(onClose, 4000)
      return () => clearTimeout(t)
    }
  }, [visible, onClose])

  /** Background and border colors for each toast type. */
  const colors = {
    success: { bg: 'rgba(16, 185, 129, 0.15)', border: '#10b981' },
    error: { bg: 'rgba(239, 68, 68, 0.15)', border: '#ef4444' },
    info: { bg: 'rgba(8, 145, 178, 0.15)', border: '#0891b2' },
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
            borderRadius: '10px',
            background: colors[type].bg,
            border: `1px solid ${colors[type].border}`,
            backdropFilter: 'blur(12px)',
            fontSize: '14px',
            maxWidth: '360px',
            cursor: 'pointer',
          }}
          onClick={onClose}
        >
          {message}
        </motion.div>
      )}
    </AnimatePresence>
  )
}
