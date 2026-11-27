import tailwindColors from 'tailwindcss/colors'
import { PRIMARY_COLOR_OPTIONS, PRIMARY_COLOR_SHADES } from './shared/primaryColors'

// Applies the stored primary color before first paint, the same way
// @nuxtjs/color-mode avoids a light/dark flash - without this, the page
// always paints the default first, then visibly swaps once
// primary-color.client.ts runs after hydration.
//
// The color list/shades are imported from shared/primaryColors.ts (not
// duplicated here) so this can never drift out of sync with the app's own
// list again. Each shade gets a real color value baked in as a fallback,
// mirroring Nuxt UI's own colors plugin - without it, var(--color-X-Y) can
// resolve to nothing if that CSS variable isn't actually defined, which is
// exactly what caused colorless buttons before this fallback existed.
function buildPrimaryColorInitScript(): string {
  const fallbacks: Record<string, Partial<Record<number, string>>> = {}
  for (const color of PRIMARY_COLOR_OPTIONS) {
    const palette = (tailwindColors as Record<string, Record<number, string> | undefined>)[color]
    if (palette) fallbacks[color] = palette
  }
  return `(function(){try{
var c=localStorage.getItem('lista-primary-color');
var valid=${JSON.stringify(PRIMARY_COLOR_OPTIONS)};
var fallbacks=${JSON.stringify(fallbacks)};
if(c&&valid.indexOf(c)!==-1){
var shades=${JSON.stringify(PRIMARY_COLOR_SHADES)};
var root=document.documentElement;
var palette=fallbacks[c]||{};
for(var i=0;i<shades.length;i++){
var shade=shades[i];
var fallback=palette[shade];
root.style.setProperty('--ui-color-primary-'+shade, fallback?('var(--color-'+c+'-'+shade+', '+fallback+')'):('var(--color-'+c+'-'+shade+')'));
}
}
}catch(e){}})()`
}

// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  modules: ['@nuxtjs/supabase', '@nuxt/ui', '@vite-pwa/nuxt'],
  css: ['@/assets/css/main.css'],
  compatibilityDate: '2025-07-15',
  devtools: { enabled: true },
  app: {
    head: {
      link: [
        { rel: 'icon', type: 'image/png', sizes: '192x192', href: '/icon-192.png' },
        { rel: 'apple-touch-icon', sizes: '192x192', href: '/icon-192.png' },
      ],
      script: [
        {
          key: 'primary-color-init',
          innerHTML: buildPrimaryColorInitScript(),
        },
      ],
    },
  },
  nitro: {
    preset: 'cloudflare-pages',
  },
  supabase: {
    redirectOptions: {
      login: '/login',
      callback: '/confirm',
      exclude: ['/signup', '/forgot-password', '/reset-password'],
    },
  },
  pwa: {
    registerType: 'autoUpdate',
    manifest: {
      name: 'Lista',
      short_name: 'Lista',
      description: 'Personal household groceries, pantry, and recipe planner.',
      theme_color: '#0ea5e9',
      background_color: '#ffffff',
      icons: [
        { src: 'icon-192.png', sizes: '192x192', type: 'image/png' },
        { src: 'icon-512.png', sizes: '512x512', type: 'image/png' },
      ],
    },
    generateSW: {
      navigateFallback: '/',
      globPatterns: ['**/*.{js,css,html,ico,png,svg}'],
    },
  },
})
