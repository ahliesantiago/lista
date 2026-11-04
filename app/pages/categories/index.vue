<script setup lang="ts">
const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: categories, refresh } = await useAsyncData('categories', async () => {
  const { data, error } = await supabase.from('categories').select('id, name').order('name')
  if (error) throw error
  return data
})

const newName = ref('')
const error = ref('')
const saving = ref(false)

async function addCategory() {
  if (!space.value) return
  error.value = ''
  saving.value = true
  const { error: insertError } = await supabase
    .from('categories')
    .insert({ space_id: space.value.id, name: newName.value.trim() })
  saving.value = false
  if (insertError) {
    error.value = insertError.message
    return
  }
  newName.value = ''
  await refresh()
}

async function deleteCategory(id: string) {
  await supabase.from('categories').delete().eq('id', id)
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-lg">
    <h1 class="mb-4 text-xl font-semibold">Categories</h1>

    <form class="mb-6 flex gap-2" @submit.prevent="addCategory">
      <UInput v-model="newName" placeholder="New category" required class="flex-1" />
      <UButton type="submit" :loading="saving">Add</UButton>
    </form>

    <p v-if="error" class="mb-4 text-sm text-red-500">{{ error }}</p>

    <ul class="flex flex-col gap-2">
      <li
        v-for="category in categories"
        :key="category.id"
        class="flex items-center justify-between rounded border border-default px-3 py-2"
      >
        <span>{{ category.name }}</span>
        <UButton size="sm" variant="ghost" color="error" icon="i-lucide-trash-2" @click="deleteCategory(category.id)" />
      </li>
      <li v-if="categories && categories.length === 0" class="text-muted text-sm">No categories yet.</li>
    </ul>
  </div>
</template>
