/** Vertical sidebar for selecting which card part to edit */
import type { PartSchema } from './types'

interface PartSelectorProps {
  parts: Record<string, PartSchema>
  selectedPart: string
  onSelectPart: (key: string) => void
}

export default function PartSelector({ parts, selectedPart, onSelectPart }: PartSelectorProps) {
  return (
    <div className="flex flex-col h-full">
      <div className="px-5 py-4 border-b border-gray-200 bg-gray-50">
        <h3 className="text-xs uppercase tracking-wider text-gray-400 font-semibold font-mono">
          Card Parts
        </h3>
      </div>

      <div className="flex-1 p-2 overflow-y-auto">
        {Object.entries(parts).map(([key, part]) => (
          <button
            key={key}
            className={`flex items-center gap-3 w-full px-4 py-3 mb-0 rounded-none text-left transition-colors ${
              selectedPart === key
                ? 'bg-amber-50 text-amber-800 border-l-4 border-amber-500 border-y-0 border-r-0'
                : 'bg-white text-gray-700 border-l-4 border-transparent border-y-0 border-r-0 hover:bg-gray-50'
            }`}
            onClick={() => onSelectPart(key)}
          >
            <span className="text-lg">{part.icon}</span>
            <span className="flex-1 text-sm font-semibold">{part.label}</span>
            <span className="text-gray-400 text-sm">›</span>
          </button>
        ))}
      </div>

      <div className="p-4 border-t border-gray-200 bg-gray-50">
        <p className="text-xs text-gray-400 text-center font-mono">
          Click a part to edit
        </p>
      </div>
    </div>
  )
}
