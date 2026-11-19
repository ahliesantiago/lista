<script setup lang="ts">
const props = defineProps<{ kind: 'pantry' | 'household' }>()

type Option = { id: string; name: string; plural_name?: string | null }
type CategoryOption = { id: string; name: string; parent_id: string | null }
type UnitOption = { id: string; name_singular: string; name_plural: string }
const UNIT_FILTER_FIELDS = ['name_singular', 'name_plural']
const ITEM_FILTER_FIELDS = ['name', 'plural_name']
const MAX_LOCATIONS = 2
const MAX_ROOMS = 2

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
      inventory_item_locations(storage_location:storage_locations(id, name, room:rooms(id, name))),
      inventory_item_rooms(room:rooms(id, name)),
      item:items(id, name, item_categories(is_primary, categories(id, name, parent_id))),
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

const { data: roomOptions } = await useAsyncData('room-options', async () => {
  const { data, error } = await supabase.from('rooms').select('id, name').is('deleted_at', null).order('name')
  if (error) throw error
  return data as Option[]
})

const itemOptions = ref<Option[]>([])
const { data: itemOptionsInitial } = await useAsyncData('item-options', async () => {
  const { data, error } = await supabase
    .from('items')
    .select('id, name, plural_name')
    .is('deleted_at', null)
    .order('name')
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

const { data: categoryOptions } = await useAsyncData('category-options', async () => {
  const { data, error } = await supabase
    .from('categories')
    .select('id, name, parent_id')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data as CategoryOption[]
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

// an entry can now link up to 2 locations and up to 2 rooms independently;
// grouping still needs one "home" per row, so it uses the first linked
// location (falling back to the first linked room, then unassigned) while
// every linked location/room is still shown as a badge on the row itself
function primaryLocation(p: InventoryItem) {
  return p.inventory_item_locations[0]?.storage_location ?? null
}

const filterCategories = ref<CategoryOption[]>([])
const filterStockStatuses = ref<StockStatusLabel[]>([])

const filteredInventoryItems = computed(() => {
  let list = inventoryItems.value ?? []
  if (filterCategories.value.length > 0) {
    const ids = new Set(filterCategories.value.map((c) => c.id))
    list = list.filter((p) => p.item!.item_categories.some((ic) => ids.has(ic.categories!.id)))
  }
  if (filterStockStatuses.value.length > 0) {
    const dbStatuses = new Set(filterStockStatuses.value.map((s) => STOCK_STATUS_TO_DB[s]))
    list = list.filter((p) => dbStatuses.has(p.stock_status))
  }
  return list
})

const { setPrimaryCategory: setPrimaryCategoryLink, primaryCategoryKeys } = useItemCategorization()
async function setPrimaryCategory(itemId: string, categoryId: string) {
  await setPrimaryCategoryLink(itemId, categoryId)
  await refresh()
}

const {
  sortBy,
  groupBy,
  sortOptions,
  groupOptions: groupOptionsBase,
  sortedItems: sortedInventoryItems,
  groupedItems: groupedByCategoryOrStock,
} = useListControls<InventoryItem>(
  filteredInventoryItems,
  {
    'name-asc': { label: 'Name (A–Z)', compare: (a, b) => a.item!.name.localeCompare(b.item!.name) },
    'name-desc': { label: 'Name (Z–A)', compare: (a, b) => b.item!.name.localeCompare(a.item!.name) },
    'quantity-asc': { label: 'Quantity (low to high)', compare: (a, b) => (a.quantity ?? 0) - (b.quantity ?? 0) },
    'quantity-desc': { label: 'Quantity (high to low)', compare: (a, b) => (b.quantity ?? 0) - (a.quantity ?? 0) },
  },
  {
    category: {
      label: 'Category',
      getKeys: (p) => primaryCategoryKeys(p.item!.item_categories),
    },
    'stock-status': {
      label: 'Stock status',
      getKeys: (p) => [p.stock_status ? DB_TO_STOCK_STATUS[p.stock_status] : 'No status'],
    },
  },
)
groupBy.value = 'location'
const groupOptions = [{ value: 'location', label: 'Location' }, ...groupOptionsBase]

const groupedByLocation = computed(() => {
  const roomMap = new Map<string, Map<string, InventoryItem[]>>()
  for (const p of sortedInventoryItems.value) {
    const loc = primaryLocation(p)
    const roomLabel = loc ? loc.room?.name || 'Other' : p.inventory_item_rooms[0]?.room?.name ?? 'Unassigned'
    const locName = loc ? loc.name : 'No location set'
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
const selectedLocations = ref<Option[]>([])
const selectedRooms = ref<Option[]>([])
const selectedItem = ref<Option | null>(null)
const stockStatusLabel = ref<StockStatusLabel>('No status')
const quantity = ref<number | null>(null)
const unitId = ref<string | null>(null)
const notes = ref('')
const error = ref('')
const saving = ref(false)

watch(selectedLocations, (val) => {
  if (val.length > MAX_LOCATIONS) selectedLocations.value = val.slice(0, MAX_LOCATIONS)
})
watch(selectedRooms, (val) => {
  if (val.length > MAX_ROOMS) selectedRooms.value = val.slice(0, MAX_ROOMS)
})

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
  selectedLocations.value = []
  selectedRooms.value = []
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
  // match the shape/identity of locationOptionsForPicker's entries (which
  // carry a computed `label`) rather than the raw embed, so the multi-select
  // recognizes these as already-selected
  selectedLocations.value = p.inventory_item_locations.map((l) => {
    const loc = l.storage_location!
    return (
      locationOptionsForPicker.value.find((o) => o.id === loc.id) ?? {
        ...loc,
        label: loc.room ? `${loc.name} (${loc.room.name})` : loc.name,
      }
    )
  })
  selectedRooms.value = p.inventory_item_rooms.map((r) => r.room!)
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
    .insert({ space_id: space.value.id, name: capitalizeFirst(searchTerm) })
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
    item_id: selectedItem.value.id,
    kind: props.kind,
    stock_status: STOCK_STATUS_TO_DB[stockStatusLabel.value],
    quantity: quantity.value,
    unit_id: unitId.value,
    notes: notes.value.trim() || null,
  }

  let id = editingId.value
  if (id) {
    const { error: updateError } = await supabase.from('inventory_items').update(payload).eq('id', id)
    if (updateError) {
      saving.value = false
      error.value = updateError.message
      return
    }
    await supabase.from('inventory_item_locations').delete().eq('inventory_item_id', id)
    await supabase.from('inventory_item_rooms').delete().eq('inventory_item_id', id)
  } else {
    const { data, error: insertError } = await supabase
      .from('inventory_items')
      .insert(payload)
      .select('id')
      .single()
    if (insertError || !data) {
      saving.value = false
      error.value = insertError?.message ?? 'Failed to save'
      return
    }
    id = data.id
  }

  if (selectedLocations.value.length > 0) {
    await supabase.from('inventory_item_locations').insert(
      selectedLocations.value.map((l) => ({ inventory_item_id: id, storage_location_id: l.id })),
    )
  }
  if (selectedRooms.value.length > 0) {
    await supabase.from('inventory_item_rooms').insert(
      selectedRooms.value.map((r) => ({ inventory_item_id: id, room_id: r.id })),
    )
  }

  saving.value = false
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
        <label class="text-muted mb-1 block text-xs">Filter by category</label>
        <UInputMenu
          v-model="filterCategories"
          :items="categoryOptions ?? []"
          multiple
          label-key="name"
          placeholder="Any category"
          class="w-full"
        />
      </div>
      <div>
        <label class="text-muted mb-1 block text-xs">Filter by stock status</label>
        <UInputMenu
          v-model="filterStockStatuses"
          :items="STOCK_STATUS_LABELS"
          multiple
          placeholder="Any status"
          class="w-full"
        />
      </div>
    </div>

    <template v-if="groupBy === 'location'">
      <div v-for="group in groupedByLocation" :key="group.room" class="mb-6">
        <h2 class="mb-2 text-sm font-semibold text-muted">{{ group.room }}</h2>
        <div v-for="loc in group.locations" :key="loc.name" class="mb-4">
          <h3 class="mb-2 text-sm text-muted">{{ loc.name }}</h3>
          <ul class="flex flex-col gap-2">
            <li
              v-for="p in loc.items"
              :key="p.id"
              class="flex flex-col items-start justify-between gap-2 rounded border border-default px-3 py-2 sm:flex-row sm:items-center"
            >
              <div class="flex-1 cursor-pointer" @click="openEdit(p)">
                <span class="font-medium">{{ p.item!.name }}</span>
                <UBadge
                  v-for="ic in p.item!.item_categories"
                  :key="ic.categories!.id"
                  size="sm"
                  :variant="ic.categories!.parent_id ? 'subtle' : 'solid'"
                  class="ml-2 cursor-pointer"
                  :title="ic.is_primary ? 'Primary category (used for grouping)' : 'Click to make this the primary category'"
                  @click.stop="setPrimaryCategory(p.item!.id, ic.categories!.id)"
                >
                  <UIcon v-if="ic.is_primary" name="i-lucide-star" class="mr-1 size-3" />
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
                <UBadge
                  v-for="il in p.inventory_item_locations"
                  :key="il.storage_location!.id"
                  size="sm"
                  variant="outline"
                  class="ml-2"
                >
                  {{ il.storage_location!.name }}
                </UBadge>
                <UBadge
                  v-for="ir in p.inventory_item_rooms"
                  :key="ir.room!.id"
                  size="sm"
                  variant="outline"
                  class="ml-2"
                >
                  {{ ir.room!.name }}
                </UBadge>
                <p v-if="p.notes" class="text-muted text-xs">{{ p.notes }}</p>
              </div>
              <div class="flex flex-wrap items-center gap-1" @click.stop>
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
      <p v-if="groupedByLocation.length === 0" class="text-muted text-sm">{{ emptyLabel }}</p>
    </template>

    <template v-else-if="groupBy !== 'none'">
      <div v-for="[groupName, groupItems] in groupedByCategoryOrStock ?? []" :key="groupName" class="mb-6">
        <h2 class="mb-2 text-sm font-semibold text-muted">{{ groupName }}</h2>
        <ul class="flex flex-col gap-2">
          <li
            v-for="p in groupItems"
            :key="p.id"
            class="flex flex-col items-start justify-between gap-2 rounded border border-default px-3 py-2 sm:flex-row sm:items-center"
          >
            <div class="flex-1 cursor-pointer" @click="openEdit(p)">
              <span class="font-medium">{{ p.item!.name }}</span>
              <UBadge
                v-for="ic in p.item!.item_categories"
                :key="ic.categories!.id"
                size="sm"
                :variant="ic.categories!.parent_id ? 'subtle' : 'solid'"
                class="ml-2 cursor-pointer"
                :title="ic.is_primary ? 'Primary category (used for grouping)' : 'Click to make this the primary category'"
                @click.stop="setPrimaryCategory(p.item!.id, ic.categories!.id)"
              >
                <UIcon v-if="ic.is_primary" name="i-lucide-star" class="mr-1 size-3" />
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
              <UBadge
                v-for="il in p.inventory_item_locations"
                :key="il.storage_location!.id"
                size="sm"
                variant="outline"
                class="ml-2"
              >
                {{ il.storage_location!.name }}
              </UBadge>
              <UBadge
                v-for="ir in p.inventory_item_rooms"
                :key="ir.room!.id"
                size="sm"
                variant="outline"
                class="ml-2"
              >
                {{ ir.room!.name }}
              </UBadge>
              <p v-if="p.notes" class="text-muted text-xs">{{ p.notes }}</p>
            </div>
            <div class="flex flex-wrap items-center gap-1" @click.stop>
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
      <p v-if="(groupedByCategoryOrStock?.length ?? 0) === 0" class="text-muted text-sm">{{ emptyLabel }}</p>
    </template>

    <template v-else>
      <ul class="flex flex-col gap-2">
        <li
          v-for="p in sortedInventoryItems"
          :key="p.id"
          class="flex flex-col items-start justify-between gap-2 rounded border border-default px-3 py-2 sm:flex-row sm:items-center"
        >
          <div class="flex-1 cursor-pointer" @click="openEdit(p)">
            <span class="font-medium">{{ p.item!.name }}</span>
            <UBadge
              v-for="ic in p.item!.item_categories"
              :key="ic.categories!.id"
              size="sm"
              :variant="ic.categories!.parent_id ? 'subtle' : 'solid'"
              class="ml-2 cursor-pointer"
              :title="ic.is_primary ? 'Primary category (used for grouping)' : 'Click to make this the primary category'"
              @click.stop="setPrimaryCategory(p.item!.id, ic.categories!.id)"
            >
              <UIcon v-if="ic.is_primary" name="i-lucide-star" class="mr-1 size-3" />
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
            <UBadge
              v-for="il in p.inventory_item_locations"
              :key="il.storage_location!.id"
              size="sm"
              variant="outline"
              class="ml-2"
            >
              {{ il.storage_location!.name }}
            </UBadge>
            <UBadge
              v-for="ir in p.inventory_item_rooms"
              :key="ir.room!.id"
              size="sm"
              variant="outline"
              class="ml-2"
            >
              {{ ir.room!.name }}
            </UBadge>
            <p v-if="p.notes" class="text-muted text-xs">{{ p.notes }}</p>
          </div>
          <div class="flex flex-wrap items-center gap-1" @click.stop>
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
      <p v-if="sortedInventoryItems.length === 0" class="text-muted text-sm">{{ emptyLabel }}</p>
    </template>

    <USlideover v-model:open="slideoverOpen" :title="editingId ? 'Edit entry' : addLabel">
      <template #body>
        <form class="flex flex-col gap-4" @submit.prevent="save">
          <UFormField label="Item">
            <UInputMenu
              v-model="selectedItem"
              :items="itemOptions"
              create-item
              label-key="name"
              :filter-fields="ITEM_FILTER_FIELDS"
              class="w-full"
              @create="onCreateItemOption"
            />
          </UFormField>

          <div class="flex flex-col gap-2">
            <UFormField label="Locations" hint="Up to 2 (optional)">
              <UInputMenu
                v-model="selectedLocations"
                :items="locationOptionsForPicker"
                multiple
                label-key="label"
                class="w-full"
              />
            </UFormField>
            <UFormField label="Rooms" hint="Up to 2 (optional)">
              <UInputMenu
                v-model="selectedRooms"
                :items="roomOptions ?? []"
                multiple
                label-key="name"
                class="w-full"
              />
            </UFormField>
          </div>

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
