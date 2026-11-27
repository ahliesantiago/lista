import tailwindColors from 'tailwindcss/colors'
import { PRIMARY_COLOR_OPTIONS, PRIMARY_COLOR_SHADES, type PrimaryColor } from '~~/shared/primaryColors'

export { PRIMARY_COLOR_OPTIONS }
export type { PrimaryColor }

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
const STORAGE_KEY = 'lista-primary-color'

function isValidColor(value: unknown): value is PrimaryColor {
  return typeof value === 'string' && (PRIMARY_COLOR_OPTIONS as readonly string[]).includes(value)
}

// Mirrors the inline boot script's logic, with the same fallback-value
// safety net Nuxt UI's own colors plugin relies on - without a real color
// baked in as the fallback, var(--color-X-Y) can resolve to nothing at all
// if that CSS variable isn't actually defined (e.g. for a color Tailwind's
// own generated CSS doesn't happen to include), leaving buttons colorless.
// Setting these as inline styles on <html> on every call (not just at boot)
// also means a live color change in Settings can't get masked by whatever
// the boot script already applied earlier in this same page session.
function applyInlineStyleOverride(color: PrimaryColor) {
  if (typeof document === 'undefined') return
  const palette = (tailwindColors as Record<string, Record<number, string> | undefined>)[color]
  const root = document.documentElement
  for (const shade of PRIMARY_COLOR_SHADES) {
    const fallback = palette?.[shade]
    root.style.setProperty(
      `--ui-color-primary-${shade}`,
      fallback ? `var(--color-${color}-${shade}, ${fallback})` : `var(--color-${color}-${shade})`,
    )
  }
}

export function usePrimaryColor() {
  const appConfig = useAppConfig()
  const supabase = useSupabaseClient()
  const user = useSupabaseUser()

  const primaryColor = computed(() => (appConfig.ui?.colors?.primary as PrimaryColor) ?? 'sky')

  function applyColor(color: PrimaryColor) {
    updateAppConfig({ ui: { colors: { primary: color } } })
    if (!import.meta.client) return
    applyInlineStyleOverride(color)
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
