// Single source of truth for selectable primary-color names, shared
// between app runtime code (app/composables/usePrimaryColor.ts) and
// nuxt.config.ts's build-time generation of the anti-flash boot script -
// those two previously kept their own separate copies and drifted apart,
// which is exactly how this list ended up missing colors on one side.
export const PRIMARY_COLOR_OPTIONS = [
  'red',
  'mauve',
  'orange',
  'amber',
  'yellow',
  'lime',
  'green',
  'emerald',
  'teal',
  'mist',
  'cyan',
  'sky',
  'blue',
  'slate',
  'indigo',
  'violet',
  'purple',
  'fuchsia',
  'pink',
  'rose',
  'zinc',
  'taupe',
] as const
export type PrimaryColor = (typeof PRIMARY_COLOR_OPTIONS)[number]

export const PRIMARY_COLOR_SHADES = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950] as const
