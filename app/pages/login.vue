<script setup lang="ts">
definePageMeta({ middleware: 'guest' })

const supabase = useSupabaseClient()
const identifier = ref('')
const password = ref('')
const error = ref('')
const loading = ref(false)

const INVALID_CREDENTIALS_MESSAGE = 'Invalid login credentials'

async function onSubmit() {
  error.value = ''
  loading.value = true

  const trimmed = identifier.value.trim()
  let email = trimmed

  if (!trimmed.includes('@')) {
    const { data: resolvedEmail } = await supabase.rpc('resolve_login_email', { identifier: trimmed })
    if (!resolvedEmail) {
      loading.value = false
      error.value = INVALID_CREDENTIALS_MESSAGE
      return
    }
    email = resolvedEmail
  }

  const { error: signInError } = await supabase.auth.signInWithPassword({ email, password: password.value })
  loading.value = false
  if (signInError) {
    error.value = INVALID_CREDENTIALS_MESSAGE
    return
  }
  await navigateTo('/')
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center p-4">
    <UCard class="w-full max-w-sm">
      <template #header>
        <h1 class="text-lg font-semibold">Log in</h1>
      </template>

      <form class="flex flex-col gap-4" @submit.prevent="onSubmit">
        <UFormField label="Email or Username">
          <UInput v-model="identifier" autocomplete="username" required class="w-full" />
        </UFormField>

        <UFormField label="Password">
          <UInput v-model="password" type="password" autocomplete="current-password" required class="w-full" />
        </UFormField>

        <p v-if="error" class="text-sm text-red-500">{{ error }}</p>

        <UButton type="submit" block :loading="loading">Log in</UButton>
      </form>

      <template #footer>
        <p class="text-sm">
          No account?
          <NuxtLink to="/signup" class="text-primary underline">Sign up</NuxtLink>
        </p>
      </template>
    </UCard>
  </div>
</template>
