<script setup lang="ts">
type Option = { id: string; name: string }
const MAX_LOCATIONS = 2
const MAX_ROOMS = 2

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: furniture, refresh } = await useAsyncData('furniture', async () => {
  const { data, error } = await supabase
    .from('furniture')
    .select(`
      id, name, brand, quantity, needs_maintenance, needs_replacement, notes, is_equipment,
      furniture_locations(storage_location:storage_locations(id, name, room:rooms(id, name))),
      furniture_rooms(room:rooms(id, name))
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

type FurnitureRow = NonNullable<typeof furniture.value>[number]

const filterLocations = ref<Option[]>([])
const filterRooms = ref<Option[]>([])

const filteredFurniture = computed(() => {
  let list = furniture.value ?? []
  if (filterLocations.value.length > 0) {
    const ids = new Set(filterLocations.value.map((l) => l.id))
    list = list.filter((f) => f.furniture_locations.some((fl) => ids.has(fl.storage_location!.id)))
  }
  if (filterRooms.value.length > 0) {
    const ids = new Set(filterRooms.value.map((r) => r.id))
    list = list.filter((f) => f.furniture_rooms.some((fr) => ids.has(fr.room!.id)))
  }
  return list
})

const {
  sortBy,
  groupBy,
  sortOptions,
  groupOptions,
  sortedItems: visibleFurniture,
  groupedItems: groupedFurniture,
} = useListControls<FurnitureRow>(
  filteredFurniture,
  {
    'name-asc': { label: 'Name (A–Z)', compare: (a, b) => a.name.localeCompare(b.name) },
    'name-desc': { label: 'Name (Z–A)', compare: (a, b) => b.name.localeCompare(a.name) },
  },
  {
    location: {
      label: 'Location',
      getKeys: (f) =>
        f.furniture_locations.length > 0
          ? f.furniture_locations.map((fl) => fl.storage_location!.name)
          : ['No location set'],
    },
    room: {
      label: 'Room',
      getKeys: (f) => (f.furniture_rooms.length > 0 ? f.furniture_rooms.map((fr) => fr.room!.name) : ['Unassigned']),
    },
  },
)

const newName = ref('')
const newBrand = ref('')
const newQuantity = ref(1)
const newNeedsMaintenance = ref(false)
const newNeedsReplacement = ref(false)
const newNotes = ref('')
const newIsEquipment = ref(false)
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

async function addFurniture() {
  if (!space.value) return
  error.value = ''
  saving.value = true
  const { data, error: insertError } = await supabase
    .from('furniture')
    .insert({
      space_id: space.value.id,
      name: newName.value.trim(),
      brand: newBrand.value.trim() || null,
      quantity: newQuantity.value,
      needs_maintenance: newNeedsMaintenance.value,
      needs_replacement: newNeedsReplacement.value,
      notes: newNotes.value.trim() || null,
      is_equipment: newIsEquipment.value,
    })
    .select('id')
    .single()
  saving.value = false
  if (insertError || !data) {
    error.value = insertError?.message ?? 'Failed to add furniture'
    return
  }
  if (newLocations.value.length > 0) {
    await supabase.from('furniture_locations').insert(
      newLocations.value.map((l) => ({ furniture_id: data.id, storage_location_id: l.id })),
    )
  }
  if (newRooms.value.length > 0) {
    await supabase.from('furniture_rooms').insert(newRooms.value.map((r) => ({ furniture_id: data.id, room_id: r.id })))
  }
  newName.value = ''
  newBrand.value = ''
  newQuantity.value = 1
  newNeedsMaintenance.value = false
  newNeedsReplacement.value = false
  newNotes.value = ''
  newIsEquipment.value = false
  newLocations.value = []
  newRooms.value = []
  await refresh()
}

async function deleteFurniture(id: string) {
  await supabase.from('furniture').update({ deleted_at: new Date().toISOString() }).eq('id', id)
  await refresh()
}

const editingId = ref<string | null>(null)
const editName = ref('')
const editBrand = ref('')
const editQuantity = ref(1)
const editNeedsMaintenance = ref(false)
const editNeedsReplacement = ref(false)
const editNotes = ref('')
const editIsEquipment = ref(false)
const editLocations = ref<Option[]>([])
const editRooms = ref<Option[]>([])

watch(editLocations, (val) => {
  if (val.length > MAX_LOCATIONS) editLocations.value = val.slice(0, MAX_LOCATIONS)
})
watch(editRooms, (val) => {
  if (val.length > MAX_ROOMS) editRooms.value = val.slice(0, MAX_ROOMS)
})

function startEdit(item: FurnitureRow) {
  editingId.value = item.id
  editName.value = item.name
  editBrand.value = item.brand ?? ''
  editQuantity.value = item.quantity
  editNeedsMaintenance.value = item.needs_maintenance
  editNeedsReplacement.value = item.needs_replacement
  editNotes.value = item.notes ?? ''
  editIsEquipment.value = item.is_equipment
  editLocations.value = item.furniture_locations.map((l) => {
    const loc = l.storage_location!
    return (
      locationOptionsForPicker.value.find((o) => o.id === loc.id) ?? {
        ...loc,
        label: loc.room ? `${loc.name} (${loc.room.name})` : loc.name,
      }
    )
  })
  editRooms.value = item.furniture_rooms.map((r) => r.room!)
}

function cancelEdit() {
  editingId.value = null
}

async function saveEdit(id: string) {
  await supabase
    .from('furniture')
    .update({
      name: editName.value.trim(),
      brand: editBrand.value.trim() || null,
      quantity: editQuantity.value,
      needs_maintenance: editNeedsMaintenance.value,
      needs_replacement: editNeedsReplacement.value,
      notes: editNotes.value.trim() || null,
      is_equipment: editIsEquipment.value,
    })
    .eq('id', id)
  await supabase.from('furniture_locations').delete().eq('furniture_id', id)
  await supabase.from('furniture_rooms').delete().eq('furniture_id', id)
  if (editLocations.value.length > 0) {
    await supabase.from('furniture_locations').insert(
      editLocations.value.map((l) => ({ furniture_id: id, storage_location_id: l.id })),
    )
  }
  if (editRooms.value.length > 0) {
    await supabase.from('furniture_rooms').insert(editRooms.value.map((r) => ({ furniture_id: id, room_id: r.id })))
  }
  editingId.value = null
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <form class="mb-6 flex flex-col gap-2" @submit.prevent="addFurniture">
      <div class="grid grid-cols-2 gap-2 sm:grid-cols-4">
        <UInput v-model="newName" placeholder="Name (e.g. Sofa)" required class="col-span-2" />
        <UInput v-model="newBrand" placeholder="Brand (optional)" />
        <UInputNumber v-model="newQuantity" :min="1" />
        <UCheckbox v-model="newNeedsMaintenance" label="Needs maintenance" />
        <UCheckbox v-model="newNeedsReplacement" label="Needs replacement" />
        <UCheckbox v-model="newIsEquipment" label="Used as cooking equipment" class="col-span-2 whitespace-nowrap" />
        <UInput v-model="newNotes" placeholder="Notes (optional)" class="col-span-2" />
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
      <UButton type="submit" :loading="saving">Add furniture</UButton>
    </form>

    <p v-if="error" class="mb-4 text-sm text-red-500">{{ error }}</p>

    <div class="mb-4 grid grid-cols-1 gap-2 sm:grid-cols-2">
      <div>
        <label class="text-muted mb-1 block text-xs">Sort by</label>
        <USelect v-model="sortBy" :items="sortOptions" class="w-full" />
      </div>
      <div>
        <label class="text-muted mb-1 block text-xs">Group by</label>
        <USelect v-model="groupBy" :items="groupOptions" class="w-full" />
      </div>
      <div>
        <label class="text-muted mb-1 block text-xs">Filter by location</label>
        <UInputMenu
          v-model="filterLocations"
          :items="locationOptionsForPicker"
          multiple
          label-key="label"
          placeholder="Any location"
          class="w-full"
        />
      </div>
      <div>
        <label class="text-muted mb-1 block text-xs">Filter by room</label>
        <UInputMenu
          v-model="filterRooms"
          :items="roomOptions ?? []"
          multiple
          label-key="name"
          placeholder="Any room"
          class="w-full"
        />
      </div>
    </div>

    <template v-if="groupedFurniture">
      <div v-for="[groupName, groupFurniture] in groupedFurniture" :key="groupName" class="mb-4">
        <h2 class="mb-2 text-sm font-semibold text-muted">{{ groupName }}</h2>
        <ul class="flex flex-col gap-2">
          <li v-for="item in groupFurniture" :key="item.id" class="rounded border border-default px-3 py-2">
            <div v-if="editingId !== item.id" class="flex items-center justify-between">
              <div>
                <span class="font-medium">{{ item.name }}</span>
                <span v-if="item.brand" class="text-muted ml-2 text-sm">{{ item.brand }}</span>
                <UBadge v-if="item.quantity > 1" size="sm" variant="subtle" class="ml-2">
                  x{{ item.quantity }}
                </UBadge>
                <UBadge v-if="item.needs_maintenance" size="sm" color="warning" class="ml-2">
                  Needs maintenance
                </UBadge>
                <UBadge v-if="item.needs_replacement" size="sm" color="error" class="ml-2">
                  Needs replacement
                </UBadge>
                <UBadge
                  v-for="fl in item.furniture_locations"
                  :key="fl.storage_location!.id"
                  size="sm"
                  variant="outline"
                  class="ml-2"
                >
                  {{ fl.storage_location!.name }}
                </UBadge>
                <UBadge v-for="fr in item.furniture_rooms" :key="fr.room!.id" size="sm" variant="outline" class="ml-2">
                  {{ fr.room!.name }}
                </UBadge>
                <p v-if="item.notes" class="text-muted mt-1 text-sm">{{ item.notes }}</p>
              </div>
              <div class="flex gap-1">
                <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(item)" />
                <UButton
                  size="sm"
                  variant="ghost"
                  color="error"
                  icon="i-lucide-trash-2"
                  @click="deleteFurniture(item.id)"
                />
              </div>
            </div>
            <div v-else class="flex flex-col gap-2">
              <div class="grid grid-cols-2 gap-2 sm:grid-cols-4">
                <UInput v-model="editName" placeholder="Name" class="col-span-2" />
                <UInput v-model="editBrand" placeholder="Brand (optional)" />
                <UInputNumber v-model="editQuantity" :min="1" />
                <UCheckbox v-model="editNeedsMaintenance" label="Needs maintenance" />
                <UCheckbox v-model="editNeedsReplacement" label="Needs replacement" />
                <UCheckbox v-model="editIsEquipment" label="Used as cooking equipment" class="col-span-2 whitespace-nowrap" />
                <UInput v-model="editNotes" placeholder="Notes (optional)" class="col-span-2" />
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
        </ul>
      </div>
      <p v-if="groupedFurniture.length === 0" class="text-muted text-sm">No furniture matches.</p>
    </template>

    <ul v-else class="flex flex-col gap-2">
      <li v-for="item in visibleFurniture" :key="item.id" class="rounded border border-default px-3 py-2">
        <div v-if="editingId !== item.id" class="flex items-center justify-between">
          <div>
            <span class="font-medium">{{ item.name }}</span>
            <span v-if="item.brand" class="text-muted ml-2 text-sm">{{ item.brand }}</span>
            <UBadge v-if="item.quantity > 1" size="sm" variant="subtle" class="ml-2">
              x{{ item.quantity }}
            </UBadge>
            <UBadge v-if="item.needs_maintenance" size="sm" color="warning" class="ml-2">
              Needs maintenance
            </UBadge>
            <UBadge v-if="item.needs_replacement" size="sm" color="error" class="ml-2">
              Needs replacement
            </UBadge>
            <UBadge
              v-for="fl in item.furniture_locations"
              :key="fl.storage_location!.id"
              size="sm"
              variant="outline"
              class="ml-2"
            >
              {{ fl.storage_location!.name }}
            </UBadge>
            <UBadge v-for="fr in item.furniture_rooms" :key="fr.room!.id" size="sm" variant="outline" class="ml-2">
              {{ fr.room!.name }}
            </UBadge>
            <p v-if="item.notes" class="text-muted mt-1 text-sm">{{ item.notes }}</p>
          </div>
          <div class="flex gap-1">
            <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(item)" />
            <UButton
              size="sm"
              variant="ghost"
              color="error"
              icon="i-lucide-trash-2"
              @click="deleteFurniture(item.id)"
            />
          </div>
        </div>
        <div v-else class="flex flex-col gap-2">
          <div class="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <UInput v-model="editName" placeholder="Name" class="col-span-2" />
            <UInput v-model="editBrand" placeholder="Brand (optional)" />
            <UInputNumber v-model="editQuantity" :min="1" />
            <UCheckbox v-model="editNeedsMaintenance" label="Needs maintenance" />
            <UCheckbox v-model="editNeedsReplacement" label="Needs replacement" />
            <UCheckbox v-model="editIsEquipment" label="Used as cooking equipment" class="col-span-2 whitespace-nowrap" />
            <UInput v-model="editNotes" placeholder="Notes (optional)" class="col-span-2" />
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
      <li v-if="visibleFurniture.length === 0" class="text-muted text-sm">No furniture matches.</li>
    </ul>
  </div>
</template>
