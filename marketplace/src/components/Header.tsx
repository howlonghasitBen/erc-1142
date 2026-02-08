/**
 * @module Header
 * @description Fixed top navigation bar for the Whirlpool Marketplace.
 *
 * Displays three sections (left to right):
 * 1. **Logo** — "🌊 WHIRLPOOL" with gradient text
 * 2. **Search** — Input field for card search (UI-only, not yet wired)
 * 3. **Wallet** — Connect/disconnect button + ETH and WAVES balances
 *
 * ## Wallet Integration
 * Uses wagmi hooks to:
 * - `useAccount` — detect connected address
 * - `useConnect` / `useDisconnect` — wallet connection lifecycle
 * - `useBalance` — fetch native ETH balance
 * - `useReadContract` — read WAVES ERC-20 balance from the WAVES contract
 *
 * The WAVES balance read is conditional (`enabled: !!address`) to avoid
 * unnecessary RPC calls when no wallet is connected.
 *
 * ## Styling
 * - Glassmorphism effect: semi-transparent background + backdrop-filter blur
 * - Fixed position at top with z-index 50 (above nav tabs at z-40)
 * - JetBrains Mono for numeric values (balances, addresses)
 */

import { useAccount, useConnect, useDisconnect, useBalance } from 'wagmi'
import { shortenAddress, formatWaves } from '../lib/utils'
import { useReadContract } from 'wagmi'
import { WAVES_ABI, WAVES_ADDRESS } from '../lib/contracts'

export default function Header() {
  const { address, isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const { disconnect } = useDisconnect()

  /** Native ETH balance for the connected address. */
  const { data: ethBalance } = useBalance({ address })

  /**
   * WAVES token balance — reads balanceOf(address) from the WAVES ERC-20.
   * Only enabled when a wallet is connected to avoid reverts on zero-address.
   */
  const { data: wavesBalance } = useReadContract({
    address: WAVES_ADDRESS,
    abi: WAVES_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  })

  return (
    <header style={{
      position: 'fixed',
      top: 0,
      left: 0,
      right: 0,
      zIndex: 50,
      display: 'flex',
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      height: '64px',
      padding: '0 24px',
      background: 'rgba(15, 13, 10, 0.85)',
      backdropFilter: 'blur(16px)',
      borderBottom: '1px solid var(--border)',
    }}>
      {/* Logo — gradient text from sunset-orange to ocean-cyan */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexShrink: 0 }}>
        <span style={{ fontSize: '24px' }}>🌊</span>
        <span className="gradient-text" style={{ fontSize: '20px', fontWeight: 700, letterSpacing: '-0.5px' }}>
          WHIRLPOOL
        </span>
      </div>

      {/* Search bar — placeholder UI, not yet connected to filtering logic */}
      <div style={{ flex: '0 1 400px', margin: '0 24px' }}>
        <div style={{ position: 'relative' }}>
          <svg style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', width: '16px', height: '16px', color: 'var(--text-muted)' }} fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
          <input
            type="text"
            placeholder="Search cards..."
            style={{ width: '100%', paddingLeft: '36px', height: '36px', fontSize: '14px' }}
          />
        </div>
      </div>

      {/* Wallet section — balances + connect/disconnect button */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '12px', flexShrink: 0 }}>
        {isConnected && address ? (
          <>
            {/* Balance display — ETH in secondary color, WAVES in ocean-cyan */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '16px', fontSize: '13px', fontFamily: "'JetBrains Mono', monospace" }}>
              <span style={{ color: 'var(--text-secondary)' }}>
                {ethBalance ? Number(ethBalance.formatted).toFixed(3) : '0'} ETH
              </span>
              <span style={{ color: 'var(--ocean-cyan)' }}>
                {wavesBalance ? formatWaves(wavesBalance as bigint) : '0'} WAVES
              </span>
            </div>
            {/* Disconnect button shows shortened address (e.g. 0xf39F...2266) */}
            <button
              onClick={() => disconnect()}
              className="btn-secondary"
              style={{ fontSize: '13px', fontFamily: "'JetBrains Mono', monospace" }}
            >
              {shortenAddress(address)}
            </button>
          </>
        ) : (
          /* Connect button — uses first available connector (typically injected/MetaMask) */
          <button
            onClick={() => connect({ connector: connectors[0] })}
            className="btn-primary"
          >
            Connect Wallet
          </button>
        )}
      </div>
    </header>
  )
}
