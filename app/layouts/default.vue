<script setup lang="ts">
const supabase = useSupabaseClient()
const user = useSupabaseUser()

const { data: username } = await useAsyncData('current-username', async () => {
  if (!user.value) return null
  const { data } = await supabase.from('users').select('username').eq('id', user.value.id).single()
  return data?.username ?? null
})

const userMenuItems = [[{ label: 'Settings', icon: 'i-lucide-settings', to: '/settings' }]]

async function signOut() {
  await supabase.auth.signOut()
  await navigateTo('/login')
}
</script>

<template>
  <div class="min-h-screen">
    <header class="flex items-center justify-between border-b border-default px-4 py-3">
      <div class="flex items-center gap-6">
        <NuxtLink to="/" class="font-semibold">Lista</NuxtLink>
        <nav v-if="user" class="flex items-center gap-4 text-sm">
          <NuxtLink to="/lists" class="hover:text-primary">Lists</NuxtLink>
          <NuxtLink to="/items" class="hover:text-primary">Items</NuxtLink>
          <NuxtLink to="/categories" class="hover:text-primary">Categories</NuxtLink>
          <NuxtLink to="/units" class="hover:text-primary">Units</NuxtLink>
        </nav>
      </div>
      <div v-if="user" class="flex items-center gap-3">
        <UDropdownMenu :items="userMenuItems">
          <UButton variant="ghost" size="sm" trailing-icon="i-lucide-chevron-down">
            {{ username ?? user.email }}
          </UButton>
        </UDropdownMenu>
        <UButton size="sm" variant="outline" @click="signOut">Sign out</UButton>
      </div>
    </header>

    <main class="p-4">
      <slot />
    </main>
  </div>
</template>
