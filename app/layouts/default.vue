<script setup lang="ts">
const supabase = useSupabaseClient()
const user = useSupabaseUser()

const { data: username } = await useAsyncData('current-username', async () => {
  if (!user.value) return null
  const { data } = await supabase.from('users').select('username').eq('id', user.value.id).single()
  return data?.username ?? null
})

const userMenuItems = [[{ label: 'Settings', icon: 'i-lucide-settings', to: '/settings' }]]

const navLinks = [
  { to: '/lists', label: 'Lists' },
  { to: '/recipes', label: 'Recipes' },
  { to: '/items', label: 'Items' },
  { to: '/categories', label: 'Categories' },
  { to: '/units', label: 'Units' },
  { to: '/household', label: 'Household' },
]

const mobileNavOpen = ref(false)

async function signOut() {
  mobileNavOpen.value = false
  await supabase.auth.signOut()
  await navigateTo('/login')
}
</script>

<template>
  <div class="min-h-screen">
    <header class="flex items-center justify-between border-b border-default px-4 py-3">
      <div class="flex items-center gap-6">
        <NuxtLink to="/" class="font-semibold">Lista</NuxtLink>
        <nav v-if="user" class="hidden items-center gap-4 text-sm sm:flex">
          <NuxtLink v-for="link in navLinks" :key="link.to" :to="link.to" class="hover:text-primary">
            {{ link.label }}
          </NuxtLink>
        </nav>
      </div>
      <div v-if="user" class="hidden items-center gap-3 sm:flex">
        <UDropdownMenu :items="userMenuItems">
          <UButton variant="ghost" size="sm" trailing-icon="i-lucide-chevron-down">
            {{ username ?? user.email }}
          </UButton>
        </UDropdownMenu>
        <UButton size="sm" variant="outline" @click="signOut">Sign out</UButton>
      </div>
      <UButton
        v-if="user"
        class="sm:hidden"
        variant="ghost"
        size="sm"
        icon="i-lucide-menu"
        @click="mobileNavOpen = true"
      />
    </header>

    <USlideover v-model:open="mobileNavOpen" title="Menu">
      <template #body>
        <nav class="flex flex-col gap-1">
          <NuxtLink
            v-for="link in navLinks"
            :key="link.to"
            :to="link.to"
            class="rounded px-2 py-2 hover:bg-elevated"
            @click="mobileNavOpen = false"
          >
            {{ link.label }}
          </NuxtLink>
          <NuxtLink to="/settings" class="rounded px-2 py-2 hover:bg-elevated" @click="mobileNavOpen = false">
            Settings
          </NuxtLink>
        </nav>
        <div class="mt-4 border-t border-default pt-4">
          <p class="text-muted mb-2 text-sm">{{ username ?? user?.email }}</p>
          <UButton block variant="outline" @click="signOut">Sign out</UButton>
        </div>
      </template>
    </USlideover>

    <main class="p-4">
      <slot />
    </main>
  </div>
</template>
