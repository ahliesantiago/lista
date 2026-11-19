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
      theme_color: '#0f766e',
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
