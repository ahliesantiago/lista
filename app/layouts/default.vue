<script setup lang="ts">
const supabase = useSupabaseClient()
const user = useSupabaseUser()

async function signOut() {
  await supabase.auth.signOut()
  await navigateTo('/login')
}
</script>

<template>
  <div class="min-h-screen">
    <header class="flex items-center justify-between border-b border-default px-4 py-3">
      <span class="font-semibold">Lista</span>
      <div v-if="user" class="flex items-center gap-3">
        <span class="text-sm text-muted">{{ user.email }}</span>
        <UButton size="sm" variant="outline" @click="signOut">Sign out</UButton>
      </div>
    </header>

    <main class="p-4">
      <slot />
    </main>
  </div>
</template>
