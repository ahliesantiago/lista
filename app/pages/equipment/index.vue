<script setup lang="ts">
type Option = { id: string; name: string }
const MAX_LOCATIONS = 2
const MAX_ROOMS = 2

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: equipment, refresh } = await useAsyncData('equipment', async () => {
  const { data, error } = await supabase
    .from('equipment')
    .select(`
      id, name, notes,
      equipment_locations(storage_location:storage_locations(id, name, room:rooms(id, name))),
      equipment_rooms(room:rooms(id, name))
    `)
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data
})

const { data: locationOptionsInitial } = await useAsyncData('pantry-location-options', async () => {
  const { data, error } = await supabase
    .from('storage_locations')
    .select('id, name, room:rooms(id, name)')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data
})
const locationOptionsForPicker = computed(() =>
  (locationOptionsInitial.value ?? []).map((l) => ({
    ...l,
    label: l.room ? `${l.name} (${l.room.name})` : l.name,
  })),
)

const { data: roomOptions } = await useAsyncData('room-options', async () => {
  const { data, error } = await supabase.from('rooms').select('id, name').is('deleted_at', null).order('name')
  if (error) throw error
  return data as Option[]
})

const newName = ref('')
const newNotes = ref('')
const newLocations = ref<Option[]>([])
const newRooms = ref<Option[]>([])
const error = ref('')
const saving = ref(false)

watch(newLocations, (val) => {
  if (val.length > MAX_LOCATIONS) newLocations.value = val.slice(0, MAX_LOCATIONS)
})
watch(newRooms, (val) => {
  if (val.length > MAX_ROOMS) newRooms.value = val.slice(0, MAX_ROOMS)
})

async function addEquipment() {
  if (!space.value) return
  error.value = ''
  saving.value = true
  const { data, error: insertError } = await supabase
    .from('equipment')
    .insert({
      space_id: space.value.id,
      name: newName.value.trim(),
      notes: newNotes.value.trim() || null,
    })
    .select('id')
    .single()
  saving.value = false
  if (insertError || !data) {
    error.value = insertError?.message ?? 'Failed to add equipment'
    return
  }
  if (newLocations.value.length > 0) {
    await supabase.from('equipment_locations').insert(
      newLocations.value.map((l) => ({ equipment_id: data.id, storage_location_id: l.id })),
    )
  }
  if (newRooms.value.length > 0) {
    await supabase.from('equipment_rooms').insert(
      newRooms.value.map((r) => ({ equipment_id: data.id, room_id: r.id })),
    )
  }
  newName.value = ''
  newNotes.value = ''
  newLocations.value = []
  newRooms.value = []
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
const editLocations = ref<Option[]>([])
const editRooms = ref<Option[]>([])

watch(editLocations, (val) => {
  if (val.length > MAX_LOCATIONS) editLocations.value = val.slice(0, MAX_LOCATIONS)
})
watch(editRooms, (val) => {
  if (val.length > MAX_ROOMS) editRooms.value = val.slice(0, MAX_ROOMS)
})

function startEdit(item: Equipment) {
  editingId.value = item.id
  editName.value = item.name
  editNotes.value = item.notes ?? ''
  editLocations.value = item.equipment_locations.map((l) => {
    const loc = l.storage_location!
    return (
      locationOptionsForPicker.value.find((o) => o.id === loc.id) ?? {
        ...loc,
        label: loc.room ? `${loc.name} (${loc.room.name})` : loc.name,
      }
    )
  })
  editRooms.value = item.equipment_rooms.map((r) => r.room!)
}

function cancelEdit() {
  editingId.value = null
}

async function saveEdit(id: string) {
  await supabase
    .from('equipment')
    .update({ name: editName.value.trim(), notes: editNotes.value.trim() || null })
    .eq('id', id)
  await supabase.from('equipment_locations').delete().eq('equipment_id', id)
  await supabase.from('equipment_rooms').delete().eq('equipment_id', id)
  if (editLocations.value.length > 0) {
    await supabase.from('equipment_locations').insert(
      editLocations.value.map((l) => ({ equipment_id: id, storage_location_id: l.id })),
    )
  }
  if (editRooms.value.length > 0) {
    await supabase.from('equipment_rooms').insert(editRooms.value.map((r) => ({ equipment_id: id, room_id: r.id })))
  }
  editingId.value = null
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-lg">
    <form class="mb-6 flex flex-col gap-2" @submit.prevent="addEquipment">
      <div class="flex flex-col gap-2 sm:flex-row">
        <UInput v-model="newName" placeholder="Equipment (e.g. Blender)" required class="flex-1" />
        <UInput v-model="newNotes" placeholder="Notes (optional)" class="flex-1" />
        <UButton type="submit" :loading="saving">Add</UButton>
      </div>
      <div class="flex flex-col gap-2">
        <UInputMenu
          v-model="newLocations"
          :items="locationOptionsForPicker"
          multiple
          label-key="label"
          placeholder="Locations (up to 2, optional)"
          class="w-full"
        />
        <UInputMenu
          v-model="newRooms"
          :items="roomOptions ?? []"
          multiple
          label-key="name"
          placeholder="Rooms (up to 2, optional)"
          class="w-full"
        />
      </div>
    </form>

    <p v-if="error" class="mb-4 text-sm text-red-500">{{ error }}</p>

    <ul class="flex flex-col gap-2">
      <li v-for="item in equipment" :key="item.id" class="rounded border border-default px-3 py-2">
        <div v-if="editingId !== item.id" class="flex items-center justify-between">
          <span>
            {{ item.name }}
            <span v-if="item.notes" class="text-muted text-sm">({{ item.notes }})</span>
            <UBadge
              v-for="il in item.equipment_locations"
              :key="il.storage_location!.id"
              size="sm"
              variant="outline"
              class="ml-2"
            >
              {{ il.storage_location!.name }}
            </UBadge>
            <UBadge
              v-for="ir in item.equipment_rooms"
              :key="ir.room!.id"
              size="sm"
              variant="outline"
              class="ml-2"
            >
              {{ ir.room!.name }}
            </UBadge>
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
        <div v-else class="flex flex-col gap-2">
          <div class="flex flex-col gap-2 sm:flex-row">
            <UInput v-model="editName" placeholder="Equipment" class="flex-1" />
            <UInput v-model="editNotes" placeholder="Notes (optional)" class="flex-1" />
          </div>
          <div class="flex flex-col gap-2">
            <UInputMenu
              v-model="editLocations"
              :items="locationOptionsForPicker"
              multiple
              label-key="label"
              placeholder="Locations (up to 2)"
              class="w-full"
            />
            <UInputMenu
              v-model="editRooms"
              :items="roomOptions ?? []"
              multiple
              label-key="name"
              placeholder="Rooms (up to 2)"
              class="w-full"
            />
          </div>
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
