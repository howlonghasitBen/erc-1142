/** Create page — card editor with part selector, live preview, and field editor */
import { useState } from 'react'
import { CARD_PARTS, createDefaultCard } from './editor/types'
import type { CardEditorData } from './editor/types'
import PartSelector from './editor/PartSelector'
import PartEditor from './editor/PartEditor'
import CardPreview from './editor/CardPreview'

interface MintCardProps {
  onToast?: (msg: string, type: 'success' | 'error' | 'info') => void
}

export default function MintCard({ onToast }: MintCardProps) {
  const [card, setCard] = useState<CardEditorData>(createDefaultCard())
  const [selectedPart, setSelectedPart] = useState<string>('identity')

  const updateField = (key: string, value: unknown) => {
    setCard(prev => {
      if (key.startsWith('stats.')) {
        const statKey = key.split('.')[1]
        return { ...prev, stats: { ...prev.stats, [statKey]: value } }
      }
      return { ...prev, [key]: value }
    })
  }

  const updateFields = (updates: Record<string, string | number>) => {
    setCard(prev => {
      const next = { ...prev, stats: { ...prev.stats } }
      for (const [key, value] of Object.entries(updates)) {
        if (key.startsWith('stats.')) {
          const statKey = key.split('.')[1]
          ;(next.stats as Record<string, unknown>)[statKey] = value
        } else {
          ;(next as Record<string, unknown>)[key] = value
        }
      }
      return next
    })
  }

  return (
    <div className="w-full px-4 sm:px-6 py-8">
      <h1 className="text-2xl font-bold text-gray-900 mb-2" style={{ fontFamily: 'Inter Tight, sans-serif' }}>
        Create Card
      </h1>
      <p className="text-sm text-gray-500 mb-8">
        Design your Whirlpool card with the editor below.
      </p>

      {/* Editor layout — CSS Grid for true center preview */}
      <div className="flex flex-col lg:flex-row gap-6 items-start w-full justify-evenly">
        {/* Part selector */}
        <div className="w-full lg:w-[300px] lg:shrink-0">
          <div className="bg-white border border-gray-200 rounded-none overflow-hidden shadow-sm">
            <PartSelector
              parts={CARD_PARTS}
              selectedPart={selectedPart}
              onSelectPart={setSelectedPart}
            />
          </div>
        </div>

        {/* Preview — true center column */}
        <div className="flex-1 flex justify-center items-start">
          <CardPreview card={card} />
        </div>

        {/* Part editor */}
        <div className="w-full lg:w-[320px] lg:shrink-0">
          <div className="bg-white border border-gray-200 rounded-none overflow-hidden shadow-sm">
            <PartEditor
              part={selectedPart}
              partSchema={CARD_PARTS[selectedPart]}
              card={card}
              onUpdateField={updateField}
              onUpdateFields={updateFields}
            />
          </div>

          {/* Mint Coming Soon */}
          <div className="mt-6 p-5 rounded-2xl bg-amber-50 border border-amber-200 text-center">
            <p className="text-lg font-bold text-amber-800" style={{ fontFamily: 'Inter Tight, sans-serif' }}>
              🌊 Minting Coming Soon
            </p>
            <p className="text-sm text-amber-600 mt-2">
              On-chain card minting is under development. Design your card now — you'll be able to mint it when we launch.
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}
