// Nuxt UI generates its color CSS vars reactively off appConfig.ui.colors
// (see its own runtime colors plugin), so calling updateAppConfig() here is
// enough to re-theme the whole app live - no page reload needed. The only
// extra piece is persisting the choice ourselves (appConfig resets to its
// default on every load) and restoring it on next visit.
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
  'taupe'
] as const
export type PrimaryColor = (typeof PRIMARY_COLOR_OPTIONS)[number]

const STORAGE_KEY = 'lista-primary-color'

export function usePrimaryColor() {
  const appConfig = useAppConfig()

  const primaryColor = computed(() => (appConfig.ui?.colors?.primary as PrimaryColor) ?? 'sky')

  function setPrimaryColor(color: PrimaryColor) {
    updateAppConfig({ ui: { colors: { primary: color } } })
    if (!import.meta.client) return
    try {
      localStorage.setItem(STORAGE_KEY, color)
    } catch {
      // private browsing / storage disabled - the choice just won't persist
    }
  }

  function restorePrimaryColor() {
    if (!import.meta.client) return
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      if (stored && (PRIMARY_COLOR_OPTIONS as readonly string[]).includes(stored)) {
        updateAppConfig({ ui: { colors: { primary: stored } } })
      }
    } catch {
      // ignore
    }
  }

  return { primaryColor, setPrimaryColor, restorePrimaryColor }
}
