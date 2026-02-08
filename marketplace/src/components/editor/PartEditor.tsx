/** Field editor for selected card part — renders inputs, sliders, selects, image upload */
import { useState, useRef } from 'react'
import type { CardEditorData, PartSchema, FieldSchema } from './types'

interface PartEditorProps {
  part: string
  partSchema: PartSchema | undefined
  card: CardEditorData
  onUpdateField: (key: string, value: string | number) => void
  onUpdateFields: (updates: Record<string, string | number>) => void
}

export default function PartEditor({ part, partSchema, card, onUpdateField, onUpdateFields }: PartEditorProps) {
  const [imagePreview, setImagePreview] = useState<string | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  if (!partSchema) {
    return (
      <div className="flex items-center justify-center h-full text-gray-400 font-mono text-sm">
        Select a part to edit
      </div>
    )
  }

  const getFieldValue = (fieldKey: string): string | number | undefined => {
    if (fieldKey.includes('.')) {
      const parts = fieldKey.split('.')
      let value: unknown = card
      for (const p of parts) {
        value = (value as Record<string, unknown>)?.[p]
      }
      return value as string | number | undefined
    }
    if (part === 'stats') {
      return card.stats?.[fieldKey as keyof typeof card.stats]
    }
    return (card as unknown as Record<string, unknown>)[fieldKey] as string | number | undefined
  }

  const handleFieldChange = (fieldKey: string, value: string | number) => {
    if (part === 'stats') {
      onUpdateField(`stats.${fieldKey}`, value)
    } else {
      onUpdateField(fieldKey, value)
    }
  }

  const handleImageUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = (event) => {
      const data = event.target?.result as string
      setImagePreview(data)
      onUpdateField('imageData', data)
    }
    reader.readAsDataURL(file)
  }

  const handleRandomize = (fieldKey: string, fieldSchema: FieldSchema) => {
    let value: string | number | undefined
    if (fieldSchema.type === 'number') {
      const min = fieldSchema.min || 1
      const max = fieldSchema.max || 10
      value = Math.floor(Math.random() * (max - min + 1)) + min
    } else if (fieldSchema.type === 'select' && fieldSchema.options) {
      value = fieldSchema.options[Math.floor(Math.random() * fieldSchema.options.length)]
    }
    if (value !== undefined) handleFieldChange(fieldKey, value)
  }

  const renderField = (fieldKey: string, fieldSchema: FieldSchema) => {
    const value = getFieldValue(fieldKey)
    const id = `field-${part}-${fieldKey}`

    switch (fieldSchema.type) {
      case 'string':
        return (
          <div key={fieldKey} className="mb-5">
            <label htmlFor={id} className="flex items-center gap-2 mb-2 text-sm font-semibold text-gray-700">
              {fieldSchema.label}
              {fieldSchema.optional && <span className="text-xs px-1.5 py-0.5 bg-gray-100 text-gray-400 rounded">Optional</span>}
            </label>
            <input
              id={id}
              type="text"
              className="w-full px-3 py-2.5 bg-white border border-gray-200 rounded-none text-sm focus:border-amber-500 focus:ring-2 focus:ring-amber-100 outline-none"
              value={(value as string) || ''}
              placeholder={fieldSchema.placeholder}
              onChange={(e) => handleFieldChange(fieldKey, e.target.value)}
            />
          </div>
        )

      case 'number':
        return (
          <div key={fieldKey} className="mb-5">
            <label htmlFor={id} className="flex items-center gap-2 mb-2 text-sm font-semibold text-gray-700">
              {fieldSchema.label}
              <span className="ml-auto px-2.5 py-0.5 bg-amber-100 text-amber-700 rounded-none font-mono text-sm font-bold">
                {value || fieldSchema.min || 0}
              </span>
            </label>
            <div className="flex items-center gap-2">
              <input
                id={id}
                type="range"
                className="flex-1 h-2 bg-gray-200 rounded-none appearance-none cursor-pointer accent-amber-600"
                min={fieldSchema.min || 0}
                max={fieldSchema.max || 10}
                value={(value as number) || fieldSchema.min || 0}
                onChange={(e) => handleFieldChange(fieldKey, parseInt(e.target.value))}
              />
              <button
                className="w-8 h-8 flex items-center justify-center bg-gray-100 hover:bg-amber-100 rounded-none text-sm cursor-pointer border-none text-gray-500 hover:text-amber-700"
                onClick={() => handleRandomize(fieldKey, fieldSchema)}
                title="Randomize"
              >
                🎲
              </button>
            </div>
            <div className="flex justify-between mt-1 text-xs text-gray-400 font-mono">
              <span>{fieldSchema.min || 0}</span>
              <span>{fieldSchema.max || 10}</span>
            </div>
          </div>
        )

      case 'textarea':
        return (
          <div key={fieldKey} className="mb-5">
            <label htmlFor={id} className="flex items-center gap-2 mb-2 text-sm font-semibold text-gray-700">
              {fieldSchema.label}
              {fieldSchema.optional && <span className="text-xs px-1.5 py-0.5 bg-gray-100 text-gray-400 rounded">Optional</span>}
            </label>
            <textarea
              id={id}
              className="w-full px-3 py-2.5 bg-white border border-gray-200 rounded-none text-sm resize-y min-h-20 focus:border-amber-500 focus:ring-2 focus:ring-amber-100 outline-none"
              rows={fieldSchema.rows || 3}
              value={(value as string) || ''}
              placeholder={fieldSchema.placeholder}
              onChange={(e) => handleFieldChange(fieldKey, e.target.value)}
            />
          </div>
        )

      case 'select':
        return (
          <div key={fieldKey} className="mb-5">
            <label htmlFor={id} className="block mb-2 text-sm font-semibold text-gray-700">
              {fieldSchema.label}
            </label>
            <div className="flex gap-2">
              <select
                id={id}
                className="flex-1 px-3 py-2.5 bg-white border border-gray-200 rounded-none text-sm appearance-none cursor-pointer focus:border-amber-500 focus:ring-2 focus:ring-amber-100 outline-none"
                value={(value as string) || fieldSchema.options?.[0]}
                onChange={(e) => handleFieldChange(fieldKey, e.target.value)}
              >
                {fieldSchema.options?.map(option => (
                  <option key={option} value={option}>{option}</option>
                ))}
              </select>
              <button
                className="w-8 h-8 flex items-center justify-center bg-gray-100 hover:bg-amber-100 rounded-none text-sm cursor-pointer border-none"
                onClick={() => handleRandomize(fieldKey, fieldSchema)}
                title="Randomize"
              >
                🎲
              </button>
            </div>
          </div>
        )

      case 'image':
        return (
          <div key={fieldKey} className="mb-5">
            <label className="block mb-2 text-sm font-semibold text-gray-700">{fieldSchema.label}</label>
            <div className="overflow-hidden">
              {(imagePreview || card.imageData) ? (
                <div className="relative">
                  <img
                    src={imagePreview || card.imageData}
                    alt="Card"
                    className="w-full h-48 object-cover rounded-none border border-gray-200"
                  />
                  <button
                    className="absolute bottom-3 left-1/2 -translate-x-1/2 px-4 py-2 bg-white/90 backdrop-blur-sm rounded-none text-xs font-semibold text-gray-700 cursor-pointer border border-gray-200 hover:bg-white"
                    onClick={() => fileInputRef.current?.click()}
                  >
                    Change Image
                  </button>
                </div>
              ) : (
                <div
                  className="flex items-center justify-center h-48 bg-gray-50 border-2 border-dashed border-gray-200 rounded-none cursor-pointer hover:bg-amber-50 hover:border-amber-400 transition-colors"
                  onClick={() => fileInputRef.current?.click()}
                >
                  <div className="flex flex-col items-center gap-2 text-gray-400">
                    <span className="text-4xl">🖼️</span>
                    <span className="text-sm">Click to upload image</span>
                    <span className="text-xs text-gray-300">PNG, JPG up to 5MB</span>
                  </div>
                </div>
              )}
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                onChange={handleImageUpload}
                style={{ display: 'none' }}
              />
            </div>
          </div>
        )

      case 'palette':
        return (
          <div key={fieldKey} className="mb-5">
            <label className="block mb-2 text-sm font-semibold text-gray-700">{fieldSchema.label}</label>
            <div className="grid grid-cols-3 gap-3">
              {card.colors && Object.keys(card.colors).length > 0 ? (
                Object.entries(card.colors).map(([colorName, colorValue]) => (
                  <div key={colorName} className="flex flex-col items-center gap-1.5">
                    <div
                      className="w-12 h-12 rounded-none border border-gray-200"
                      style={{ backgroundColor: colorValue }}
                      title={colorName}
                    />
                    <span className="text-xs text-gray-400 capitalize font-mono">{colorName}</span>
                  </div>
                ))
              ) : (
                <div className="col-span-3 text-center py-6 text-gray-400 text-sm">
                  Upload an image to extract colors
                </div>
              )}
            </div>
          </div>
        )

      default:
        return null
    }
  }

  return (
    <div className="h-full flex flex-col">
      <div className="flex items-center gap-3 px-5 py-4 border-b border-gray-200 bg-gray-50">
        <span className="text-2xl">{partSchema.icon}</span>
        <h3 className="text-base font-bold text-gray-900" style={{ fontFamily: "'Inter Tight', sans-serif" }}>
          {partSchema.label}
        </h3>
      </div>

      <div className="flex-1 p-5 overflow-y-auto">
        {Object.entries(partSchema.fields).map(([key, schema]) => renderField(key, schema))}
      </div>

      {part === 'stats' && (
        <div className="p-5 border-t border-gray-200 bg-gray-50">
          <button
            className="w-full py-3 bg-amber-100 hover:bg-amber-200 text-amber-800 rounded-none text-sm font-semibold cursor-pointer border-none transition-colors"
            onClick={() => {
              onUpdateFields({
                'stats.hp': Math.floor(Math.random() * 15) + 5,
                'stats.attack': Math.floor(Math.random() * 12) + 3,
                'stats.defense': Math.floor(Math.random() * 12) + 3,
                'stats.mana': Math.floor(Math.random() * 8) + 2,
                'stats.crit': Math.floor(Math.random() * 20) + 1,
              })
            }}
          >
            🎲 Randomize All Stats
          </button>
        </div>
      )}
    </div>
  )
}
