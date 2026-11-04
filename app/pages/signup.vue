<script setup lang="ts">
definePageMeta({ middleware: 'guest' })

const supabase = useSupabaseClient()
const email = ref('')
const password = ref('')
const error = ref('')
const loading = ref(false)

async function onSubmit() {
  error.value = ''
  loading.value = true
  const { error: signUpError } = await supabase.auth.signUp({
    email: email.value,
    password: password.value,
  })
  loading.value = false
  if (signUpError) {
    error.value = signUpError.message
    return
  }
  await navigateTo('/')
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center p-4">
    <UCard class="w-full max-w-sm">
      <template #header>
        <h1 class="text-lg font-semibold">Sign up</h1>
      </template>

      <form class="flex flex-col gap-4" @submit.prevent="onSubmit">
        <UFormField label="Email">
          <UInput v-model="email" type="email" autocomplete="email" required class="w-full" />
        </UFormField>

        <UFormField label="Password">
          <UInput v-model="password" type="password" autocomplete="new-password" required class="w-full" />
        </UFormField>

        <p v-if="error" class="text-sm text-red-500">{{ error }}</p>

        <UButton type="submit" block :loading="loading">Sign up</UButton>
      </form>

      <template #footer>
        <p class="text-sm">
          Already have an account?
          <NuxtLink to="/login" class="text-primary underline">Log in</NuxtLink>
        </p>
      </template>
    </UCard>
  </div>
</template>
