<script setup lang="ts">
const supabase = useSupabaseClient()
const user = useSupabaseUser()

const { data: username } = await useAsyncData(
  'current-username',
  async () => {
    if (!user.value) return null
    const { data } = await supabase.from('users').select('username').eq('id', user.value.sub).single()
    return data?.username ?? null
  },
  { watch: [user] },
)

async function signOut() {
  mobileMoreOpen.value = false
  await supabase.auth.signOut()
  await navigateTo('/login')
}

const headerMenuItems = computed(() => [
  [
    {
      type: 'label' as const,
      label: username.value || 'Account',
      description: user.value?.email || undefined,
    },
  ],
  [{ label: 'Settings', icon: 'i-lucide-settings', to: '/settings' }],
  [{ label: 'Sign out', icon: 'i-lucide-log-out', onSelect: signOut }],
])

const navLinks = [
  { to: '/lists', label: 'Lists', icon: 'i-lucide-clipboard-list' },
  { to: '/recipes', label: 'Recipes', icon: 'i-lucide-cooking-pot' },
  { to: '/items', label: 'Items', icon: 'i-lucide-folder-cog' },
  { to: '/categories', label: 'Categories', icon: 'i-lucide-folder-tree' },
  { to: '/tags', label: 'Tags', icon: 'i-lucide-tags' },
  { to: '/units', label: 'Units', icon: 'i-lucide-ruler' },
  {
    to: '/household',
    label: 'Household',
    icon: 'i-lucide-house-plus',
    children: [
      { to: '/pantry', label: 'Pantry' },
      { to: '/home-inventory', label: 'Home Inventory' },
      { to: '/equipment', label: 'Equipment' },
      { to: '/appliances', label: 'Appliances' },
      { to: '/furniture', label: 'Furniture' },
      { to: '/rooms', label: 'Storage' },
    ],
  },
  { to: '/trash', label: 'Trash', icon: 'i-lucide-trash-2' },
]

const primaryMobileLinks = navLinks.filter((link) => ['/lists', '/recipes', '/items', '/household'].includes(link.to))
const moreLinks = navLinks.filter((link) => !primaryMobileLinks.includes(link))

const sidebarCollapsed = ref(true)
const householdExpanded = ref(false)
const mobileMoreOpen = ref(false)

const route = useRoute()
watch(
  () => route.path,
  () => {
    mobileMoreOpen.value = false
  },
)
const pageTitles: Record<string, string> = {
  '/': 'Home',
  '/lists': 'Lists',
  '/recipes': 'Recipes',
  '/items': 'Items',
  '/categories': 'Categories',
  '/tags': 'Tags',
  '/units': 'Units',
  '/household': 'Household',
  '/pantry': 'Pantry',
  '/home-inventory': 'Home Inventory',
  '/equipment': 'Equipment',
  '/appliances': 'Appliances',
  '/furniture': 'Furniture',
  '/rooms': 'Storage',
  '/storage': 'Storage',
  '/recipe-categories': 'Recipe Categories',
  '/trash': 'Trash',
  '/settings': 'Settings',
  '/login': 'Log in',
  '/forgot-password': 'Reset password',
  '/reset-password': 'Set a new password',
  '/signup': 'Sign up',
}
const pageEntityName = usePageEntityName()
const basePath = computed(() => {
  if (route.path === '/') return '/'
  const match = Object.keys(pageTitles)
    .filter((path) => path !== '/' && route.path.startsWith(path))
    .sort((a, b) => b.length - a.length)[0]
  return match ?? null
})
const baseTitle = computed(() => (basePath.value ? pageTitles[basePath.value] : 'Lista'))
const pageTitle = computed(() =>
  pageEntityName.value ? `${baseTitle.value} — ${pageEntityName.value}` : baseTitle.value,
)

useHead({
  title: computed(() => `${pageTitle.value} - Lista`),
})
</script>

<template>
  <div class="flex h-dvh overflow-hidden">
    <aside
      v-if="user"
      class="hidden shrink-0 flex-col overflow-y-auto border-r border-default px-3 py-4 transition-[width] duration-200 sm:flex"
      :class="sidebarCollapsed ? 'sm:w-16' : 'sm:w-56'"
    >
      <div class="mb-2 flex items-center gap-1 px-1">
        <UButton
          variant="ghost"
          size="sm"
          :icon="sidebarCollapsed ? 'i-lucide-panel-left-open' : 'i-lucide-panel-left-close'"
          :title="sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'"
          @click="sidebarCollapsed = !sidebarCollapsed"
        />
        <NuxtLink v-if="!sidebarCollapsed" to="/" class="text-lg font-semibold">Lista</NuxtLink>
      </div>

      <nav class="flex flex-1 flex-col gap-1">
        <template v-for="link in navLinks" :key="link.to">
          <div class="flex items-center">
            <NuxtLink
              :to="link.to"
              :title="sidebarCollapsed ? link.label : undefined"
              class="flex flex-1 items-center gap-2 rounded px-2 py-2 text-sm hover:bg-elevated"
              active-class="bg-elevated text-primary"
            >
              <UIcon :name="link.icon" class="size-5 shrink-0" />
              <span v-if="!sidebarCollapsed">{{ link.label }}</span>
            </NuxtLink>
            <UButton
              v-if="link.children && !sidebarCollapsed"
              variant="ghost"
              size="sm"
              :icon="householdExpanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
              :title="householdExpanded ? 'Collapse' : 'Expand'"
              @click="householdExpanded = !householdExpanded"
            />
          </div>
          <div v-if="link.children && !sidebarCollapsed && householdExpanded" class="ml-6 flex flex-col gap-1">
            <NuxtLink
              v-for="child in link.children"
              :key="child.to"
              :to="child.to"
              class="rounded px-2 py-1.5 text-sm text-muted hover:bg-elevated"
              active-class="bg-elevated text-primary"
            >
              {{ child.label }}
            </NuxtLink>
          </div>
        </template>
      </nav>
    </aside>

    <div class="flex min-h-0 flex-1 flex-col overflow-hidden">
      <header class="flex shrink-0 items-center justify-between border-b border-default px-4 py-3">
        <div class="flex items-center gap-2">
          <NuxtLink
            v-if="user && route.path !== '/'"
            to="/"
            class="font-semibold"
          >
            Home
          </NuxtLink>
          <span v-if="user && route.path !== '/'">></span>
          <h1 class="font-semibold">
            <NuxtLink v-if="pageEntityName && basePath" :to="basePath" class="hover:underline">
              {{ baseTitle }}
            </NuxtLink>
            <template v-else>{{ baseTitle }}</template>
            <span v-if="pageEntityName"> — {{ pageEntityName }}</span>
          </h1>
        </div>
        <div v-if="user" class="flex items-center gap-2">
          <UDropdownMenu :items="headerMenuItems">
            <UButton variant="ghost" size="sm" icon="i-lucide-circle-user" />
          </UDropdownMenu>
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
          <p class="text-sm font-medium">{{ username || 'Account' }}</p>
          <p class="text-muted mb-2 text-sm">{{ user?.email }}</p>
          <UButton block variant="outline" @click="signOut">Sign out</UButton>
        </div>
      </template>
    </USlideover>
  </div>
</template>
