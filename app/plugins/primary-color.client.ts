// Syncs the persisted primary color into appConfig so the rest of the app
// (e.g. the Settings page's swatch picker) sees the right value reactively.
// The pre-paint flash itself is already handled by the blocking inline
// script in nuxt.config.ts (app.head.script) - this just catches up the
// Vue-side state afterward, it doesn't need to run before first paint.
export default defineNuxtPlugin(() => {
  const { restorePrimaryColor } = usePrimaryColor()
  restorePrimaryColor()
})
