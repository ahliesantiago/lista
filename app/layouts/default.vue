<script setup lang="ts">
const supabase = useSupabaseClient()
const user = useSupabaseUser()

const { data: username } = await useAsyncData('current-username', async () => {
  if (!user.value) return null
  const { data } = await supabase.from('users').select('username').eq('id', user.value.id).single()
  return data?.username ?? null
})

async function signOut() {
  mobileMoreOpen.value = false
  await supabase.auth.signOut()
  await navigateTo('/login')
}

const userMenuItems = [[{ label: 'Settings', icon: 'i-lucide-settings', to: '/settings' }]]
const headerMenuItems = computed(() => [
  [
    {
      type: 'label' as const,
      label: username.value ?? user.value?.email ?? '',
      description: username.value ? user.value?.email : undefined,
    },
  ],
  [{ label: 'Settings', icon: 'i-lucide-settings', to: '/settings' }],
  [{ label: 'Sign out', icon: 'i-lucide-log-out', onSelect: signOut }],
])

const navLinks = [
  { to: '/lists', label: 'Lists', icon: 'i-lucide-list-checks' },
  { to: '/recipes', label: 'Recipes', icon: 'i-lucide-book-open' },
  { to: '/items', label: 'Items', icon: 'i-lucide-package' },
  { to: '/categories', label: 'Categories', icon: 'i-lucide-tags' },
  { to: '/units', label: 'Units', icon: 'i-lucide-ruler' },
  { to: '/household', label: 'Household', icon: 'i-lucide-home' },
]

const primaryMobileLinks = navLinks.filter((link) => ['/lists', '/recipes', '/items', '/household'].includes(link.to))
const moreLinks = navLinks.filter((link) => !primaryMobileLinks.includes(link))

const sidebarCollapsed = ref(true)
const mobileMoreOpen = ref(false)

const route = useRoute()
const pageTitles: Record<string, string> = {
  '/': 'Home',
  '/lists': 'Lists',
  '/recipes': 'Recipes',
  '/items': 'Items',
  '/categories': 'Categories',
  '/units': 'Units',
  '/household': 'Household',
  '/pantry': 'Pantry',
  '/home-inventory': 'Home Inventory',
  '/equipment': 'Equipment',
  '/appliances': 'Appliances',
  '/furniture': 'Furniture',
  '/rooms': 'Rooms',
  '/storage': 'Storage',
  '/recipe-categories': 'Recipe Categories',
  '/trash': 'Trash',
  '/settings': 'Settings',
  '/login': 'Log in',
  '/signup': 'Sign up',
}
const pageTitle = computed(() => {
  if (route.path === '/') return pageTitles['/']
  const match = Object.keys(pageTitles)
    .filter((path) => path !== '/' && route.path.startsWith(path))
    .sort((a, b) => b.length - a.length)[0]
  return match ? pageTitles[match] : 'Lista'
})
</script>

<template>
  <div class="flex h-dvh overflow-hidden">
    <aside
      v-if="user"
      class="hidden shrink-0 flex-col overflow-y-auto border-r border-default px-3 py-4 transition-[width] duration-200 sm:flex"
      :class="sidebarCollapsed ? 'sm:w-16' : 'sm:w-56'"
    >
      <div class="mb-2 flex items-center" :class="sidebarCollapsed ? 'justify-center' : 'justify-between'">
        <NuxtLink v-if="!sidebarCollapsed" to="/" class="text-lg font-semibold">Lista</NuxtLink>
        <UButton
          variant="ghost"
          size="sm"
          :icon="sidebarCollapsed ? 'i-lucide-panel-left-open' : 'i-lucide-panel-left-close'"
          :title="sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'"
          @click="sidebarCollapsed = !sidebarCollapsed"
        />
      </div>

      <nav class="flex flex-1 flex-col gap-1">
        <NuxtLink
          v-for="link in navLinks"
          :key="link.to"
          :to="link.to"
          :title="sidebarCollapsed ? link.label : undefined"
          class="flex items-center gap-2 rounded px-2 py-2 text-sm hover:bg-elevated"
          :class="sidebarCollapsed ? 'justify-center' : ''"
          active-class="bg-elevated text-primary"
        >
          <UIcon :name="link.icon" class="size-5 shrink-0" />
          <span v-if="!sidebarCollapsed">{{ link.label }}</span>
        </NuxtLink>
      </nav>
    </aside>

    <div class="flex min-h-0 flex-1 flex-col overflow-hidden">
      <header class="flex shrink-0 items-center justify-between border-b border-default px-4 py-3">
        <h1 class="font-semibold">{{ pageTitle }}</h1>
        <div v-if="user" class="flex items-center gap-2">
          <UDropdownMenu :items="headerMenuItems" class="hidden sm:block">
            <UButton variant="ghost" size="sm" icon="i-lucide-circle-user" />
          </UDropdownMenu>
          <UButton
            variant="ghost"
            size="sm"
            icon="i-lucide-more-horizontal"
            class="sm:hidden"
            @click="mobileMoreOpen = true"
          />
        </div>
      </header>

      <div class="flex min-h-0 flex-1 flex-col overflow-y-auto">
        <main class="flex-1 p-4" :class="user ? 'pb-20 sm:pb-4' : ''">
          <slot />
        </main>

        <nav
          v-if="user"
          class="fixed inset-x-0 bottom-0 z-50 flex items-center justify-around border-t border-default bg-default py-1 sm:hidden"
          style="padding-bottom: env(safe-area-inset-bottom)"
        >
          <NuxtLink
            v-for="link in primaryMobileLinks"
            :key="link.to"
            :to="link.to"
            class="flex flex-1 flex-col items-center gap-0.5 py-1.5 text-xs text-muted"
            active-class="text-primary"
          >
            <UIcon :name="link.icon" class="size-5" />
            {{ link.label }}
          </NuxtLink>
          <button
            type="button"
            class="flex flex-1 flex-col items-center gap-0.5 py-1.5 text-xs text-muted"
            @click="mobileMoreOpen = true"
          >
            <UIcon name="i-lucide-more-horizontal" class="size-5" />
            More
          </button>
        </nav>
      </div>
    </div>

    <USlideover v-model:open="mobileMoreOpen" title="More">
      <template #body>
        <nav class="flex flex-col gap-1">
          <NuxtLink
            v-for="link in moreLinks"
            :key="link.to"
            :to="link.to"
            class="flex items-center gap-2 rounded px-2 py-2 hover:bg-elevated"
            @click="mobileMoreOpen = false"
          >
            <UIcon :name="link.icon" class="size-5" />
            {{ link.label }}
          </NuxtLink>
          <NuxtLink
            to="/settings"
            class="flex items-center gap-2 rounded px-2 py-2 hover:bg-elevated"
            @click="mobileMoreOpen = false"
          >
            <UIcon name="i-lucide-settings" class="size-5" />
            Settings
          </NuxtLink>
        </nav>
        <div class="mt-4 border-t border-default pt-4">
          <p class="text-muted mb-2 text-sm">{{ username ?? user?.email }}</p>
          <UButton block variant="outline" @click="signOut">Sign out</UButton>
        </div>
      </template>
    </USlideover>
  </div>
</template>
