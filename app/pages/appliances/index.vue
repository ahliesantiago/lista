<script setup lang="ts">
type Option = { id: string; name: string }
const MAX_LOCATIONS = 2
const MAX_ROOMS = 2

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: appliances, refresh } = await useAsyncData('appliances', async () => {
  const { data, error } = await supabase
    .from('appliances')
    .select(`
      id, name, brand, quantity, needs_maintenance, needs_replacement, notes,
      appliance_locations(storage_location:storage_locations(id, name, room:rooms(id, name))),
      appliance_rooms(room:rooms(id, name))
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

type ApplianceRow = NonNullable<typeof appliances.value>[number]

const filterLocations = ref<Option[]>([])
const filterRooms = ref<Option[]>([])

const filteredAppliances = computed(() => {
  let list = appliances.value ?? []
  if (filterLocations.value.length > 0) {
    const ids = new Set(filterLocations.value.map((l) => l.id))
    list = list.filter((a) => a.appliance_locations.some((al) => ids.has(al.storage_location!.id)))
  }
  if (filterRooms.value.length > 0) {
    const ids = new Set(filterRooms.value.map((r) => r.id))
    list = list.filter((a) => a.appliance_rooms.some((ar) => ids.has(ar.room!.id)))
  }
  return list
})

const {
  sortBy,
  groupBy,
  sortOptions,
  groupOptions,
  sortedItems: visibleAppliances,
  groupedItems: groupedAppliances,
} = useListControls<ApplianceRow>(
  filteredAppliances,
  {
    'name-asc': { label: 'Name (A–Z)', compare: (a, b) => a.name.localeCompare(b.name) },
    'name-desc': { label: 'Name (Z–A)', compare: (a, b) => b.name.localeCompare(a.name) },
  },
  {
    location: {
      label: 'Location',
      getKeys: (a) =>
        a.appliance_locations.length > 0
          ? a.appliance_locations.map((al) => al.storage_location!.name)
          : ['No location set'],
    },
    room: {
      label: 'Room',
      getKeys: (a) => (a.appliance_rooms.length > 0 ? a.appliance_rooms.map((ar) => ar.room!.name) : ['Unassigned']),
    },
  },
)

const newName = ref('')
const newBrand = ref('')
const newQuantity = ref(1)
const newNeedsMaintenance = ref(false)
const newNeedsReplacement = ref(false)
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

async function addAppliance() {
  if (!space.value) return
  error.value = ''
  saving.value = true
  const { data, error: insertError } = await supabase
    .from('appliances')
    .insert({
      space_id: space.value.id,
      name: newName.value.trim(),
      brand: newBrand.value.trim() || null,
      quantity: newQuantity.value,
      needs_maintenance: newNeedsMaintenance.value,
      needs_replacement: newNeedsReplacement.value,
      notes: newNotes.value.trim() || null,
    })
    .select('id')
    .single()
  saving.value = false
  if (insertError || !data) {
    error.value = insertError?.message ?? 'Failed to add appliance'
    return
  }
  if (newLocations.value.length > 0) {
    await supabase.from('appliance_locations').insert(
      newLocations.value.map((l) => ({ appliance_id: data.id, storage_location_id: l.id })),
    )
  }
  if (newRooms.value.length > 0) {
    await supabase.from('appliance_rooms').insert(newRooms.value.map((r) => ({ appliance_id: data.id, room_id: r.id })))
  }
  newName.value = ''
  newBrand.value = ''
  newQuantity.value = 1
  newNeedsMaintenance.value = false
  newNeedsReplacement.value = false
  newNotes.value = ''
  newLocations.value = []
  newRooms.value = []
  await refresh()
}

async function deleteAppliance(id: string) {
  await supabase.from('appliances').update({ deleted_at: new Date().toISOString() }).eq('id', id)
  await refresh()
}

const editingId = ref<string | null>(null)
const editName = ref('')
const editBrand = ref('')
const editQuantity = ref(1)
const editNeedsMaintenance = ref(false)
const editNeedsReplacement = ref(false)
const editNotes = ref('')
const editLocations = ref<Option[]>([])
const editRooms = ref<Option[]>([])

watch(editLocations, (val) => {
  if (val.length > MAX_LOCATIONS) editLocations.value = val.slice(0, MAX_LOCATIONS)
})
watch(editRooms, (val) => {
  if (val.length > MAX_ROOMS) editRooms.value = val.slice(0, MAX_ROOMS)
})

function startEdit(appliance: ApplianceRow) {
  editingId.value = appliance.id
  editName.value = appliance.name
  editBrand.value = appliance.brand ?? ''
  editQuantity.value = appliance.quantity
  editNeedsMaintenance.value = appliance.needs_maintenance
  editNeedsReplacement.value = appliance.needs_replacement
  editNotes.value = appliance.notes ?? ''
  editLocations.value = appliance.appliance_locations.map((l) => {
    const loc = l.storage_location!
    return (
      locationOptionsForPicker.value.find((o) => o.id === loc.id) ?? {
        ...loc,
        label: loc.room ? `${loc.name} (${loc.room.name})` : loc.name,
      }
    )
  })
  editRooms.value = appliance.appliance_rooms.map((r) => r.room!)
}

function cancelEdit() {
  editingId.value = null
}

async function saveEdit(id: string) {
  await supabase
    .from('appliances')
    .update({
      name: editName.value.trim(),
      brand: editBrand.value.trim() || null,
      quantity: editQuantity.value,
      needs_maintenance: editNeedsMaintenance.value,
      needs_replacement: editNeedsReplacement.value,
      notes: editNotes.value.trim() || null,
    })
    .eq('id', id)
  await supabase.from('appliance_locations').delete().eq('appliance_id', id)
  await supabase.from('appliance_rooms').delete().eq('appliance_id', id)
  if (editLocations.value.length > 0) {
    await supabase.from('appliance_locations').insert(
      editLocations.value.map((l) => ({ appliance_id: id, storage_location_id: l.id })),
    )
  }
  if (editRooms.value.length > 0) {
    await supabase.from('appliance_rooms').insert(editRooms.value.map((r) => ({ appliance_id: id, room_id: r.id })))
  }
  editingId.value = null
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <form class="mb-6 flex flex-col gap-2" @submit.prevent="addAppliance">
      <div class="grid grid-cols-2 gap-2 sm:grid-cols-4">
        <UInput v-model="newName" placeholder="Name (e.g. Dishwasher)" required class="col-span-2" />
        <UInput v-model="newBrand" placeholder="Brand (optional)" />
        <UInputNumber v-model="newQuantity" :min="1" />
        <UCheckbox v-model="newNeedsMaintenance" label="Needs maintenance" />
        <UCheckbox v-model="newNeedsReplacement" label="Needs replacement" />
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
      <UButton type="submit" :loading="saving">Add appliance</UButton>
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

    <template v-if="groupedAppliances">
      <div v-for="[groupName, groupAppliances] in groupedAppliances" :key="groupName" class="mb-4">
        <h2 class="mb-2 text-sm font-semibold text-muted">{{ groupName }}</h2>
        <ul class="flex flex-col gap-2">
          <li v-for="appliance in groupAppliances" :key="appliance.id" class="rounded border border-default px-3 py-2">
            <div v-if="editingId !== appliance.id" class="flex items-center justify-between">
              <div>
                <span class="font-medium">{{ appliance.name }}</span>
                <span v-if="appliance.brand" class="text-muted ml-2 text-sm">{{ appliance.brand }}</span>
                <UBadge v-if="appliance.quantity > 1" size="sm" variant="subtle" class="ml-2">
                  x{{ appliance.quantity }}
                </UBadge>
                <UBadge v-if="appliance.needs_maintenance" size="sm" color="warning" class="ml-2">
                  Needs maintenance
                </UBadge>
                <UBadge v-if="appliance.needs_replacement" size="sm" color="error" class="ml-2">
                  Needs replacement
                </UBadge>
                <UBadge
                  v-for="al in appliance.appliance_locations"
                  :key="al.storage_location!.id"
                  size="sm"
                  variant="outline"
                  class="ml-2"
                >
                  {{ al.storage_location!.name }}
                </UBadge>
                <UBadge
                  v-for="ar in appliance.appliance_rooms"
                  :key="ar.room!.id"
                  size="sm"
                  variant="outline"
                  class="ml-2"
                >
                  {{ ar.room!.name }}
                </UBadge>
                <p v-if="appliance.notes" class="text-muted mt-1 text-sm">{{ appliance.notes }}</p>
              </div>
              <div class="flex gap-1">
                <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(appliance)" />
                <UButton
                  size="sm"
                  variant="ghost"
                  color="error"
                  icon="i-lucide-trash-2"
                  @click="deleteAppliance(appliance.id)"
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
                <UButton size="sm" @click="saveEdit(appliance.id)">Save</UButton>
                <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
              </div>
            </div>
          </li>
        </ul>
      </div>
      <p v-if="groupedAppliances.length === 0" class="text-muted text-sm">No appliances match.</p>
    </template>

    <ul v-else class="flex flex-col gap-2">
      <li v-for="appliance in visibleAppliances" :key="appliance.id" class="rounded border border-default px-3 py-2">
        <div v-if="editingId !== appliance.id" class="flex items-center justify-between">
          <div>
            <span class="font-medium">{{ appliance.name }}</span>
            <span v-if="appliance.brand" class="text-muted ml-2 text-sm">{{ appliance.brand }}</span>
            <UBadge v-if="appliance.quantity > 1" size="sm" variant="subtle" class="ml-2">
              x{{ appliance.quantity }}
            </UBadge>
            <UBadge v-if="appliance.needs_maintenance" size="sm" color="warning" class="ml-2">
              Needs maintenance
            </UBadge>
            <UBadge v-if="appliance.needs_replacement" size="sm" color="error" class="ml-2">
              Needs replacement
            </UBadge>
            <UBadge
              v-for="al in appliance.appliance_locations"
              :key="al.storage_location!.id"
              size="sm"
              variant="outline"
              class="ml-2"
            >
              {{ al.storage_location!.name }}
            </UBadge>
            <UBadge
              v-for="ar in appliance.appliance_rooms"
              :key="ar.room!.id"
              size="sm"
              variant="outline"
              class="ml-2"
            >
              {{ ar.room!.name }}
            </UBadge>
            <p v-if="appliance.notes" class="text-muted mt-1 text-sm">{{ appliance.notes }}</p>
          </div>
          <div class="flex gap-1">
            <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(appliance)" />
            <UButton
              size="sm"
              variant="ghost"
              color="error"
              icon="i-lucide-trash-2"
              @click="deleteAppliance(appliance.id)"
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
            <UButton size="sm" @click="saveEdit(appliance.id)">Save</UButton>
            <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
          </div>
        </div>
      </li>
      <li v-if="visibleAppliances.length === 0" class="text-muted text-sm">No appliances match.</li>
    </ul>
  </div>
</template>
