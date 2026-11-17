<script setup lang="ts">
type Tag = { id: string; name: string }

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: tags, refresh } = await useAsyncData('tags', async () => {
  const { data, error } = await supabase.from('tags').select('id, name').is('deleted_at', null).order('name')
  if (error) throw error
  return data as Tag[]
})

const newName = ref('')
const error = ref('')
const saving = ref(false)

async function addTag() {
  if (!space.value) return
  error.value = ''
  saving.value = true
  const { error: insertError } = await supabase
    .from('tags')
    .insert({ space_id: space.value.id, name: newName.value.trim() })
  saving.value = false
  if (insertError) {
    error.value = insertError.message
    return
  }
  newName.value = ''
  await refresh()
}

async function deleteTag(id: string) {
  await supabase.from('tags').update({ deleted_at: new Date().toISOString() }).eq('id', id)
  await refresh()
}

const editingId = ref<string | null>(null)
const editName = ref('')

function startEdit(tag: Tag) {
  editingId.value = tag.id
  editName.value = tag.name
}

function cancelEdit() {
  editingId.value = null
}

async function saveEdit(id: string) {
  await supabase.from('tags').update({ name: editName.value.trim() }).eq('id', id)
  editingId.value = null
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-lg">
    <form class="mb-6 flex gap-2" @submit.prevent="addTag">
      <UInput v-model="newName" placeholder="New tag" required class="flex-1" />
      <UButton type="submit" :loading="saving">Add</UButton>
    </form>

    <p v-if="error" class="mb-4 text-sm text-red-500">{{ error }}</p>

    <ul class="flex flex-col gap-2">
      <li v-for="tag in tags" :key="tag.id" class="rounded border border-default px-3 py-2">
        <div v-if="editingId !== tag.id" class="flex items-center justify-between">
          <span>{{ tag.name }}</span>
          <div class="flex gap-1">
            <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(tag)" />
            <UButton size="sm" variant="ghost" color="error" icon="i-lucide-trash-2" @click="deleteTag(tag.id)" />
          </div>
        </div>
        <div v-else class="flex gap-2">
          <UInput v-model="editName" class="flex-1" />
          <UButton size="sm" @click="saveEdit(tag.id)">Save</UButton>
          <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
        </div>
      </li>
      <li v-if="tags && tags.length === 0" class="text-muted text-sm">No tags yet.</li>
    </ul>
  </div>
</template>
