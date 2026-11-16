<script setup lang="ts">
type RoomOption = { id: string; name: string }

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: locations, refresh } = await useAsyncData('storage-locations', async () => {
  const { data, error } = await supabase
    .from('storage_locations')
    .select('id, name, room:rooms(id, name)')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data
})

const roomOptions = ref<RoomOption[]>([])
const { data: roomOptionsInitial } = await useAsyncData('room-options', async () => {
  const { data, error } = await supabase.from('rooms').select('id, name').is('deleted_at', null).order('name')
  if (error) throw error
  return data
})
roomOptions.value = roomOptionsInitial.value ?? []

type Location = NonNullable<typeof locations.value>[number]

const groupedLocations = computed(() => {
  const map = new Map<string, Location[]>()
  for (const l of locations.value ?? []) {
    const roomLabel = l.room?.name ?? 'No room'
    const list = map.get(roomLabel) ?? []
    list.push(l)
    map.set(roomLabel, list)
  }
  return Array.from(map.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([room, locs]) => ({ room, locations: locs }))
})

async function insertRoom(name: string): Promise<RoomOption | null> {
  if (!space.value) return null
  const { data, error: insertError } = await supabase
    .from('rooms')
    .insert({ space_id: space.value.id, name })
    .select('id, name')
    .single()
  if (insertError || !data) return null
  roomOptions.value.push(data)
  return data
}

async function onCreateRoomOptionForAdd(searchTerm: string) {
  const data = await insertRoom(searchTerm)
  if (data) newRoom.value = data
}

async function onCreateRoomOptionForEdit(searchTerm: string) {
  const data = await insertRoom(searchTerm)
  if (data) editRoom.value = data
}

const newName = ref('')
const newRoom = ref<RoomOption | null>(null)
const error = ref('')
const saving = ref(false)

async function addLocation() {
  if (!space.value) return
  error.value = ''
  saving.value = true
  const { error: insertError } = await supabase.from('storage_locations').insert({
    space_id: space.value.id,
    name: newName.value.trim(),
    room_id: newRoom.value?.id ?? null,
  })
  saving.value = false
  if (insertError) {
    error.value = insertError.message
    return
  }
  newName.value = ''
  newRoom.value = null
  await refresh()
}

async function deleteLocation(id: string) {
  // soft delete only: keeps inventory_items links intact so restoring from
  // Trash brings them back. Also cascade-soft-deletes its (then-live)
  // inventory items, mirroring deleteList()'s cascade to list_items -
  // an item can link up to 2 locations, so this goes through the join
  // table rather than a direct column.
  const deletedAt = new Date().toISOString()
  await supabase.from('storage_locations').update({ deleted_at: deletedAt }).eq('id', id)
  const { data: linked } = await supabase
    .from('inventory_item_locations')
    .select('inventory_item_id')
    .eq('storage_location_id', id)
  const linkedIds = (linked ?? []).map((l) => l.inventory_item_id)
  if (linkedIds.length > 0) {
    await supabase
      .from('inventory_items')
      .update({ deleted_at: deletedAt })
      .in('id', linkedIds)
      .is('deleted_at', null)
  }
  await refresh()
}

const editingId = ref<string | null>(null)
const editName = ref('')
const editRoom = ref<RoomOption | null>(null)

function startEdit(location: Location) {
  editingId.value = location.id
  editName.value = location.name
  editRoom.value = location.room ? { id: location.room.id, name: location.room.name } : null
}

function cancelEdit() {
  editingId.value = null
}

async function saveEdit(id: string) {
  await supabase
    .from('storage_locations')
    .update({ name: editName.value.trim(), room_id: editRoom.value?.id ?? null })
    .eq('id', id)
  editingId.value = null
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-lg">
    <div class="mb-4 flex justify-end">
      <UButton to="/rooms" variant="outline" size="sm">Manage rooms</UButton>
    </div>

    <form class="mb-6 flex flex-col gap-2 sm:flex-row" @submit.prevent="addLocation">
      <UInput v-model="newName" placeholder="Location (e.g. Fridge)" required class="flex-1" />
      <UInputMenu
        v-model="newRoom"
        :items="roomOptions"
        create-item
        label-key="name"
        placeholder="Room (optional)"
        class="flex-1"
        @create="onCreateRoomOptionForAdd"
      />
      <UButton type="submit" :loading="saving">Add</UButton>
    </form>

    <p v-if="error" class="mb-4 text-sm text-red-500">{{ error }}</p>

    <div v-for="group in groupedLocations" :key="group.room" class="mb-4">
      <h3 class="mb-2 text-sm font-semibold text-muted">{{ group.room }}</h3>
      <ul class="flex flex-col gap-2">
        <li v-for="location in group.locations" :key="location.id" class="rounded border border-default px-3 py-2">
          <div v-if="editingId !== location.id" class="flex items-center justify-between">
            <span>{{ location.name }}</span>
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
            <UInputMenu
              v-model="editRoom"
              :items="roomOptions"
              create-item
              label-key="name"
              placeholder="Room (optional)"
              class="flex-1"
              @create="onCreateRoomOptionForEdit"
            />
            <div class="flex gap-1">
              <UButton size="sm" @click="saveEdit(location.id)">Save</UButton>
              <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
            </div>
          </div>
        </li>
      </ul>
    </div>
    <p v-if="locations && locations.length === 0" class="text-muted text-sm">No storage locations yet.</p>
  </div>
</template>
