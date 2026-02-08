/**
 * @module MintCard
 * @description Card creation form for minting new Whirlpool cards.
 *
 * ## What Happens When You Create a Card
 *
 * Calls `WhirlpoolRouter.createCard(name, symbol, tokenURI)` with 0.05 ETH:
 *
 * 1. **CardToken deployed** — 10,000,000 ERC-20 tokens minted for this card
 * 2. **WAVES minted** — 2,000 WAVES created:
 *    - 500 WAVES (25%) → AMM pool as initial liquidity
 *    - 1,500 WAVES (75%) → minter (you)
 * 3. **Token distribution**:
 *    - 7,500,000 (75%) → AMM pool (tradeable supply)
 *    - 2,000,000 (20%) → auto-staked for you (gives you initial ownership)
 *    - 500,000 (5%) → protocol treasury
 * 4. **BidNFT minted** — dynamic ownership NFT linked to LP staking
 * 5. **You become owner** — auto-staked tokens give you majority LP shares
 *
 * ## Form Fields
 * - **Name** — Display name for the card (e.g. "Sunset Wave")
 * - **Symbol** — Token ticker symbol (e.g. "SWAVE")
 * - **Token URI** — IPFS URI for card metadata/image (optional)
 *
 * ## Contract Interaction
 * - Contract: `WhirlpoolRouter`
 * - Function: `createCard(string name, string symbol, string tokenURI)`
 * - Value: `0.05 ETH` (MINT_FEE)
 * - Returns: `cardId` (the new card's ID)
 *
 * @see WhirlpoolRouter.sol for the full creation flow
 */

import { useState } from 'react'
import { motion } from 'framer-motion'
import { useWriteContract } from 'wagmi'
import { parseEther } from 'viem'
import { ROUTER_ADDRESS, ROUTER_ABI } from '../lib/contracts'

/** @property onToast - Callback to trigger global toast notifications */
interface MintCardProps {
  onToast: (msg: string, type: 'success' | 'error' | 'info') => void
}

export default function MintCard({ onToast }: MintCardProps) {
  /** Card display name input. */
  const [name, setName] = useState('')

  /** Card token symbol input. */
  const [symbol, setSymbol] = useState('')

  /** IPFS token URI for card metadata. */
  const [tokenURI, setTokenURI] = useState('')

  const { writeContract, isPending } = useWriteContract()

  /**
   * Submit card creation transaction.
   *
   * Validates that name and symbol are provided, then calls
   * WhirlpoolRouter.createCard with 0.05 ETH mint fee.
   * On success, clears the form and shows a success toast.
   */
  const handleCreate = () => {
    if (!name || !symbol) { onToast('Name and symbol required', 'error'); return }
    writeContract({
      address: ROUTER_ADDRESS,
      abi: ROUTER_ABI,
      functionName: 'createCard',
      args: [name, symbol, tokenURI],
      value: parseEther('0.05'),
    }, {
      onSuccess: () => {
        onToast(`Created ${name}!`, 'success')
        setName(''); setSymbol(''); setTokenURI('')
      },
      onError: (e) => onToast(e.message.slice(0, 80), 'error'),
    })
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      style={{
        maxWidth: '500px',
        margin: '0 auto',
        background: 'var(--bg-card)',
        border: '1px solid var(--border)',
        borderRadius: '16px',
        padding: '32px',
      }}
    >
      <h2 style={{ fontSize: '24px', fontWeight: 700, marginBottom: '8px' }}>
        🃏 Create Card
      </h2>
      <p style={{ fontSize: '14px', color: 'var(--text-muted)', marginBottom: '24px' }}>
        Mint a new card into the Whirlpool
      </p>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
        {/* Card name input */}
        <div>
          <label style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-secondary)', display: 'block', marginBottom: '6px' }}>Name</label>
          <input value={name} onChange={e => setName(e.target.value)} placeholder="e.g. Sunset Wave" style={{ width: '100%' }} />
        </div>

        {/* Token symbol input */}
        <div>
          <label style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-secondary)', display: 'block', marginBottom: '6px' }}>Symbol</label>
          <input value={symbol} onChange={e => setSymbol(e.target.value)} placeholder="e.g. SWAVE" style={{ width: '100%' }} />
        </div>

        {/* Token URI input (IPFS metadata link) */}
        <div>
          <label style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-secondary)', display: 'block', marginBottom: '6px' }}>Token URI</label>
          <input value={tokenURI} onChange={e => setTokenURI(e.target.value)} placeholder="ipfs://..." style={{ width: '100%' }} />
        </div>

        {/* Mint fee display — hardcoded at 0.05 ETH per the contract */}
        <div style={{
          background: 'var(--bg-secondary)',
          borderRadius: '10px',
          padding: '14px',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
        }}>
          <span style={{ fontSize: '13px', color: 'var(--text-muted)' }}>Mint Fee</span>
          <span style={{ fontSize: '16px', fontWeight: 600, color: 'var(--ocean-cyan)', fontFamily: "'JetBrains Mono', monospace" }}>
            0.05 ETH
          </span>
        </div>

        {/* Submit button — disabled while transaction is pending */}
        <button
          onClick={handleCreate}
          disabled={isPending}
          className="btn-primary"
          style={{ width: '100%', padding: '12px', fontSize: '16px', marginTop: '8px' }}
        >
          {isPending ? '⏳ Creating...' : '🌊 Create Card'}
        </button>
      </div>
    </motion.div>
  )
}
