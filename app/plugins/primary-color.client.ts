// Syncs the persisted primary color into appConfig so the rest of the app
// (e.g. the Settings page's swatch picker) sees the right value reactively.
// The pre-paint flash itself is already handled by the blocking inline
// script in nuxt.config.ts (app.head.script) - this just catches up the
// Vue-side state afterward, it doesn't need to run before first paint.
export default defineNuxtPlugin(() => {
  const { restorePrimaryColor, syncPrimaryColorFromAccount } = usePrimaryColor()
  restorePrimaryColor()

  // the signed-in user may not be known yet the instant this plugin runs
  // (session restore is async) - watch rather than check once, so the
  // account's stored color still gets picked up once it resolves
  const user = useSupabaseUser()
  watch(user, (value) => {
    if (value) syncPrimaryColorFromAccount()
  }, { immediate: true })
})
