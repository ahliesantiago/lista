<script setup lang="ts">
import tailwindColors from 'tailwindcss/colors'

const supabase = useSupabaseClient()
const user = useSupabaseUser()

const { primaryColor, setPrimaryColor } = usePrimaryColor()
function swatchColor(color: string) {
  return (tailwindColors as Record<string, Record<number, string>>)[color]?.[500] ?? '#888'
}

const { data: profile, refresh: refreshProfile } = await useAsyncData(
  'settings-profile',
  async () => {
    if (!user.value) return null
    const { data } = await supabase
      .from('users')
      .select('username, preferred_name')
      .eq('id', user.value.sub)
      .single()
    return data
  },
  { watch: [user] },
)

const username = ref('')
const preferredName = ref('')
watch(
  profile,
  (value) => {
    username.value = value?.username ?? ''
    preferredName.value = value?.preferred_name ?? ''
  },
  { immediate: true },
)

const profileError = ref('')
const profileSuccess = ref('')
const profileLoading = ref(false)

async function saveProfile() {
  if (!user.value) return
  profileError.value = ''
  profileSuccess.value = ''
  profileLoading.value = true

  const { error } = await supabase
    .from('users')
    .update({ username: username.value.trim(), preferred_name: preferredName.value.trim() || null })
    .eq('id', user.value.sub)

  profileLoading.value = false
  if (error) {
    profileError.value = error.code === '23505' ? 'That username is already taken.' : error.message
    return
  }
  profileSuccess.value = 'Profile updated.'
  await refreshProfile()
  await refreshNuxtData('current-username')
}

const email = ref(user.value?.email ?? '')
const emailError = ref('')
const emailSuccess = ref('')
const emailLoading = ref(false)

async function saveEmail() {
  emailError.value = ''
  emailSuccess.value = ''
  emailLoading.value = true

  const { error } = await supabase.auth.updateUser({ email: email.value.trim() })

  emailLoading.value = false
  if (error) {
    emailError.value = error.message
    return
  }
  emailSuccess.value = 'Check your inbox to confirm the new email address.'
}

const newPassword = ref('')
const confirmPassword = ref('')
const passwordError = ref('')
const passwordSuccess = ref('')
const passwordLoading = ref(false)

async function savePassword() {
  passwordError.value = ''
  passwordSuccess.value = ''

  if (newPassword.value !== confirmPassword.value) {
    passwordError.value = 'Passwords do not match.'
    return
  }

  passwordLoading.value = true
  const { error } = await supabase.auth.updateUser({ password: newPassword.value })
  passwordLoading.value = false

  if (error) {
    passwordError.value = error.message
    return
  }
  passwordSuccess.value = 'Password updated.'
  newPassword.value = ''
  confirmPassword.value = ''
}
</script>

<template>
  <div class="mx-auto max-w-2xl pb-12">
    <div class="flex flex-col gap-4">
      <div class="rounded border border-default px-4 py-3">
        <h2 class="mb-3 font-medium">Profile</h2>
        <form class="flex flex-col gap-4" @submit.prevent="saveProfile">
          <UFormField label="Display Name" hint="Optional">
            <UInput v-model="preferredName" class="w-full" />
          </UFormField>

          <UFormField label="Username">
            <UInput v-model="username" autocomplete="username" required class="w-full" />
          </UFormField>

          <p v-if="profileError" class="text-sm text-red-500">{{ profileError }}</p>
          <p v-if="profileSuccess" class="text-sm text-green-500">{{ profileSuccess }}</p>

          <UButton type="submit" :loading="profileLoading" class="self-start">Save</UButton>
        </form>
      </div>

      <div class="rounded border border-default px-4 py-3">
        <h2 class="mb-3 font-medium">Appearance</h2>
        <div class="flex flex-col gap-4">
          <UFormField label="Color mode" hint="Defaults to your system setting">
            <UColorModeSelect class="w-40" />
          </UFormField>

          <UFormField label="Color scheme">
            <div class="flex flex-wrap gap-2">
              <button
                v-for="color in PRIMARY_COLOR_OPTIONS"
                :key="color"
                type="button"
                class="size-8 rounded-full ring-2 ring-offset-2 ring-offset-default transition-shadow"
                :class="primaryColor === color ? 'ring-default' : 'ring-transparent hover:ring-accented'"
                :style="{ backgroundColor: swatchColor(color) }"
                :title="color"
                :aria-label="`Use ${color} as the color scheme`"
                @click="setPrimaryColor(color)"
              />
            </div>
          </UFormField>
        </div>
      </div>

      <div class="rounded border border-default px-4 py-3">
        <h2 class="mb-3 font-medium">Email</h2>
        <form class="flex flex-col gap-4" @submit.prevent="saveEmail">
          <UFormField label="Email address">
            <UInput v-model="email" type="email" autocomplete="email" required class="w-full" />
          </UFormField>

          <p v-if="emailError" class="text-sm text-red-500">{{ emailError }}</p>
          <p v-if="emailSuccess" class="text-sm text-primary">{{ emailSuccess }}</p>

          <UButton type="submit" :loading="emailLoading" class="self-start">Update email</UButton>
        </form>
      </div>

      <div class="rounded border border-default px-4 py-3">
        <h2 class="mb-3 font-medium">Password</h2>
        <form class="flex flex-col gap-4" @submit.prevent="savePassword">
          <UFormField label="New password">
            <UInput v-model="newPassword" type="password" autocomplete="new-password" required class="w-full" />
          </UFormField>

          <UFormField label="Confirm new password">
            <UInput v-model="confirmPassword" type="password" autocomplete="new-password" required class="w-full" />
          </UFormField>

          <p v-if="passwordError" class="text-sm text-red-500">{{ passwordError }}</p>
          <p v-if="passwordSuccess" class="text-sm text-primary">{{ passwordSuccess }}</p>

          <UButton type="submit" :loading="passwordLoading" class="self-start">Update password</UButton>
        </form>
      </div>

      <div class="rounded border border-default px-4 py-3 opacity-60">
        <h2 class="font-medium">Space</h2>
        <p class="text-muted text-sm">Rename your space, manage members. Coming soon.</p>
      </div>

      <div class="rounded border border-default px-4 py-3 opacity-60">
        <h2 class="font-medium">Notifications</h2>
        <p class="text-muted text-sm">Coming soon.</p>
      </div>

      <div class="flex items-center justify-between rounded border border-default px-4 py-3">
        <div>
          <h2 class="font-medium">Trash</h2>
          <p class="text-muted text-sm">Restore or permanently delete anything you've removed.</p>
        </div>
        <UButton to="/trash" variant="outline">Go to Trash</UButton>
      </div>
    </div>
  </div>
</template>
