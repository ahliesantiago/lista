<script setup lang="ts">
const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: rooms, refresh } = await useAsyncData('rooms', async () => {
  const { data, error } = await supabase.from('rooms').select('id, name').is('deleted_at', null).order('name')
  if (error) throw error
  return data
})

const newName = ref('')
const error = ref('')
const saving = ref(false)

async function addRoom() {
  if (!space.value) return
  error.value = ''
  saving.value = true
  const { error: insertError } = await supabase
    .from('rooms')
    .insert({ space_id: space.value.id, name: newName.value.trim() })
  saving.value = false
  if (insertError) {
    error.value = insertError.message
    return
  }
  newName.value = ''
  await refresh()
}

async function deleteRoom(id: string) {
  // soft delete only: keeps storage_locations.room_id links intact so
  // restoring from Trash brings them back.
  await supabase.from('rooms').update({ deleted_at: new Date().toISOString() }).eq('id', id)
  await refresh()
}

const editingId = ref<string | null>(null)
const editName = ref('')

function startEdit(room: { id: string; name: string }) {
  editingId.value = room.id
  editName.value = room.name
}

function cancelEdit() {
  editingId.value = null
}

async function saveEdit(id: string) {
  await supabase.from('rooms').update({ name: editName.value.trim() }).eq('id', id)
  editingId.value = null
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-lg">
    <h1 class="mb-4 text-xl font-semibold">Rooms</h1>

    <form class="mb-6 flex gap-2" @submit.prevent="addRoom">
      <UInput v-model="newName" placeholder="Room (e.g. Kitchen)" required class="flex-1" />
      <UButton type="submit" :loading="saving">Add</UButton>
    </form>

    <p v-if="error" class="mb-4 text-sm text-red-500">{{ error }}</p>

    <ul class="flex flex-col gap-2">
      <li v-for="room in rooms" :key="room.id" class="rounded border border-default px-3 py-2">
        <div v-if="editingId !== room.id" class="flex items-center justify-between">
          <span>{{ room.name }}</span>
          <div class="flex gap-1">
            <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(room)" />
            <UButton
              size="sm"
              variant="ghost"
              color="error"
              icon="i-lucide-trash-2"
              @click="deleteRoom(room.id)"
            />
          </div>
        </div>
        <div v-else class="flex gap-2">
          <UInput v-model="editName" class="flex-1" />
          <div class="flex gap-1">
            <UButton size="sm" @click="saveEdit(room.id)">Save</UButton>
            <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
          </div>
        </div>
      </li>
      <li v-if="rooms && rooms.length === 0" class="text-muted text-sm">No rooms yet.</li>
    </ul>
  </div>
</template>
