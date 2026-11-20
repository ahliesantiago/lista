<script setup lang="ts">
type Option = { id: string; name: string }
type CategoryOption = { id: string; name: string; parent_id: string | null }
type UnitOption = {
  id: string
  name_singular: string
  name_plural: string
  abbrev_singular: string | null
  abbrev_plural: string | null
}
const UNIT_FILTER_FIELDS = ['name_singular', 'name_plural', 'abbrev_singular', 'abbrev_plural']
const MAX_CATEGORIES = 2
const MAX_SUBCATEGORIES = 2

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: items, error: itemsError, refresh } = await useAsyncData('items', async () => {
  const { data, error } = await supabase
    .from('items')
    .select(`
      id, name, plural_name, price,
      item_categories(is_primary, categories(id, name, parent_id)),
      default_unit:units!items_default_unit_id_fkey(id, name_singular),
      item_tags(is_primary, tags(id, name)),
      item_units(units(id, name_singular, name_plural, abbrev_singular, abbrev_plural))
    `)
    .is('deleted_at', null)
    .order('name')
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
const topLevelCategoryOptions = computed(() => categoryOptions.value?.filter((c) => !c.parent_id) ?? [])

const { data: unitOptions } = await useAsyncData('unit-options', async () => {
  const { data, error } = await supabase
    .from('units')
    .select('id, name_singular, name_plural, abbrev_singular, abbrev_plural')
    .is('deleted_at', null)
    .order('name_singular')
  if (error) throw error
  return data as UnitOption[]
})

const tagOptions = ref<Option[]>([])
const { data: tagOptionsInitial } = await useAsyncData('tag-options', async () => {
  const { data, error } = await supabase
    .from('tags')
    .select('id, name')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data
})
tagOptions.value = tagOptionsInitial.value ?? []

const filterCategories = ref<CategoryOption[]>([])
const filterTags = ref<Option[]>([])
const searchTerm = ref('')

type ItemRow = NonNullable<typeof items.value>[number]

const filteredItems = computed(() => {
  let list = items.value ?? []
  if (searchTerm.value.trim()) {
    const term = searchTerm.value.trim().toLowerCase()
    list = list.filter(
      (item) => item.name.toLowerCase().includes(term) || item.plural_name?.toLowerCase().includes(term),
    )
  }
  if (filterCategories.value.length > 0) {
    const ids = new Set(filterCategories.value.map((c) => c.id))
    list = list.filter((item) => item.item_categories.some((ic) => ids.has(ic.categories!.id)))
  }
  if (filterTags.value.length > 0) {
    const ids = new Set(filterTags.value.map((t) => t.id))
    list = list.filter((item) => item.item_tags.some((it) => ids.has(it.tags!.id)))
  }
  return list
})

const {
  setPrimaryCategory: setPrimaryCategoryLink,
  setPrimaryTag: setPrimaryTagLink,
  primaryCategoryKeys,
  primaryTagKeys,
  syncPrimaryLinks,
} = useItemCategorization()

async function setPrimaryCategory(itemId: string, categoryId: string) {
  await setPrimaryCategoryLink(itemId, categoryId)
  await refresh()
}
async function setPrimaryTag(itemId: string, tagId: string) {
  await setPrimaryTagLink(itemId, tagId)
  await refresh()
}

const { sortBy, groupBy, sortOptions, groupOptions, sortedItems, groupedItems } = useListControls<ItemRow>(
  filteredItems,
  {
    'name-asc': { label: 'Name (A–Z)', compare: (a, b) => a.name.localeCompare(b.name) },
    'name-desc': { label: 'Name (Z–A)', compare: (a, b) => b.name.localeCompare(a.name) },
    'price-asc': { label: 'Price (low to high)', compare: (a, b) => (a.price ?? Infinity) - (b.price ?? Infinity) },
    'price-desc': {
      label: 'Price (high to low)',
      compare: (a, b) => (b.price ?? -Infinity) - (a.price ?? -Infinity),
    },
  },
  {
    category: {
      label: 'Category',
      getKeys: (item) => primaryCategoryKeys(item.item_categories),
    },
    tag: {
      label: 'Tag',
      getKeys: (item) => primaryTagKeys(item.item_tags),
    },
  },
)
groupBy.value = 'category'

// group buckets are keyed by name (not id) - categories/tags are unique
// per space by name, so this is an unambiguous name->id lookup for
// quick-add to know which category/tag a given group heading maps to
const categoryIdByName = computed(() => new Map((categoryOptions.value ?? []).map((c) => [c.name, c.id])))
const tagIdByName = computed(() => new Map(tagOptions.value.map((t) => [t.name, t.id])))

// groups default expanded (unlike Trash's collapse-by-default) - the
// Masterlist's whole point is browsing/finding items, so hiding content
// by default would work against that
const collapsedGroups = ref<Record<string, boolean>>({})
function isGroupExpanded(groupName: string) {
  return !collapsedGroups.value[groupName]
}
function toggleGroup(groupName: string) {
  collapsedGroups.value[groupName] = !collapsedGroups.value[groupName]
}
function expandAllGroups() {
  collapsedGroups.value = {}
}
function collapseAllGroups() {
  const all: Record<string, boolean> = {}
  for (const [groupName] of groupedItems.value ?? []) all[groupName] = true
  collapsedGroups.value = all
}

const quickAddOpenFor = ref<string | null>(null)
const quickAddName = ref('')
function openQuickAdd(groupName: string) {
  quickAddOpenFor.value = groupName
  quickAddName.value = ''
}
async function submitQuickAdd(groupName: string) {
  if (!space.value || !quickAddName.value.trim()) return
  const { data, error: insertError } = await supabase
    .from('items')
    .insert({ space_id: space.value.id, name: capitalizeFirst(quickAddName.value.trim()) })
    .select('id')
    .single()
  if (insertError || !data) return
  if (groupBy.value === 'category') {
    const categoryId = categoryIdByName.value.get(groupName)
    // this is the first (and only) category this item has - it must be
    // primary, or it'd fall straight back into "Uncategorized" despite
    // being quick-added into a named group
    if (categoryId) {
      await supabase.from('item_categories').insert({ item_id: data.id, category_id: categoryId, is_primary: true })
    }
  } else if (groupBy.value === 'tag') {
    const tagId = tagIdByName.value.get(groupName)
    if (tagId) await supabase.from('item_tags').insert({ item_id: data.id, tag_id: tagId, is_primary: true })
  }
  quickAddOpenFor.value = null
  quickAddName.value = ''
  await refresh()
}

const slideoverOpen = ref(false)
const editingId = ref<string | null>(null)

// the floating create button (CreateFab, in the layout) hides itself while
// this is true - only the create case counts (not editing). useState
// persists across navigation, so reset on unmount too - otherwise
// navigating away while the slideover is open would leave the FAB hidden forever.
const createFormOpen = useCreateFormOpen()
watch([slideoverOpen, editingId], ([open, id]) => {
  createFormOpen.value = open && !id
})
onUnmounted(() => {
  createFormOpen.value = false
})

const name = ref('')
const pluralName = ref('')
const price = ref<number | null>(null)
const selectedCategories = ref<CategoryOption[]>([])
const selectedSubcategories = ref<CategoryOption[]>([])
const defaultUnitId = ref<string | null>(null)
const selectedUnits = ref<UnitOption[]>([])
const selectedTags = ref<Option[]>([])
const error = ref('')
const saving = ref(false)

const extraDefaultUnitOption = ref<{ id: string; name_singular: string } | null>(null)
const defaultUnitOptionsForForm = computed(() => {
  const base = unitOptions.value ?? []
  const extra = extraDefaultUnitOption.value
  return extra && !base.some((u) => u.id === extra.id) ? [...base, extra] : base
})

// a default unit should always be one of the allowed units too, so picking
// one adds it to Allowed Units automatically if it isn't there already
watch(defaultUnitId, (val) => {
  if (!val || selectedUnits.value.some((u) => u.id === val)) return
  const unit = unitOptions.value?.find((u) => u.id === val)
  if (unit) selectedUnits.value.push(unit)
})

const subcategoryOptions = computed(() => {
  const parentIds = new Set(selectedCategories.value.map((c) => c.id))
  return categoryOptions.value?.filter((c) => c.parent_id && parentIds.has(c.parent_id)) ?? []
})

watch(selectedCategories, (val) => {
  if (val.length > MAX_CATEGORIES) {
    selectedCategories.value = val.slice(0, MAX_CATEGORIES)
    return
  }
  const parentIds = new Set(val.map((c) => c.id))
  selectedSubcategories.value = selectedSubcategories.value.filter(
    (s) => s.parent_id && parentIds.has(s.parent_id),
  )
})

watch(selectedSubcategories, (val) => {
  if (val.length > MAX_SUBCATEGORIES) {
    selectedSubcategories.value = val.slice(0, MAX_SUBCATEGORIES)
  }
})

const { onCreateCategoryOption, onCreateSubcategoryOption } = useCategoryCreation(
  'categories',
  space,
  categoryOptions,
  selectedCategories,
  selectedSubcategories,
)

// kept separate from the picker-bound selectedCategories/selectedSubcategories/
// selectedTags (which only ever hold plain {id,name} option objects) so
// is_primary doesn't leak into the UInputMenu chip/create-item flow - these
// exist purely so save() has the "before" state to diff against
const originalCategoryLinks = ref<{ id: string; is_primary: boolean }[]>([])
const originalTagLinks = ref<{ id: string; is_primary: boolean }[]>([])

function resetForm() {
  editingId.value = null
  name.value = ''
  pluralName.value = ''
  price.value = null
  selectedCategories.value = []
  selectedSubcategories.value = []
  defaultUnitId.value = null
  selectedUnits.value = []
  selectedTags.value = []
  extraDefaultUnitOption.value = null
  originalCategoryLinks.value = []
  originalTagLinks.value = []
  error.value = ''
}

function openCreate() {
  resetForm()
  slideoverOpen.value = true
}

// the floating create button's "Item" option navigates here with ?new=1,
// same convention already used for a fresh list/recipe's own detail page
const route = useRoute()
if (route.query.new === '1') openCreate()

function openEdit(item: NonNullable<typeof items.value>[number]) {
  editingId.value = item.id
  name.value = item.name
  pluralName.value = item.plural_name ?? ''
  price.value = item.price
  const linkedCategories = item.item_categories.map((ic) => ic.categories!)
  selectedCategories.value = linkedCategories.filter((c) => !c.parent_id)
  selectedSubcategories.value = linkedCategories.filter((c) => c.parent_id)
  defaultUnitId.value = item.default_unit?.id ?? null
  extraDefaultUnitOption.value = item.default_unit ?? null
  selectedUnits.value = item.item_units.map((iu) => iu.units!)
  selectedTags.value = item.item_tags.map((it) => ({ id: it.tags!.id, name: it.tags!.name }))
  originalCategoryLinks.value = item.item_categories.map((ic) => ({ id: ic.categories!.id, is_primary: ic.is_primary }))
  originalTagLinks.value = item.item_tags.map((it) => ({ id: it.tags!.id, is_primary: it.is_primary }))
  error.value = ''
  slideoverOpen.value = true
}

async function onCreateTag(searchTerm: string) {
  if (!space.value) return
  const { data, error: insertError } = await supabase
    .from('tags')
    .insert({ space_id: space.value.id, name: searchTerm })
    .select('id, name')
    .single()
  if (insertError || !data) return
  tagOptions.value.push(data)
  selectedTags.value.push(data)
}

async function save() {
  if (!space.value) return
  error.value = ''
  saving.value = true

  const isNew = !editingId.value
  const payload = {
    space_id: space.value.id,
    name: isNew ? capitalizeFirst(name.value.trim()) : name.value.trim(),
    plural_name: pluralName.value.trim() || null,
    default_unit_id: defaultUnitId.value,
    price: price.value,
  }

  let itemId = editingId.value
  if (itemId) {
    const { error: updateError } = await supabase.from('items').update(payload).eq('id', itemId)
    if (updateError) {
      saving.value = false
      error.value = updateError.message
      return
    }
    await supabase.from('item_units').delete().eq('item_id', itemId)
  } else {
    const { data, error: insertError } = await supabase.from('items').insert(payload).select('id').single()
    if (insertError || !data) {
      saving.value = false
      error.value = insertError?.message ?? 'Failed to create item'
      return
    }
    itemId = data.id
  }

  if (selectedUnits.value.length > 0) {
    await supabase.from('item_units').insert(selectedUnits.value.map((u) => ({ item_id: itemId, unit_id: u.id })))
  }

  const allCategoryIds = [...selectedCategories.value, ...selectedSubcategories.value].map((c) => c.id)
  await syncPrimaryLinks('item_categories', 'category_id', itemId, originalCategoryLinks.value, allCategoryIds)
  await syncPrimaryLinks('item_tags', 'tag_id', itemId, originalTagLinks.value, selectedTags.value.map((t) => t.id))

  saving.value = false
  slideoverOpen.value = false
  await refresh()
}

async function deleteItem(id: string) {
  // soft delete only: anything referencing this item keeps the link intact,
  // so restoring it from Trash brings the link right back. Permanently
  // deleting it (a real DELETE, from the Trash page) is what triggers the
  // FK's on-delete-set-null, not this.
  await supabase.from('items').update({ deleted_at: new Date().toISOString() }).eq('id', id)
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <div class="mb-4 flex justify-between">
      <h1 class="text-lg font-semibold">Masterlist</h1>
      <UButton icon="i-lucide-plus" @click="openCreate">Add item</UButton>
    </div>

    <p v-if="itemsError" class="mb-4 text-sm text-red-500">{{ itemsError.message }}</p>

    <UInput
      v-model="searchTerm"
      icon="i-lucide-search"
      placeholder="Search items"
      class="mb-4 w-full"
    />

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
        <label class="text-muted mb-1 block text-xs">Filter by tag</label>
        <UInputMenu
          v-model="filterTags"
          :items="tagOptions"
          multiple
          label-key="name"
          placeholder="Any tag"
          class="w-full"
        />
      </div>
    </div>

    <template v-if="groupedItems">
      <div v-if="groupedItems.length > 0" class="mb-4 flex gap-2">
        <UButton size="sm" variant="ghost" @click="expandAllGroups">Expand all</UButton>
        <UButton size="sm" variant="ghost" @click="collapseAllGroups">Collapse all</UButton>
      </div>
      <div v-for="[groupName, groupItems] in groupedItems" :key="groupName" class="mb-4">
        <div class="mb-2 flex items-center justify-between gap-2">
          <button
            type="button"
            class="flex flex-1 items-center gap-1 text-left"
            @click="toggleGroup(groupName)"
          >
            <UIcon
              :name="isGroupExpanded(groupName) ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'"
              class="size-4 text-muted"
            />
            <h2 class="text-sm font-semibold text-muted">{{ groupName }}</h2>
          </button>
          <UButton
            v-if="groupBy === 'category' || groupBy === 'tag'"
            size="sm"
            variant="ghost"
            icon="i-lucide-plus"
            :title="`Quick add to ${groupName}`"
            @click="openQuickAdd(groupName)"
          />
        </div>
        <form
          v-if="quickAddOpenFor === groupName"
          class="mb-2 flex gap-2"
          @submit.prevent="submitQuickAdd(groupName)"
        >
          <UInput v-model="quickAddName" autofocus placeholder="Item name" class="flex-1" />
          <UButton type="submit" size="sm">Add</UButton>
          <UButton size="sm" variant="ghost" @click="quickAddOpenFor = null">Cancel</UButton>
        </form>
        <ul v-if="isGroupExpanded(groupName)" class="flex flex-col gap-2">
          <li
            v-for="item in groupItems"
            :key="item.id"
            class="flex cursor-pointer items-center justify-between rounded border border-default px-3 py-2"
            @click="openEdit(item)"
          >
            <div>
              <span class="font-medium">{{ item.name }}</span>
              <span v-if="item.price != null" class="text-muted ml-2 text-sm">${{ item.price }}</span>
              <UBadge
                v-for="ic in item.item_categories"
                :key="ic.categories!.id"
                size="sm"
                :variant="ic.categories!.parent_id ? 'subtle' : 'solid'"
                class="ml-2 cursor-pointer"
                :title="ic.is_primary ? 'Primary category (used for grouping)' : 'Click to make this the primary category'"
                @click.stop="setPrimaryCategory(item.id, ic.categories!.id)"
              >
                <UIcon v-if="ic.is_primary" name="i-lucide-star" class="mr-1 size-3" />
                {{ ic.categories!.name }}
              </UBadge>
              <UBadge
                v-for="t in item.item_tags"
                :key="t.tags!.id"
                size="sm"
                variant="outline"
                class="ml-2 cursor-pointer"
                :title="t.is_primary ? 'Primary tag (used for grouping)' : 'Click to make this the primary tag'"
                @click.stop="setPrimaryTag(item.id, t.tags!.id)"
              >
                <UIcon v-if="t.is_primary" name="i-lucide-star" class="mr-1 size-3" />
                {{ t.tags!.name }}
              </UBadge>
            </div>
            <UButton
              size="sm"
              variant="ghost"
              color="error"
              icon="i-lucide-trash-2"
              @click.stop="deleteItem(item.id)"
            />
          </li>
        </ul>
      </div>
      <p v-if="groupedItems.length === 0" class="text-muted text-sm">No items match.</p>
    </template>

    <ul v-else class="flex flex-col gap-2">
      <li
        v-for="item in sortedItems"
        :key="item.id"
        class="flex cursor-pointer items-center justify-between rounded border border-default px-3 py-2"
        @click="openEdit(item)"
      >
        <div>
          <span class="font-medium">{{ item.name }}</span>
          <span v-if="item.price != null" class="text-muted ml-2 text-sm">${{ item.price }}</span>
          <UBadge
            v-for="ic in item.item_categories"
            :key="ic.categories!.id"
            size="sm"
            :variant="ic.categories!.parent_id ? 'subtle' : 'solid'"
            class="ml-2 cursor-pointer"
            :title="ic.is_primary ? 'Primary category (used for grouping)' : 'Click to make this the primary category'"
            @click.stop="setPrimaryCategory(item.id, ic.categories!.id)"
          >
            <UIcon v-if="ic.is_primary" name="i-lucide-star" class="mr-1 size-3" />
            {{ ic.categories!.name }}
          </UBadge>
          <UBadge
            v-for="t in item.item_tags"
            :key="t.tags!.id"
            size="sm"
            variant="outline"
            class="ml-2 cursor-pointer"
            :title="t.is_primary ? 'Primary tag (used for grouping)' : 'Click to make this the primary tag'"
            @click.stop="setPrimaryTag(item.id, t.tags!.id)"
          >
            <UIcon v-if="t.is_primary" name="i-lucide-star" class="mr-1 size-3" />
            {{ t.tags!.name }}
          </UBadge>
        </div>
        <UButton
          size="sm"
          variant="ghost"
          color="error"
          icon="i-lucide-trash-2"
          @click.stop="deleteItem(item.id)"
        />
      </li>
      <li v-if="sortedItems.length === 0" class="text-muted text-sm">No items match.</li>
    </ul>

    <USlideover v-model:open="slideoverOpen" :title="editingId ? 'Edit item' : 'Add item'">
      <template #body>
        <form class="flex flex-col gap-4" @submit.prevent="save">
          <UFormField label="Name">
            <UInput v-model="name" required class="w-full" />
          </UFormField>

          <UFormField label="Plural Name" hint="Optional">
            <UInput v-model="pluralName" class="w-full" />
          </UFormField>

          <UFormField label="Categories" hint="Optional, up to 2">
            <UInputMenu
              v-model="selectedCategories"
              :items="topLevelCategoryOptions"
              multiple
              create-item
              label-key="name"
              class="w-full"
              @create="onCreateCategoryOption"
            />
          </UFormField>

          <UFormField label="Subcategories" hint="Optional, up to 2">
            <UInputMenu
              v-model="selectedSubcategories"
              :items="subcategoryOptions"
              multiple
              create-item
              label-key="name"
              placeholder="Pick a category first"
              class="w-full"
              @create="onCreateSubcategoryOption"
            />
          </UFormField>

          <UFormField label="Price" hint="Optional">
            <UInputNumber v-model="price" :min="0" class="w-full" />
          </UFormField>

          <UFormField label="Default Unit" hint="Optional">
            <div class="flex items-center gap-2">
              <UInputMenu
                v-model="defaultUnitId"
                :items="defaultUnitOptionsForForm"
                value-key="id"
                label-key="name_singular"
                :filter-fields="UNIT_FILTER_FIELDS"
                class="w-full flex-1"
              />
              <UButton
                v-if="defaultUnitId"
                size="sm"
                variant="ghost"
                icon="i-lucide-x"
                @click="defaultUnitId = null"
              />
            </div>
          </UFormField>

          <UFormField label="Allowed Units" hint="Optional">
            <UInputMenu
              v-model="selectedUnits"
              :items="unitOptions ?? []"
              multiple
              label-key="name_singular"
              :filter-fields="UNIT_FILTER_FIELDS"
              class="w-full"
            />
          </UFormField>

          <UFormField label="Tags" hint="Optional">
            <UInputMenu
              v-model="selectedTags"
              :items="tagOptions"
              multiple
              create-item
              label-key="name"
              class="w-full"
              @create="onCreateTag"
            />
          </UFormField>

          <p v-if="error" class="text-sm text-red-500">{{ error }}</p>

          <UButton type="submit" block :loading="saving">{{ editingId ? 'Save' : 'Add item' }}</UButton>
        </form>
      </template>
    </USlideover>
  </div>
</template>
