/** Main card editor orchestrator with undo/redo and draft management */
import { useState, useCallback } from 'react'
import { useAccount, useWriteContract } from 'wagmi'
import { parseEther } from 'viem'
import { ROUTER_ADDRESS, ROUTER_ABI } from '../../lib/contracts'
import { CARD_PARTS, createDefaultCard } from './types'
import type { CardEditorData } from './types'
import PartSelector from './PartSelector'
import PartEditor from './PartEditor'
import CardPreview from './CardPreview'

interface CardEditorProps {
  onToast: (msg: string, type: 'success' | 'error' | 'info') => void
}

export default function CardEditor({ onToast }: CardEditorProps) {
  const { isConnected } = useAccount()
  const { writeContract, isPending } = useWriteContract()

  const [card, setCard] = useState<CardEditorData>(createDefaultCard)
  const [selectedPart, setSelectedPart] = useState('identity')
  const [mintStatus, setMintStatus] = useState<'idle' | 'success' | 'error'>('idle')

  const updateField = useCallback((key: string, value: string | number) => {
    setCard(prev => {
      const next = { ...prev }
      if (key.startsWith('stats.')) {
        const statKey = key.slice(6) as keyof typeof next.stats
        next.stats = { ...next.stats, [statKey]: value }
      } else {
        (next as Record<string, unknown>)[key] = value
      }
      return next
    })
  }, [])

  const updateFields = useCallback((updates: Record<string, string | number>) => {
    setCard(prev => {
      const next = { ...prev, stats: { ...prev.stats } }
      for (const [key, value] of Object.entries(updates)) {
        if (key.startsWith('stats.')) {
          const statKey = key.slice(6) as keyof typeof next.stats
          ;(next.stats as Record<string, number>)[statKey] = value as number
        } else {
          (next as Record<string, unknown>)[key] = value
        }
      }
      return next
    })
  }, [])

  const handleReset = () => {
    setCard(createDefaultCard())
    setMintStatus('idle')
  }

  const handleMint = () => {
    if (!card.name) {
      onToast('Please give your card a name', 'error')
      return
    }

    // Use card name as both name and symbol for simplicity
    const symbol = card.name.replace(/[^a-zA-Z]/g, '').toUpperCase().slice(0, 6) || 'CARD'
    // For now, use a placeholder tokenURI — in production this would be an IPFS upload
    const tokenURI = `data:application/json,${encodeURIComponent(JSON.stringify({
      name: card.name,
      description: card.flavorText || card.subtitle || '',
      image: card.imageData || '',
      attributes: [
        { trait_type: 'Type', value: card.type },
        { trait_type: 'Level', value: card.level },
        { trait_type: 'HP', value: card.stats.hp },
        { trait_type: 'Attack', value: card.stats.attack },
        { trait_type: 'Defense', value: card.stats.defense },
        { trait_type: 'Rarity', value: card.rarity },
      ],
    }))}`

    writeContract({
      address: ROUTER_ADDRESS,
      abi: ROUTER_ABI,
      functionName: 'createCard',
      args: [card.name, symbol, tokenURI],
      value: parseEther('0.05'),
    }, {
      onSuccess: () => {
        onToast(`Created ${card.name}!`, 'success')
        setMintStatus('success')
      },
      onError: (e) => {
        onToast(e.message.slice(0, 80), 'error')
        setMintStatus('error')
      },
    })
  }

  return (
    <div className="flex flex-col w-full" style={{ minHeight: 'calc(100vh - 200px)' }}>
      {/* Header */}
      <div className="flex items-center justify-between px-6 py-4 bg-white border-b border-gray-200 rounded-t-2xl">
        <div className="flex items-center gap-3">
          <span className="text-2xl">🃏</span>
          <h2 className="text-xl font-bold text-gray-900" style={{ fontFamily: "'Inter Tight', sans-serif" }}>
            Card Editor
          </h2>
        </div>

        <div className="flex items-center gap-2">
          <button
            className="px-4 py-2 bg-gray-100 hover:bg-gray-200 text-gray-600 rounded-xl text-sm font-medium cursor-pointer border-none transition-colors"
            onClick={handleReset}
          >
            Reset
          </button>
          <button
            className="px-5 py-2 text-white rounded-xl text-sm font-semibold cursor-pointer border-none transition-all disabled:opacity-50 disabled:cursor-not-allowed"
            style={{ background: isPending ? '#9CA3AF' : '#FF613D' }}
            onClick={handleMint}
            disabled={isPending || !isConnected}
          >
            {isPending ? '⏳ Minting...' : '🌊 Mint Card — 0.05 ETH'}
          </button>
        </div>
      </div>

      {/* Success/Error inline banner */}
      {mintStatus === 'success' && (
        <div className="flex items-center justify-between px-6 py-3 bg-green-50 border-b border-green-200 text-green-700 text-sm">
          <span>✅ Card minted successfully!</span>
          <button className="text-green-600 hover:text-green-800 cursor-pointer border-none bg-transparent text-sm" onClick={() => setMintStatus('idle')}>Dismiss</button>
        </div>
      )}
      {mintStatus === 'error' && (
        <div className="flex items-center justify-between px-6 py-3 bg-red-50 border-b border-red-200 text-red-700 text-sm">
          <span>❌ Minting failed. Check your wallet and try again.</span>
          <button className="text-red-600 hover:text-red-800 cursor-pointer border-none bg-transparent text-sm" onClick={() => setMintStatus('idle')}>Dismiss</button>
        </div>
      )}

      {/* Main editor layout */}
      <div className="flex flex-1 overflow-hidden bg-gray-50 rounded-b-2xl border border-t-0 border-gray-200">
        {/* Left: Part selector */}
        <div className="w-56 flex-shrink-0 bg-white border-r border-gray-200 hidden md:block">
          <PartSelector
            parts={CARD_PARTS}
            selectedPart={selectedPart}
            onSelectPart={setSelectedPart}
          />
        </div>

        {/* Center: Preview */}
        <div className="flex-1 flex flex-col items-center justify-center p-6 overflow-auto">
          {/* Mobile part selector */}
          <div className="flex gap-2 mb-4 md:hidden overflow-x-auto w-full pb-2">
            {Object.entries(CARD_PARTS).map(([key, part]) => (
              <button
                key={key}
                className={`flex-shrink-0 px-3 py-1.5 rounded-lg text-xs font-medium border transition-colors ${
                  selectedPart === key
                    ? 'bg-violet-100 text-violet-700 border-violet-200'
                    : 'bg-white text-gray-500 border-gray-200'
                }`}
                onClick={() => setSelectedPart(key)}
              >
                {part.icon} {part.label}
              </button>
            ))}
          </div>

          <CardPreview card={card} />

          {/* Mint fee display */}
          <div className="mt-4 px-5 py-3 bg-white rounded-xl border border-gray-200 flex items-center gap-4">
            <span className="text-sm text-gray-400">Mint Fee</span>
            <span className="text-lg font-bold text-violet-500 font-mono">0.05 ETH</span>
          </div>
        </div>

        {/* Right: Part editor */}
        <div className="w-80 flex-shrink-0 bg-white border-l border-gray-200 hidden lg:block">
          <PartEditor
            part={selectedPart}
            partSchema={CARD_PARTS[selectedPart]}
            card={card}
            onUpdateField={updateField}
            onUpdateFields={updateFields}
          />
        </div>
      </div>

      {/* Mobile part editor (below preview) */}
      <div className="lg:hidden mt-4 bg-white rounded-2xl border border-gray-200 overflow-hidden">
        <PartEditor
          part={selectedPart}
          partSchema={CARD_PARTS[selectedPart]}
          card={card}
          onUpdateField={updateField}
          onUpdateFields={updateFields}
        />
      </div>
    </div>
  )
}
