/** Card data shape for the editor */
export interface CardEditorData {
  name: string
  subtitle: string
  type: string
  level: number
  imageData: string
  moveName: string
  flavorText: string
  artist: string
  rarity: string
  stats: {
    hp: number
    attack: number
    defense: number
    mana: number
    crit: number
  }
  manaCost: ManaCost[]
  colors: Record<string, string>
  theme: CardTheme
}

export interface ManaCost {
  type: string
  value: number
  color: string
  textColor: string
}

export interface CardTheme {
  background?: string
  header?: { background?: string; color?: string; textShadow?: string; boxShadow?: string }
  imageArea?: { background?: string; border?: string; boxShadow?: string }
  typeSection?: { background?: string; color?: string; textShadow?: string; boxShadow?: string }
  stat?: { background?: string; color?: string; boxShadow?: string; border?: string }
  flavorText?: { background?: string; color?: string; border?: string }
  bottomSection?: { background?: string }
  rarity?: { background?: string; color?: string; border?: string; boxShadow?: string }
}

export interface FieldSchema {
  label: string
  type: 'string' | 'number' | 'textarea' | 'select' | 'image' | 'palette'
  placeholder?: string
  optional?: boolean
  min?: number
  max?: number
  rows?: number
  options?: string[]
}

export interface PartSchema {
  label: string
  icon: string
  fields: Record<string, FieldSchema>
}

/** Card parts schema — defines the editor UI structure */
export const CARD_PARTS: Record<string, PartSchema> = {
  identity: {
    label: 'Identity',
    icon: '🏷️',
    fields: {
      name: { label: 'Card Name', type: 'string', placeholder: 'e.g. Sunset Wave' },
      subtitle: { label: 'Subtitle', type: 'string', placeholder: 'e.g. Ocean Guardian', optional: true },
      type: {
        label: 'Type',
        type: 'select',
        options: ['Creature', 'Spell', 'Artifact', 'Enchantment', 'Land', 'Hero', 'Token'],
      },
      level: { label: 'Level', type: 'number', min: 1, max: 20 },
    },
  },
  artwork: {
    label: 'Artwork',
    icon: '🖼️',
    fields: {
      imageData: { label: 'Card Image', type: 'image' },
      colors: { label: 'Color Palette', type: 'palette' },
    },
  },
  stats: {
    label: 'Stats',
    icon: '⚔️',
    fields: {
      hp: { label: 'HP', type: 'number', min: 1, max: 20 },
      attack: { label: 'Attack', type: 'number', min: 0, max: 15 },
      defense: { label: 'Defense', type: 'number', min: 0, max: 15 },
      mana: { label: 'Mana', type: 'number', min: 0, max: 10 },
      crit: { label: 'Crit %', type: 'number', min: 0, max: 25 },
    },
  },
  flavor: {
    label: 'Flavor',
    icon: '📜',
    fields: {
      moveName: { label: 'Move Name', type: 'string', placeholder: 'e.g. Tidal Crash', optional: true },
      flavorText: { label: 'Flavor Text', type: 'textarea', placeholder: 'Card lore or description...', rows: 4 },
      artist: { label: 'Artist', type: 'string', placeholder: '◆Waves TCG◆', optional: true },
      rarity: {
        label: 'Rarity',
        type: 'select',
        options: ['★1/1★', '★Common★', '★Uncommon★', '★Rare★', '★Epic★', '★Legendary★'],
      },
    },
  },
}

export function createDefaultCard(): CardEditorData {
  return {
    name: '',
    subtitle: '',
    type: 'Creature',
    level: 1,
    imageData: '',
    moveName: '',
    flavorText: '',
    artist: '◆Waves TCG◆',
    rarity: '★1/1★',
    stats: { hp: 10, attack: 5, defense: 5, mana: 3, crit: 5 },
    manaCost: [],
    colors: {},
    theme: {},
  }
}
