<script setup lang="ts">
const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: equipment, refresh } = await useAsyncData('equipment', async () => {
  const { data, error } = await supabase
    .from('equipment')
    .select('id, name, notes')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data
})

const newName = ref('')
const newNotes = ref('')
const error = ref('')
const saving = ref(false)

async function addEquipment() {
  if (!space.value) return
  error.value = ''
  saving.value = true
  const { error: insertError } = await supabase.from('equipment').insert({
    space_id: space.value.id,
    name: newName.value.trim(),
    notes: newNotes.value.trim() || null,
  })
  saving.value = false
  if (insertError) {
    error.value = insertError.message
    return
  }
  newName.value = ''
  newNotes.value = ''
  await refresh()
}

async function deleteEquipment(id: string) {
  await supabase.from('equipment').update({ deleted_at: new Date().toISOString() }).eq('id', id)
  await refresh()
}

type Equipment = NonNullable<typeof equipment.value>[number]
const editingId = ref<string | null>(null)
const editName = ref('')
const editNotes = ref('')

function startEdit(item: Equipment) {
  editingId.value = item.id
  editName.value = item.name
  editNotes.value = item.notes ?? ''
}

function cancelEdit() {
  editingId.value = null
}

async function saveEdit(id: string) {
  await supabase
    .from('equipment')
    .update({ name: editName.value.trim(), notes: editNotes.value.trim() || null })
    .eq('id', id)
  editingId.value = null
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-lg">
    <h1 class="mb-4 text-xl font-semibold">Equipment</h1>

    <form class="mb-6 flex flex-col gap-2 sm:flex-row" @submit.prevent="addEquipment">
      <UInput v-model="newName" placeholder="Equipment (e.g. Blender)" required class="flex-1" />
      <UInput v-model="newNotes" placeholder="Notes (optional)" class="flex-1" />
      <UButton type="submit" :loading="saving">Add</UButton>
    </form>

    <p v-if="error" class="mb-4 text-sm text-red-500">{{ error }}</p>

    <ul class="flex flex-col gap-2">
      <li v-for="item in equipment" :key="item.id" class="rounded border border-default px-3 py-2">
        <div v-if="editingId !== item.id" class="flex items-center justify-between">
          <span>
            {{ item.name }}
            <span v-if="item.notes" class="text-muted text-sm">({{ item.notes }})</span>
          </span>
          <div class="flex gap-1">
            <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(item)" />
            <UButton
              size="sm"
              variant="ghost"
              color="error"
              icon="i-lucide-trash-2"
              @click="deleteEquipment(item.id)"
            />
          </div>
        </div>
        <div v-else class="flex flex-col gap-2 sm:flex-row">
          <UInput v-model="editName" placeholder="Equipment" class="flex-1" />
          <UInput v-model="editNotes" placeholder="Notes (optional)" class="flex-1" />
          <div class="flex gap-1">
            <UButton size="sm" @click="saveEdit(item.id)">Save</UButton>
            <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
          </div>
        </div>
      </li>
      <li v-if="equipment && equipment.length === 0" class="text-muted text-sm">No equipment yet.</li>
    </ul>
  </div>
</template>
