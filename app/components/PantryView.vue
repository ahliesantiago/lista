<script setup lang="ts">
const props = defineProps<{ kind: 'pantry' | 'household' }>()

type Option = { id: string; name: string }
type UnitOption = { id: string; name_singular: string; name_plural: string }
const UNIT_FILTER_FIELDS = ['name_singular', 'name_plural']

const STOCK_STATUS_LABELS = ['No status', 'In stock', 'Low', 'Out'] as const
type StockStatusLabel = (typeof STOCK_STATUS_LABELS)[number]
const STOCK_STATUS_TO_DB: Record<StockStatusLabel, 'in_stock' | 'low' | 'out' | null> = {
  'No status': null,
  'In stock': 'in_stock',
  Low: 'low',
  Out: 'out',
}
const DB_TO_STOCK_STATUS: Record<string, StockStatusLabel> = {
  in_stock: 'In stock',
  low: 'Low',
  out: 'Out',
}

const pageTitle = props.kind === 'pantry' ? 'Pantry' : 'Home Inventory'
const addLabel = props.kind === 'pantry' ? 'Add to pantry' : 'Add to home inventory'
const emptyLabel =
  props.kind === 'pantry' ? 'Nothing in the pantry yet.' : 'Nothing in home inventory yet.'

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

// cache key must include `kind` - useAsyncData's key is global, not scoped
// to this component instance, so the Pantry and Home Inventory pages (both
// rendering this same component with a different kind) would otherwise
// silently share one cached, wrongly-filtered result
const { data: inventoryItems, refresh } = await useAsyncData(`inventory-items-${props.kind}`, async () => {
  const { data, error } = await supabase
    .from('inventory_items')
    .select(`
      id, stock_status, quantity, notes,
      storage_location:storage_locations(id, name, room:rooms(id, name)),
      item:items(id, name, item_categories(categories(id, name, parent_id))),
      unit:units(id, name_singular, name_plural)
    `)
    .eq('kind', props.kind)
    .is('deleted_at', null)
    .order('created_at')
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

const itemOptions = ref<Option[]>([])
const { data: itemOptionsInitial } = await useAsyncData('item-options', async () => {
  const { data, error } = await supabase.from('items').select('id, name').is('deleted_at', null).order('name')
  if (error) throw error
  return data
})
itemOptions.value = itemOptionsInitial.value ?? []

const { data: unitOptions } = await useAsyncData('unit-options', async () => {
  const { data, error } = await supabase
    .from('units')
    .select('id, name_singular, name_plural, abbrev_singular, abbrev_plural')
    .is('deleted_at', null)
    .order('name_singular')
  if (error) throw error
  return data
})

const { data: activeLists } = await useAsyncData('pantry-active-lists', async () => {
  const { data, error } = await supabase
    .from('lists')
    .select('id, name')
    .eq('status', 'active')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data
})

type InventoryItem = NonNullable<typeof inventoryItems.value>[number]

function unitLabel(unit: { name_singular: string; name_plural: string } | null, amount: number | null) {
  if (!unit) return ''
  return amount != null && amount !== 1 ? unit.name_plural : unit.name_singular
}

const groupedItems = computed(() => {
  const roomMap = new Map<string, Map<string, InventoryItem[]>>()
  for (const p of inventoryItems.value ?? []) {
    const roomLabel = p.storage_location ? p.storage_location.room?.name || 'Other' : 'Unassigned'
    const locName = p.storage_location ? p.storage_location.name : 'No location set'
    if (!roomMap.has(roomLabel)) roomMap.set(roomLabel, new Map())
    const locMap = roomMap.get(roomLabel)!
    if (!locMap.has(locName)) locMap.set(locName, [])
    locMap.get(locName)!.push(p)
  }
  return Array.from(roomMap.entries()).map(([room, locMap]) => ({
    room,
    locations: Array.from(locMap.entries()).map(([name, items]) => ({ name, items })),
  }))
})

// --- add to list (manual "need to buy" surfacing) ---

const addListSelection = reactive<Record<string, Option | null>>({})

async function onPickListForItem(p: InventoryItem, list: Option | null) {
  if (!list) return
  await supabase.from('list_items').insert({
    list_id: list.id,
    item_id: p.item!.id,
    name: p.item!.name,
    unit_id: p.unit?.id ?? null,
  })
  addListSelection[p.id] = null
}

// --- manual add/deduct ---

async function bumpQuantity(p: InventoryItem, delta: number) {
  const next = Math.max(0, (p.quantity ?? 0) + delta)
  await supabase.from('inventory_items').update({ quantity: next }).eq('id', p.id)
  await refresh()
}

async function deleteInventoryItem(id: string) {
  await supabase.from('inventory_items').update({ deleted_at: new Date().toISOString() }).eq('id', id)
  await refresh()
}

// --- add/edit slideover ---

const slideoverOpen = ref(false)
const editingId = ref<string | null>(null)
const selectedLocationId = ref<string | null>(null)
const selectedItem = ref<Option | null>(null)
const stockStatusLabel = ref<StockStatusLabel>('No status')
const quantity = ref<number | null>(null)
const unitId = ref<string | null>(null)
const notes = ref('')
const error = ref('')
const saving = ref(false)

// a unit an entry stays linked to can be trashed (soft delete never touches
// the link); the picker options are live-only, so without this it can't
// resolve a label for the current value and falls back to the raw id.
const extraUnitOption = ref<UnitOption | null>(null)
const unitOptionsForForm = computed(() => {
  const base = unitOptions.value ?? []
  const extra = extraUnitOption.value
  return extra && !base.some((u) => u.id === extra.id) ? [...base, extra] : base
})

function resetForm() {
  editingId.value = null
  selectedLocationId.value = null
  selectedItem.value = null
  stockStatusLabel.value = 'No status'
  quantity.value = null
  unitId.value = null
  extraUnitOption.value = null
  notes.value = ''
  error.value = ''
}

function openCreate() {
  resetForm()
  slideoverOpen.value = true
}

function openEdit(p: InventoryItem) {
  editingId.value = p.id
  selectedLocationId.value = p.storage_location?.id ?? null
  selectedItem.value = p.item ? { id: p.item.id, name: p.item.name } : null
  stockStatusLabel.value = p.stock_status ? DB_TO_STOCK_STATUS[p.stock_status] : 'No status'
  quantity.value = p.quantity
  unitId.value = p.unit?.id ?? null
  extraUnitOption.value = p.unit ?? null
  notes.value = p.notes ?? ''
  error.value = ''
  slideoverOpen.value = true
}

async function onCreateItemOption(searchTerm: string) {
  if (!space.value) return
  const { data, error: insertError } = await supabase
    .from('items')
    .insert({ space_id: space.value.id, name: searchTerm })
    .select('id, name')
    .single()
  if (insertError || !data) return
  itemOptions.value.push(data)
  selectedItem.value = data
}

async function save() {
  if (!space.value || !selectedItem.value) return
  error.value = ''
  saving.value = true

  const payload = {
    space_id: space.value.id,
    storage_location_id: selectedLocationId.value,
    item_id: selectedItem.value.id,
    kind: props.kind,
    stock_status: STOCK_STATUS_TO_DB[stockStatusLabel.value],
    quantity: quantity.value,
    unit_id: unitId.value,
    notes: notes.value.trim() || null,
  }

  const { error: saveError } = editingId.value
    ? await supabase.from('inventory_items').update(payload).eq('id', editingId.value)
    : await supabase.from('inventory_items').insert(payload)

  saving.value = false
  if (saveError) {
    error.value = saveError.message
    return
  }

  slideoverOpen.value = false
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <div class="mb-4 flex items-center justify-between">
      <h1 class="text-xl font-semibold">{{ pageTitle }}</h1>
      <div class="flex gap-2">
        <UButton to="/storage" variant="outline" size="sm">Manage locations</UButton>
        <UButton icon="i-lucide-plus" @click="openCreate">{{ addLabel }}</UButton>
      </div>
    </div>

    <div v-for="group in groupedItems" :key="group.room" class="mb-6">
      <h2 class="mb-2 text-sm font-semibold text-muted">{{ group.room }}</h2>
      <div v-for="loc in group.locations" :key="loc.name" class="mb-4">
        <h3 class="mb-2 text-sm text-muted">{{ loc.name }}</h3>
        <ul class="flex flex-col gap-2">
          <li
            v-for="p in loc.items"
            :key="p.id"
            class="flex items-center justify-between rounded border border-default px-3 py-2"
          >
            <div class="flex-1 cursor-pointer" @click="openEdit(p)">
              <span class="font-medium">{{ p.item!.name }}</span>
              <UBadge
                v-for="ic in p.item!.item_categories"
                :key="ic.categories!.id"
                size="sm"
                :variant="ic.categories!.parent_id ? 'subtle' : 'solid'"
                class="ml-2"
              >
                {{ ic.categories!.name }}
              </UBadge>
              <UBadge
                v-if="p.stock_status"
                size="sm"
                :color="p.stock_status === 'out' ? 'error' : p.stock_status === 'low' ? 'warning' : 'success'"
                class="ml-2"
              >
                {{ DB_TO_STOCK_STATUS[p.stock_status] }}
              </UBadge>
              <span v-if="p.quantity != null" class="text-muted ml-2 text-sm">
                {{ p.quantity }}<span v-if="p.unit">{{ ' ' + unitLabel(p.unit, p.quantity) }}</span>
              </span>
              <p v-if="p.notes" class="text-muted text-xs">{{ p.notes }}</p>
            </div>
            <div class="flex items-center gap-1" @click.stop>
              <UButton size="xs" variant="ghost" icon="i-lucide-minus" @click="bumpQuantity(p, -1)" />
              <UButton size="xs" variant="ghost" icon="i-lucide-plus" @click="bumpQuantity(p, 1)" />
              <UInputMenu
                :model-value="addListSelection[p.id] ?? null"
                :items="activeLists ?? []"
                label-key="name"
                placeholder="Add to list..."
                class="w-36"
                @update:model-value="(val) => onPickListForItem(p, val)"
              />
              <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="openEdit(p)" />
              <UButton
                size="sm"
                variant="ghost"
                color="error"
                icon="i-lucide-trash-2"
                @click="deleteInventoryItem(p.id)"
              />
            </div>
          </li>
        </ul>
      </div>
    </div>
    <p v-if="inventoryItems && inventoryItems.length === 0" class="text-muted text-sm">
      {{ emptyLabel }}
    </p>

    <USlideover v-model:open="slideoverOpen" :title="editingId ? 'Edit entry' : addLabel">
      <template #body>
        <form class="flex flex-col gap-4" @submit.prevent="save">
          <UFormField label="Item">
            <UInputMenu
              v-model="selectedItem"
              :items="itemOptions"
              create-item
              label-key="name"
              class="w-full"
              @create="onCreateItemOption"
            />
          </UFormField>

          <UFormField label="Location" hint="Optional">
            <UInputMenu
              v-model="selectedLocationId"
              :items="locationOptionsForPicker"
              value-key="id"
              label-key="label"
              class="w-full"
            />
          </UFormField>

          <UFormField label="Stock status" hint="Optional">
            <USelect v-model="stockStatusLabel" :items="STOCK_STATUS_LABELS" class="w-full" />
          </UFormField>

          <div class="flex gap-2">
            <UFormField label="Quantity" hint="Optional" class="flex-1">
              <UInputNumber v-model="quantity" :min="0" class="w-full" />
            </UFormField>
            <UFormField label="Unit" hint="Optional" class="flex-1">
              <UInputMenu
                v-model="unitId"
                :items="unitOptionsForForm"
                value-key="id"
                label-key="name_singular"
                :filter-fields="UNIT_FILTER_FIELDS"
                class="w-full"
              />
            </UFormField>
          </div>

          <UFormField label="Notes" hint="Optional">
            <UInput v-model="notes" class="w-full" />
          </UFormField>

          <p v-if="error" class="text-sm text-red-500">{{ error }}</p>

          <UButton type="submit" block :loading="saving">{{ editingId ? 'Save' : addLabel }}</UButton>
        </form>
      </template>
    </USlideover>
  </div>
</template>
