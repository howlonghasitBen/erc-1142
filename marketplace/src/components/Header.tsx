import { useAccount, useConnect, useDisconnect, useBalance } from 'wagmi'
import { shortenAddress, formatWaves } from '../lib/utils'
import { useReadContract } from 'wagmi'
import { WAVES_ABI, WAVES_ADDRESS } from '../lib/contracts'

export default function Header() {
  const { address, isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const { disconnect } = useDisconnect()
  const { data: ethBalance } = useBalance({ address })
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
      background: 'rgba(255, 255, 255, 0.85)',
      backdropFilter: 'blur(16px)',
      borderBottom: '1px solid var(--border)',
    }}>
      {/* Logo */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexShrink: 0 }}>
        <span style={{ fontSize: '24px' }}>🌊</span>
        <span className="gradient-text" style={{ fontSize: '20px', fontWeight: 700, letterSpacing: '-0.5px', fontFamily: "'Inter Tight', sans-serif" }}>
          WHIRLPOOL
        </span>
      </div>

      {/* Search */}
      <div style={{ flex: '0 1 400px', margin: '0 24px' }}>
        <div style={{ position: 'relative' }}>
          <svg style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', width: '16px', height: '16px', color: 'var(--text-muted)' }} fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
          <input
            type="text"
            placeholder="Search cards..."
            style={{ width: '100%', paddingLeft: '36px', height: '36px', fontSize: '14px', borderRadius: '10px' }}
          />
        </div>
      </div>

      {/* Wallet */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '12px', flexShrink: 0 }}>
        {isConnected && address ? (
          <>
            <div style={{ display: 'flex', alignItems: 'center', gap: '16px', fontSize: '13px', fontFamily: "'DM Mono', monospace" }}>
              <span style={{ color: 'var(--text-secondary)' }}>
                {ethBalance ? Number(ethBalance.formatted).toFixed(3) : '0'} ETH
              </span>
              <span style={{ color: '#8b5cf6' }}>
                {wavesBalance ? formatWaves(wavesBalance as bigint) : '0'} WAVES
              </span>
            </div>
            <button
              onClick={() => disconnect()}
              className="btn-secondary"
              style={{ fontSize: '13px', fontFamily: "'DM Mono', monospace", borderRadius: '10px' }}
            >
              {shortenAddress(address)}
            </button>
          </>
        ) : (
          <button
            onClick={() => connect({ connector: connectors[0] })}
            className="btn-primary"
            style={{ borderRadius: '12px' }}
          >
            Connect Wallet
          </button>
        )}
      </div>
    </header>
  )
}
