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
          // Applies the stored primary color before first paint, the same
          // way @nuxtjs/color-mode avoids a light/dark flash - without
          // this, the page always paints the default (blue) first, then
          // visibly swaps once primary-color.client.ts runs after hydration.
          // The color list here is duplicated from usePrimaryColor.ts on
          // purpose: this has to be a plain string (it runs pre-hydration,
          // before any app code/imports exist), so keep the two in sync.
          innerHTML: `(function(){try{var c=localStorage.getItem('lista-primary-color');var valid=['red','orange','amber','yellow','lime','green','emerald','teal','cyan','sky','blue','indigo','violet','purple','fuchsia','pink','rose'];if(c&&valid.indexOf(c)!==-1){var shades=[50,100,200,300,400,500,600,700,800,900,950];var root=document.documentElement;for(var i=0;i<shades.length;i++){root.style.setProperty('--ui-color-primary-'+shades[i],'var(--color-'+c+'-'+shades[i]+')')}}}catch(e){}})()`,
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
