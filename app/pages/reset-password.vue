<script setup lang="ts">
const supabase = useSupabaseClient()

const newPassword = ref('')
const confirmPassword = ref('')
const error = ref('')
const success = ref(false)
const loading = ref(false)

async function onSubmit() {
  error.value = ''

  if (newPassword.value !== confirmPassword.value) {
    error.value = 'Passwords do not match.'
    return
  }

  loading.value = true
  const { error: updateError } = await supabase.auth.updateUser({ password: newPassword.value })
  loading.value = false

  if (updateError) {
    error.value = updateError.message
    return
  }
  success.value = true
}

async function continueToLogin() {
  await supabase.auth.signOut()
  await navigateTo('/login')
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center p-4">
    <UCard class="w-full max-w-sm">
      <template #header>
        <h1 class="text-lg font-semibold">Set a new password</h1>
      </template>

      <div v-if="success" class="flex flex-col gap-4">
        <p class="text-sm text-primary">Password updated.</p>
        <UButton block @click="continueToLogin">Continue to log in</UButton>
      </div>

      <form v-else class="flex flex-col gap-4" @submit.prevent="onSubmit">
        <UFormField label="New password">
          <UInput v-model="newPassword" type="password" autocomplete="new-password" required class="w-full" />
        </UFormField>

        <UFormField label="Confirm new password">
          <UInput v-model="confirmPassword" type="password" autocomplete="new-password" required class="w-full" />
        </UFormField>

        <p v-if="error" class="text-sm text-red-500">{{ error }}</p>

        <UButton type="submit" block :loading="loading">Update password</UButton>
      </form>
    </UCard>
  </div>
</template>
