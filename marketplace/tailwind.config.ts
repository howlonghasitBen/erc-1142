import type { Config } from 'tailwindcss'

export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', 'sans-serif'],
        heading: ['Inter Tight', 'Inter', 'sans-serif'],
        mono: ['DM Mono', 'monospace'],
      },
      colors: {
        border: 'var(--border)',
        violet: {
          300: '#a78bfa',
          400: '#8b5cf6',
          500: '#7c3aed',
        },
      },
    },
  },
  plugins: [],
} satisfies Config
