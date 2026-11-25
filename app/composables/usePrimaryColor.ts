// Nuxt UI generates its color CSS vars reactively off appConfig.ui.colors
// (see its own runtime colors plugin), so calling updateAppConfig() here is
// enough to re-theme the whole app live - no page reload needed.
//
// The choice is persisted twice, for two different jobs:
// - localStorage: read synchronously by the blocking inline script in
//   nuxt.config.ts (app.head.script) before first paint, and by
//   restorePrimaryColor() below - this is what avoids a flash back to the
//   default color, and it's also what a signed-out visitor falls back to.
// - users.primary_color: the account-level source of truth, so the choice
//   follows you to another browser/device instead of staying stuck to the
//   one it was picked in. syncPrimaryColorFromAccount() reconciles this in
//   after the fact, once the signed-in user is known - it doesn't block
//   first paint on a network round trip.
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

const STORAGE_KEY = 'lista-primary-color'

function isValidColor(value: unknown): value is PrimaryColor {
  return typeof value === 'string' && (PRIMARY_COLOR_OPTIONS as readonly string[]).includes(value)
}

export function usePrimaryColor() {
  const appConfig = useAppConfig()
  const supabase = useSupabaseClient()
  const user = useSupabaseUser()

  const primaryColor = computed(() => (appConfig.ui?.colors?.primary as PrimaryColor) ?? 'sky')

  function applyColor(color: PrimaryColor) {
    updateAppConfig({ ui: { colors: { primary: color } } })
    if (!import.meta.client) return
    try {
      localStorage.setItem(STORAGE_KEY, color)
    } catch {
      // private browsing / storage disabled - the choice just won't persist
    }
  }

  async function setPrimaryColor(color: PrimaryColor) {
    applyColor(color)
    if (!user.value) return
    await supabase.from('users').update({ primary_color: color }).eq('id', user.value.sub)
  }

  function restorePrimaryColor() {
    if (!import.meta.client) return
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      if (isValidColor(stored)) applyColor(stored)
    } catch {
      // ignore
    }
  }

  async function syncPrimaryColorFromAccount() {
    if (!import.meta.client || !user.value) return
    const { data } = await supabase.from('users').select('primary_color').eq('id', user.value.sub).single()
    if (data?.primary_color && isValidColor(data.primary_color)) {
      applyColor(data.primary_color)
    }
  }

  return { primaryColor, setPrimaryColor, restorePrimaryColor, syncPrimaryColorFromAccount }
}
