<script setup lang="ts">
// Cooking equipment isn't its own table - it's items/appliances/furniture
// flagged is_equipment. This page is a merged, filtered view over the
// three, not an independent CRUD surface: location/room assignment and
// permanent deletion stay on each source's own dedicated page (Items,
// Appliances, Furniture) to avoid duplicating that logic three times here.
// "Remove" on this page only clears is_equipment - it never touches
// deleted_at, so the underlying item/appliance/furniture is untouched.
type EquipmentSource = 'item' | 'appliance' | 'furniture'
type EquipmentRow = {
  id: string
  source: EquipmentSource
  name: string
  notes: string | null
  locations: string[]
  rooms: string[]
}

const SOURCE_LABELS: Record<EquipmentSource, string> = {
  item: 'Item',
  appliance: 'Appliance',
  furniture: 'Furniture',
}
const SOURCE_TABLES: Record<EquipmentSource, 'items' | 'appliances' | 'furniture'> = {
  item: 'items',
  appliance: 'appliances',
  furniture: 'furniture',
}

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: equipment, refresh } = await useAsyncData('cooking-equipment', async () => {
  const [itemsRes, appliancesRes, furnitureRes] = await Promise.all([
    supabase.from('items').select('id, name, notes').eq('is_equipment', true).is('deleted_at', null).order('name'),
    supabase
      .from('appliances')
      .select(`
        id, name, notes,
        appliance_locations(storage_location:storage_locations(id, name)),
        appliance_rooms(room:rooms(id, name))
      `)
      .eq('is_equipment', true)
      .is('deleted_at', null)
      .order('name'),
    supabase
      .from('furniture')
      .select(`
        id, name, notes,
        furniture_locations(storage_location:storage_locations(id, name)),
        furniture_rooms(room:rooms(id, name))
      `)
      .eq('is_equipment', true)
      .is('deleted_at', null)
      .order('name'),
  ])
  if (itemsRes.error) throw itemsRes.error
  if (appliancesRes.error) throw appliancesRes.error
  if (furnitureRes.error) throw furnitureRes.error

  const rows: EquipmentRow[] = [
    ...itemsRes.data.map((i): EquipmentRow => ({ id: i.id, source: 'item', name: i.name, notes: i.notes, locations: [], rooms: [] })),
    ...appliancesRes.data.map(
      (a): EquipmentRow => ({
        id: a.id,
        source: 'appliance',
        name: a.name,
        notes: a.notes,
        locations: a.appliance_locations.map((l) => l.storage_location!.name),
        rooms: a.appliance_rooms.map((r) => r.room!.name),
      }),
    ),
    ...furnitureRes.data.map(
      (f): EquipmentRow => ({
        id: f.id,
        source: 'furniture',
        name: f.name,
        notes: f.notes,
        locations: f.furniture_locations.map((l) => l.storage_location!.name),
        rooms: f.furniture_rooms.map((r) => r.room!.name),
      }),
    ),
  ]
  return rows.sort((a, b) => a.name.localeCompare(b.name))
})

const sortedEquipment = computed(() => equipment.value ?? [])

const newSource = ref<EquipmentSource>('appliance')
const sourceOptions = (Object.entries(SOURCE_LABELS) as [EquipmentSource, string][]).map(([value, label]) => ({
  value,
  label,
}))
const newName = ref('')
const newNotes = ref('')
const error = ref('')
const saving = ref(false)

async function addEquipment() {
  if (!space.value || !newName.value.trim()) return
  error.value = ''
  saving.value = true
  const { error: insertError } = await supabase
    .from(SOURCE_TABLES[newSource.value])
    .insert({ space_id: space.value.id, name: newName.value.trim(), notes: newNotes.value.trim() || null, is_equipment: true })
  saving.value = false
  if (insertError) {
    error.value = insertError.message
    return
  }
  newName.value = ''
  newNotes.value = ''
  await refresh()
}

async function removeFromEquipment(row: EquipmentRow) {
  await supabase.from(SOURCE_TABLES[row.source]).update({ is_equipment: false }).eq('id', row.id)
  await refresh()
}

const editingId = ref<string | null>(null)
const editName = ref('')
const editNotes = ref('')

function startEdit(row: EquipmentRow) {
  editingId.value = row.id
  editName.value = row.name
  editNotes.value = row.notes ?? ''
}

function cancelEdit() {
  editingId.value = null
}

async function saveEdit(row: EquipmentRow) {
  await supabase
    .from(SOURCE_TABLES[row.source])
    .update({ name: editName.value.trim(), notes: editNotes.value.trim() || null })
    .eq('id', row.id)
  editingId.value = null
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-lg">
    <form class="mb-6 flex flex-col gap-2" @submit.prevent="addEquipment">
      <div class="flex flex-col gap-2 sm:flex-row">
        <USelect v-model="newSource" :items="sourceOptions" value-key="value" class="sm:w-36" />
        <UInput v-model="newName" placeholder="Equipment (e.g. Blender)" required class="flex-1" />
        <UButton type="submit" :loading="saving">Add</UButton>
      </div>
      <UInput v-model="newNotes" placeholder="Notes (optional)" />
    </form>
    <p class="text-muted mb-4 text-xs">
      Classifying as Appliance or Furniture lets you also set its location/room from those pages. Items don't track
      location unless also added to Home Inventory.
    </p>

    <p v-if="error" class="mb-4 text-sm text-red-500">{{ error }}</p>

    <ul class="flex flex-col gap-2">
      <li v-for="row in sortedEquipment" :key="`${row.source}-${row.id}`" class="rounded border border-default px-3 py-2">
        <div v-if="editingId !== row.id" class="flex items-center justify-between gap-2">
          <div>
            <span>{{ row.name }}</span>
            <UBadge size="sm" variant="subtle" color="neutral" class="ml-2">{{ SOURCE_LABELS[row.source] }}</UBadge>
            <UBadge v-for="l in row.locations" :key="l" size="sm" variant="outline" class="ml-2">{{ l }}</UBadge>
            <UBadge v-for="r in row.rooms" :key="r" size="sm" variant="outline" class="ml-2">{{ r }}</UBadge>
            <p v-if="row.notes" class="text-muted mt-1 text-sm">{{ row.notes }}</p>
          </div>
          <div class="flex shrink-0 gap-1">
            <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(row)" />
            <UButton
              size="sm"
              variant="ghost"
              color="error"
              icon="i-lucide-x"
              title="Remove from cooking equipment (doesn't delete it)"
              @click="removeFromEquipment(row)"
            />
          </div>
        </div>
        <div v-else class="flex flex-col gap-2">
          <div class="flex flex-col gap-2 sm:flex-row">
            <UInput v-model="editName" placeholder="Name" class="flex-1" />
            <UInput v-model="editNotes" placeholder="Notes (optional)" class="flex-1" />
          </div>
          <div class="flex gap-1">
            <UButton size="sm" @click="saveEdit(row)">Save</UButton>
            <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
          </div>
        </div>
      </li>
      <li v-if="sortedEquipment.length === 0" class="text-muted text-sm">No cooking equipment yet.</li>
    </ul>
  </div>
</template>
