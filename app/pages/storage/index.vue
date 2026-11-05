<script setup lang="ts">
const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: locations, refresh } = await useAsyncData('storage-locations', async () => {
  const { data, error } = await supabase
    .from('storage_locations')
    .select('id, name, room')
    .is('deleted_at', null)
    .order('room')
    .order('name')
  if (error) throw error
  return data
})

const newName = ref('')
const newRoom = ref('')
const error = ref('')
const saving = ref(false)

async function addLocation() {
  if (!space.value) return
  error.value = ''
  saving.value = true
  const { error: insertError } = await supabase.from('storage_locations').insert({
    space_id: space.value.id,
    name: newName.value.trim(),
    room: newRoom.value.trim() || null,
  })
  saving.value = false
  if (insertError) {
    error.value = insertError.message
    return
  }
  newName.value = ''
  newRoom.value = ''
  await refresh()
}

async function deleteLocation(id: string) {
  // soft delete only: keeps inventory_items links intact so restoring from
  // Trash brings them back. Also cascade-soft-deletes its (then-live)
  // inventory items, mirroring deleteList()'s cascade to list_items.
  const deletedAt = new Date().toISOString()
  await supabase.from('storage_locations').update({ deleted_at: deletedAt }).eq('id', id)
  await supabase
    .from('inventory_items')
    .update({ deleted_at: deletedAt })
    .eq('storage_location_id', id)
    .is('deleted_at', null)
  await refresh()
}

type Location = NonNullable<typeof locations.value>[number]
const editingId = ref<string | null>(null)
const editName = ref('')
const editRoom = ref('')

function startEdit(location: Location) {
  editingId.value = location.id
  editName.value = location.name
  editRoom.value = location.room ?? ''
}

function cancelEdit() {
  editingId.value = null
}

async function saveEdit(id: string) {
  await supabase
    .from('storage_locations')
    .update({ name: editName.value.trim(), room: editRoom.value.trim() || null })
    .eq('id', id)
  editingId.value = null
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-lg">
    <h1 class="mb-4 text-xl font-semibold">Storage Locations</h1>

    <form class="mb-6 flex flex-col gap-2 sm:flex-row" @submit.prevent="addLocation">
      <UInput v-model="newName" placeholder="Location (e.g. Fridge)" required class="flex-1" />
      <UInput v-model="newRoom" placeholder="Room (optional)" class="flex-1" />
      <UButton type="submit" :loading="saving">Add</UButton>
    </form>

    <p v-if="error" class="mb-4 text-sm text-red-500">{{ error }}</p>

    <ul class="flex flex-col gap-2">
      <li v-for="location in locations" :key="location.id" class="rounded border border-default px-3 py-2">
        <div v-if="editingId !== location.id" class="flex items-center justify-between">
          <span>
            {{ location.name }}
            <span v-if="location.room" class="text-muted text-sm">({{ location.room }})</span>
          </span>
          <div class="flex gap-1">
            <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(location)" />
            <UButton
              size="sm"
              variant="ghost"
              color="error"
              icon="i-lucide-trash-2"
              @click="deleteLocation(location.id)"
            />
          </div>
        </div>
        <div v-else class="flex flex-col gap-2 sm:flex-row">
          <UInput v-model="editName" placeholder="Location" class="flex-1" />
          <UInput v-model="editRoom" placeholder="Room (optional)" class="flex-1" />
          <div class="flex gap-1">
            <UButton size="sm" @click="saveEdit(location.id)">Save</UButton>
            <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
          </div>
        </div>
      </li>
      <li v-if="locations && locations.length === 0" class="text-muted text-sm">No storage locations yet.</li>
    </ul>
  </div>
</template>
