<script setup lang="ts">
definePageMeta({ middleware: 'guest' })

const supabase = useSupabaseClient()
const email = ref('')
const error = ref('')
const success = ref(false)
const loading = ref(false)

async function onSubmit() {
  error.value = ''
  loading.value = true

  const { error: resetError } = await supabase.auth.resetPasswordForEmail(email.value.trim(), {
    redirectTo: `${window.location.origin}/reset-password`,
  })

  loading.value = false
  if (resetError) {
    error.value = resetError.message
    return
  }
  success.value = true
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center p-4">
    <UCard class="w-full max-w-sm">
      <template #header>
        <h1 class="text-lg font-semibold">Reset password</h1>
      </template>

      <p v-if="success" class="text-sm">
        If an account exists for <strong>{{ email }}</strong>, a password reset link has been sent. Check your
        inbox.
      </p>

      <form v-else class="flex flex-col gap-4" @submit.prevent="onSubmit">
        <p class="text-muted text-sm">Enter your email and we'll send you a link to reset your password.</p>

        <UFormField label="Email">
          <UInput v-model="email" type="email" autocomplete="email" required class="w-full" />
        </UFormField>

        <p v-if="error" class="text-sm text-red-500">{{ error }}</p>

        <UButton type="submit" block :loading="loading">Send reset link</UButton>
      </form>

      <template #footer>
        <p class="text-sm">
          <NuxtLink to="/login" class="text-primary underline">Back to log in</NuxtLink>
        </p>
      </template>
    </UCard>
  </div>
</template>
