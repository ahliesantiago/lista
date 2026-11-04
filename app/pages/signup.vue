<script setup lang="ts">
definePageMeta({ middleware: 'guest' })

const supabase = useSupabaseClient()

const username = ref('')
const preferredName = ref('')
const spaceName = ref('')
const password = ref('')
const email = ref('')
const error = ref('')
const loading = ref(false)

const spaceNameTouched = ref(false)

watch([username, preferredName], ([newUsername, newPreferredName]) => {
  if (spaceNameTouched.value) return
  const base = newPreferredName.trim() || newUsername.trim()
  spaceName.value = base ? `${base}'s Space` : ''
})

function onSpaceNameInput() {
  spaceNameTouched.value = true
}

async function onSubmit() {
  error.value = ''
  loading.value = true

  const { error: signUpError } = await supabase.auth.signUp({
    email: email.value.trim(),
    password: password.value,
    options: {
      data: {
        username: username.value.trim(),
        preferred_name: preferredName.value.trim() || null,
        space_name: spaceName.value.trim(),
      },
    },
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
        <UFormField label="Username">
          <UInput v-model="username" autocomplete="username" required class="w-full" />
        </UFormField>

        <UFormField label="Preferred Name (Display Name)" hint="Optional">
          <UInput v-model="preferredName" autocomplete="nickname" class="w-full" />
        </UFormField>

        <UFormField label="Space Name">
          <UInput v-model="spaceName" class="w-full" @input="onSpaceNameInput" />
        </UFormField>

        <UFormField label="Password">
          <UInput v-model="password" type="password" autocomplete="new-password" required class="w-full" />
        </UFormField>

        <UFormField label="Email">
          <UInput v-model="email" type="email" autocomplete="email" required class="w-full" />
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
