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
      id, name, plural_name, price, notes,
      item_categories(is_primary, is_primary_subcategory, categories(id, name, parent_id)),
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
  setPrimarySubcategory: setPrimarySubcategoryLink,
  setPrimaryTag: setPrimaryTagLink,
  primaryCategoryKeys,
  categoryAndSubcategoryKeys,
  parentCategoryNameFor,
  primaryTagKeys,
  syncPrimaryLinks,
} = useItemCategorization()

async function setPrimaryCategory(itemId: string, categoryId: string) {
  await setPrimaryCategoryLink(itemId, categoryId)
  await refresh()
}
async function setPrimarySubcategory(itemId: string, categoryId: string) {
  await setPrimarySubcategoryLink(itemId, categoryId)
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
    category_subcategory: {
      label: 'Category & Subcategory',
      getKeys: (item) => categoryAndSubcategoryKeys(item.item_categories),
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
function isSubcategoryId(categoryId: string) {
  return !!categoryOptions.value?.find((c) => c.id === categoryId)?.parent_id
}
function parentCategoryIdFor(categoryId: string): string | null {
  return categoryOptions.value?.find((c) => c.id === categoryId)?.parent_id ?? null
}

function groupParentName(groupName: string): string | null {
  if (groupBy.value !== 'category_subcategory') return null
  return parentCategoryNameFor(categoryOptions.value ?? [], groupName)
}

// Pin "Uncategorized" to the end of the list of groups
const displayGroups = computed(() => {
  const g = groupedItems.value
  if (!g) return g
  const uncategorizedIndex = g.findIndex(([groupName]) => groupName === 'Uncategorized')
  if (uncategorizedIndex === -1) return g
  const copy = [...g]
  const [uncategorized] = copy.splice(uncategorizedIndex, 1)
  copy.push(uncategorized!)
  return copy
})

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
const quickAdding = ref(false)
function openQuickAdd(groupName: string) {
  quickAddOpenFor.value = groupName
  quickAddName.value = ''
}
async function submitQuickAdd(groupName: string) {
  if (quickAdding.value) return // already in flight - ignore a second click/Enter
  if (!space.value || !quickAddName.value.trim()) return
  quickAdding.value = true
  try {
    const { data, error: insertError } = await supabase
      .from('items')
      .insert({ space_id: space.value.id, name: capitalizeFirst(quickAddName.value.trim()) })
      .select('id')
      .single()
    if (insertError || !data) return
    if (groupBy.value === 'category' || groupBy.value === 'category_subcategory') {
      const categoryId = categoryIdByName.value.get(groupName)
      // this is the first (and only) category/subcategory this item has -
      // it must be primary, or it'd fall straight back into "Uncategorized"
      // despite being quick-added into a named group
      if (categoryId) {
        const isSubcategory = isSubcategoryId(categoryId)
        const rows = [
          { item_id: data.id, category_id: categoryId, is_primary: !isSubcategory, is_primary_subcategory: isSubcategory },
        ]
        // when quick adding to a subcategory, link its parent too as the primary category
        const parentId = isSubcategory ? parentCategoryIdFor(categoryId) : null
        if (parentId) rows.push({ item_id: data.id, category_id: parentId, is_primary: true, is_primary_subcategory: false })
        await supabase.from('item_categories').insert(rows)
      }
    } else if (groupBy.value === 'tag') {
      const tagId = tagIdByName.value.get(groupName)
      if (tagId) await supabase.from('item_tags').insert({ item_id: data.id, tag_id: tagId, is_primary: true })
    }
  } finally {
    quickAdding.value = false
  }
  quickAddOpenFor.value = null
  quickAddName.value = ''
  await refresh()
}

function matchExistingItem(name: string) {
  const term = name.trim().toLowerCase()
  return items.value?.find((it) => it.name.toLowerCase() === term) ?? null
}

type QuickAddDraftRow = { name: string }
const quickAddBulkOpen = ref(false)
const quickAddBulkGroup = ref<string | null>(null)
const quickAddBulkRows = ref<QuickAddDraftRow[]>([])
const quickAddBulkSubmitting = ref(false)

function onQuickAddPaste(event: ClipboardEvent, groupName: string) {
  const lines = splitPastedLines(event.clipboardData?.getData('text/plain') ?? '')
  if (lines.length < 2) return // a single-line paste behaves exactly as before
  event.preventDefault()
  quickAddBulkGroup.value = groupName
  quickAddBulkRows.value = lines.map((name) => ({ name }))
  quickAddBulkOpen.value = true
}

// unlike the single quick-add, a pasted batch can easily include a name
// that already exists in the master list - items are unique by name per
// space, so reuse the existing item instead of trying (and failing) to
// insert a duplicate
async function submitQuickAddBulkReview() {
  if (quickAddBulkSubmitting.value) return // already in flight - ignore a second click
  const groupName = quickAddBulkGroup.value
  if (!groupName || !space.value) return
  const rows = quickAddBulkRows.value.filter((r) => r.name.trim())
  if (rows.length === 0) {
    quickAddBulkOpen.value = false
    return
  }

  quickAddBulkSubmitting.value = true
  try {
    for (const row of rows) {
      const name = row.name.trim()
      const existing = matchExistingItem(name)

      let itemId = existing?.id ?? null
      if (!itemId) {
        const { data } = await supabase
          .from('items')
          .insert({ space_id: space.value.id, name: capitalizeFirst(name) })
          .select('id')
          .single()
        if (!data) continue
        itemId = data.id
      }

      if (groupBy.value === 'category' || groupBy.value === 'category_subcategory') {
        const categoryId = categoryIdByName.value.get(groupName)
        if (!categoryId) continue
        const alreadyLinked = existing?.item_categories.some((ic) => ic.categories?.id === categoryId)
        if (alreadyLinked) continue
        const isSubcategory = isSubcategoryId(categoryId)
        // only becomes primary if this is the item's first category/subcategory
        // at that level - bulk-adding an already-categorized item into
        // another group shouldn't silently steal its existing primary grouping
        const existingOfSameLevel = existing?.item_categories.filter((ic) =>
          isSubcategory ? !!ic.categories?.parent_id : !ic.categories?.parent_id,
        )
        const isFirstOfLevel = !existingOfSameLevel || existingOfSameLevel.length === 0
        const rows = [
          {
            item_id: itemId,
            category_id: categoryId,
            is_primary: !isSubcategory && isFirstOfLevel,
            is_primary_subcategory: isSubcategory && isFirstOfLevel,
          },
        ]
        // when quick adding to a subcategory, link its parent too (unless already linked),
        // as the primary category if this item doesn't have one yet
        if (isSubcategory) {
          const parentId = parentCategoryIdFor(categoryId)
          const parentAlreadyLinked = existing?.item_categories.some((ic) => ic.categories?.id === parentId)
          if (parentId && !parentAlreadyLinked) {
            const hasMainCategory = existing?.item_categories.some((ic) => !ic.categories?.parent_id) ?? false
            rows.push({ item_id: itemId, category_id: parentId, is_primary: !hasMainCategory, is_primary_subcategory: false })
          }
        }
        await supabase.from('item_categories').insert(rows)
      } else if (groupBy.value === 'tag') {
        const tagId = tagIdByName.value.get(groupName)
        if (!tagId) continue
        const alreadyLinked = existing?.item_tags.some((it) => it.tags?.id === tagId)
        if (alreadyLinked) continue
        const isFirstTag = !existing || existing.item_tags.length === 0
        await supabase.from('item_tags').insert({ item_id: itemId, tag_id: tagId, is_primary: isFirstTag })
      }
    }
  } finally {
    quickAddBulkSubmitting.value = false
  }

  quickAddBulkOpen.value = false
  quickAddBulkRows.value = []
  quickAddBulkGroup.value = null
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
const notes = ref('')
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
const originalCategoryLinks = ref<{ id: string; parentId: string | null; is_primary: boolean }[]>([])
const originalTagLinks = ref<{ id: string; is_primary: boolean }[]>([])

function resetForm() {
  editingId.value = null
  name.value = ''
  pluralName.value = ''
  price.value = null
  notes.value = ''
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
  notes.value = item.notes ?? ''
  const linkedCategories = item.item_categories.map((ic) => ic.categories!)
  selectedCategories.value = linkedCategories.filter((c) => !c.parent_id)
  selectedSubcategories.value = linkedCategories.filter((c) => c.parent_id)
  defaultUnitId.value = item.default_unit?.id ?? null
  extraDefaultUnitOption.value = item.default_unit ?? null
  selectedUnits.value = item.item_units.map((iu) => iu.units!)
  selectedTags.value = item.item_tags.map((it) => ({ id: it.tags!.id, name: it.tags!.name }))
  originalCategoryLinks.value = item.item_categories.map((ic) => ({
    id: ic.categories!.id,
    parentId: ic.categories!.parent_id,
    is_primary: ic.categories!.parent_id ? ic.is_primary_subcategory : ic.is_primary,
  }))
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
  if (saving.value) return // already in flight - ignore a second click/Enter
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
    notes: notes.value.trim() || null,
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

  const prevMainLinks = originalCategoryLinks.value.filter((l) => !l.parentId)
  const prevSubLinks = originalCategoryLinks.value.filter((l) => l.parentId)
  await syncPrimaryLinks('item_categories', 'category_id', itemId, prevMainLinks, selectedCategories.value.map((c) => c.id))
  await syncPrimaryLinks(
    'item_categories',
    'category_id',
    itemId,
    prevSubLinks,
    selectedSubcategories.value.map((c) => c.id),
    'is_primary_subcategory',
  )
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

// --- bulk select / delete / edit category ---
const selectedIds = ref<Set<string>>(new Set())
function toggleSelected(id: string) {
  if (selectedIds.value.has(id)) selectedIds.value.delete(id)
  else selectedIds.value.add(id)
}
function clearSelection() {
  selectedIds.value.clear()
}

const bulkDeleting = ref(false)
async function bulkDelete() {
  if (bulkDeleting.value) return // already in flight - ignore a second click
  const ids = [...selectedIds.value]
  if (ids.length === 0) return
  bulkDeleting.value = true
  try {
    await supabase.from('items').update({ deleted_at: new Date().toISOString() }).in('id', ids)
  } finally {
    bulkDeleting.value = false
  }
  selectedIds.value.clear()
  await refresh()
}

const bulkEditCategoryOpen = ref(false)
const bulkCategories = ref<CategoryOption[]>([])
const bulkSubcategories = ref<CategoryOption[]>([])
const bulkEditSubmitting = ref(false)
const bulkEditResultMessage = ref('')

const bulkSubcategoryOptions = computed(() => {
  const parentIds = new Set(bulkCategories.value.map((c) => c.id))
  return categoryOptions.value?.filter((c) => c.parent_id && parentIds.has(c.parent_id)) ?? []
})

watch(bulkCategories, (val) => {
  if (val.length > MAX_CATEGORIES) {
    bulkCategories.value = val.slice(0, MAX_CATEGORIES)
    return
  }
  const parentIds = new Set(val.map((c) => c.id))
  bulkSubcategories.value = bulkSubcategories.value.filter((s) => s.parent_id && parentIds.has(s.parent_id))
})
watch(bulkSubcategories, (val) => {
  if (val.length > MAX_SUBCATEGORIES) {
    bulkSubcategories.value = val.slice(0, MAX_SUBCATEGORIES)
  }
})

function openBulkEditCategory() {
  bulkCategories.value = []
  bulkSubcategories.value = []
  bulkEditResultMessage.value = ''
  bulkEditCategoryOpen.value = true
}

// adds the picked categories/subcategories alongside whatever each
// selected item already has - never removes an existing link. Respects
// the same 2-category/2-subcategory cap as the individual edit form:
// an item already at the cap is left unchanged for that part rather than
// evicting one of its existing links to make room.
async function applyBulkCategory() {
  if (bulkEditSubmitting.value) return // already in flight - ignore a second click
  const ids = [...selectedIds.value]
  const toAddCategories = bulkCategories.value
  const toAddSubcategories = bulkSubcategories.value
  if (ids.length === 0 || (toAddCategories.length === 0 && toAddSubcategories.length === 0)) return

  bulkEditSubmitting.value = true
  let cappedCount = 0
  try {
    for (const itemId of ids) {
      const item = items.value?.find((it) => it.id === itemId)
      if (!item) continue

      const linkedIds = new Set(item.item_categories.map((ic) => ic.categories?.id))
      let categoryCount = item.item_categories.filter((ic) => !ic.categories?.parent_id).length
      let subcategoryCount = item.item_categories.filter((ic) => ic.categories?.parent_id).length
      let mainPrimaryAssigned = categoryCount > 0
      let subPrimaryAssigned = subcategoryCount > 0
      let wasCapped = false

      for (const cat of toAddCategories) {
        if (linkedIds.has(cat.id)) continue
        if (categoryCount >= MAX_CATEGORIES) {
          wasCapped = true
          continue
        }
        const isPrimary = !mainPrimaryAssigned
        await supabase.from('item_categories').insert({ item_id: itemId, category_id: cat.id, is_primary: isPrimary })
        if (isPrimary) mainPrimaryAssigned = true
        categoryCount++
        linkedIds.add(cat.id)
      }
      for (const sub of toAddSubcategories) {
        if (linkedIds.has(sub.id)) continue
        if (subcategoryCount >= MAX_SUBCATEGORIES) {
          wasCapped = true
          continue
        }
        const isPrimary = !subPrimaryAssigned
        await supabase
          .from('item_categories')
          .insert({ item_id: itemId, category_id: sub.id, is_primary_subcategory: isPrimary })
        if (isPrimary) subPrimaryAssigned = true
        subcategoryCount++
        linkedIds.add(sub.id)
      }
      if (wasCapped) cappedCount++
    }
  } finally {
    bulkEditSubmitting.value = false
  }

  selectedIds.value.clear()
  await refresh()

  if (cappedCount > 0) {
    bulkEditResultMessage.value = `Done, but ${cappedCount} item${cappedCount === 1 ? ' was' : 's were'} already at the category/subcategory limit and left unchanged for those.`
  } else {
    bulkEditCategoryOpen.value = false
  }
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

    <div
      v-if="selectedIds.size > 0"
      class="sticky top-0 z-10 mb-4 flex items-center gap-2 rounded border border-default bg-default p-2 shadow-sm"
    >
      <span class="text-sm">{{ selectedIds.size }} selected</span>
      <UButton size="sm" variant="outline" @click="openBulkEditCategory">Edit category</UButton>
      <UButton size="sm" variant="outline" color="error" :loading="bulkDeleting" @click="bulkDelete">Delete</UButton>
      <UButton size="sm" variant="ghost" @click="clearSelection">Clear</UButton>
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
      <div v-for="[groupName, groupItems] in displayGroups" :key="groupName" class="mb-4">
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
            <div>
              <p v-if="groupParentName(groupName)" class="text-muted text-xs leading-tight">
                {{ groupParentName(groupName) }}
              </p>
              <h2
                class="font-semibold text-muted"
                :class="groupParentName(groupName) ? 'border-default border-l-2 pl-2 text-sm' : 'text-base'"
              >
                {{ groupName }}
              </h2>
            </div>
          </button>
          <UButton
            v-if="groupBy === 'category' || groupBy === 'category_subcategory' || groupBy === 'tag'"
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
          @paste="onQuickAddPaste($event, groupName)"
        >
          <UInput v-model="quickAddName" :disabled="quickAdding" autofocus placeholder="Item name" class="flex-1" />
          <UButton type="submit" size="sm" :loading="quickAdding">Add</UButton>
          <UButton size="sm" variant="ghost" :disabled="quickAdding" @click="quickAddOpenFor = null">Cancel</UButton>
        </form>
        <ul v-if="isGroupExpanded(groupName)" class="flex flex-col gap-2">
          <li
            v-for="item in groupItems"
            :key="item.id"
            class="flex cursor-pointer items-center justify-between rounded border border-default px-3 py-2"
            @click="openEdit(item)"
          >
            <div class="flex items-center gap-2">
              <UCheckbox
                :model-value="selectedIds.has(item.id)"
                @click.stop
                @update:model-value="toggleSelected(item.id)"
              />
              <div>
                <span class="font-medium">{{ item.name }}</span>
                <span v-if="item.price != null" class="text-muted ml-2 text-sm">${{ item.price }}</span>
                <UBadge
                  v-for="ic in item.item_categories.filter((c) => !c.categories?.parent_id)"
                  :key="ic.categories!.id"
                  size="sm"
                  color="primary"
                  variant="solid"
                  class="ml-2 cursor-pointer"
                  :title="ic.is_primary ? 'Primary category (used for grouping)' : 'Click to make this the primary category'"
                  @click.stop="setPrimaryCategory(item.id, ic.categories!.id)"
                >
                  <UIcon v-if="ic.is_primary" name="i-lucide-star" class="mr-1 size-3" />
                  {{ ic.categories!.name }}
                </UBadge>
                <UBadge
                  v-for="ic in item.item_categories.filter((c) => c.categories?.parent_id)"
                  :key="ic.categories!.id"
                  size="sm"
                  color="warning"
                  variant="subtle"
                  class="ml-2 cursor-pointer"
                  :title="
                    ic.is_primary_subcategory
                      ? 'Primary subcategory (used for grouping)'
                      : 'Click to make this the primary subcategory'
                  "
                  @click.stop="setPrimarySubcategory(item.id, ic.categories!.id)"
                >
                  <UIcon v-if="ic.is_primary_subcategory" name="i-lucide-star" class="mr-1 size-3" />
                  {{ ic.categories!.name }}
                </UBadge>
                <UBadge
                  v-for="t in item.item_tags"
                  :key="t.tags!.id"
                  size="sm"
                  color="neutral"
                  variant="outline"
                  class="ml-2 cursor-pointer"
                  :title="t.is_primary ? 'Primary tag (used for grouping)' : 'Click to make this the primary tag'"
                  @click.stop="setPrimaryTag(item.id, t.tags!.id)"
                >
                  <UIcon v-if="t.is_primary" name="i-lucide-star" class="mr-1 size-3" />
                  {{ t.tags!.name }}
                </UBadge>
                <p v-if="item.notes" class="text-muted mt-1 text-sm">{{ item.notes }}</p>
              </div>
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
        <div class="flex items-center gap-2">
          <UCheckbox
            :model-value="selectedIds.has(item.id)"
            @click.stop
            @update:model-value="toggleSelected(item.id)"
          />
          <div>
            <span class="font-medium">{{ item.name }}</span>
            <span v-if="item.price != null" class="text-muted ml-2 text-sm">${{ item.price }}</span>
            <UBadge
              v-for="ic in item.item_categories.filter((c) => !c.categories?.parent_id)"
              :key="ic.categories!.id"
              size="sm"
              color="primary"
              variant="solid"
              class="ml-2 cursor-pointer"
              :title="ic.is_primary ? 'Primary category (used for grouping)' : 'Click to make this the primary category'"
              @click.stop="setPrimaryCategory(item.id, ic.categories!.id)"
            >
              <UIcon v-if="ic.is_primary" name="i-lucide-star" class="mr-1 size-3" />
              {{ ic.categories!.name }}
            </UBadge>
            <UBadge
              v-for="ic in item.item_categories.filter((c) => c.categories?.parent_id)"
              :key="ic.categories!.id"
              size="sm"
              color="warning"
              variant="subtle"
              class="ml-2 cursor-pointer"
              :title="
                ic.is_primary_subcategory
                  ? 'Primary subcategory (used for grouping)'
                  : 'Click to make this the primary subcategory'
              "
              @click.stop="setPrimarySubcategory(item.id, ic.categories!.id)"
            >
              <UIcon v-if="ic.is_primary_subcategory" name="i-lucide-star" class="mr-1 size-3" />
              {{ ic.categories!.name }}
            </UBadge>
            <UBadge
              v-for="t in item.item_tags"
              :key="t.tags!.id"
              size="sm"
              color="neutral"
              variant="outline"
              class="ml-2 cursor-pointer"
              :title="t.is_primary ? 'Primary tag (used for grouping)' : 'Click to make this the primary tag'"
              @click.stop="setPrimaryTag(item.id, t.tags!.id)"
            >
              <UIcon v-if="t.is_primary" name="i-lucide-star" class="mr-1 size-3" />
              {{ t.tags!.name }}
            </UBadge>
            <p v-if="item.notes" class="text-muted mt-1 text-sm">{{ item.notes }}</p>
          </div>
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

          <UFormField label="Notes" hint="Optional">
            <UInput v-model="notes" placeholder="Notes" class="w-full" />
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

    <UModal v-model:open="quickAddBulkOpen" title="Review pasted items" :dismissible="!quickAddBulkSubmitting">
      <template #body>
        <div class="flex flex-col gap-2">
          <div v-for="(row, i) in quickAddBulkRows" :key="i" class="flex items-center gap-2">
            <UInput v-model="row.name" :disabled="quickAddBulkSubmitting" class="flex-1" />
            <UBadge v-if="matchExistingItem(row.name)" color="success" variant="subtle">Already in master list</UBadge>
            <UBadge v-else variant="outline">New item</UBadge>
            <UButton
              size="sm"
              variant="ghost"
              icon="i-lucide-x"
              :disabled="quickAddBulkSubmitting"
              @click="quickAddBulkRows.splice(i, 1)"
            />
          </div>
          <p v-if="quickAddBulkRows.length === 0" class="text-muted text-sm">No items left to add.</p>
          <div class="mt-2 flex gap-2">
            <UButton
              :disabled="quickAddBulkRows.length === 0"
              :loading="quickAddBulkSubmitting"
              @click="submitQuickAddBulkReview"
            >
              Add {{ quickAddBulkRows.length }} item{{ quickAddBulkRows.length === 1 ? '' : 's' }}
            </UButton>
            <UButton variant="ghost" :disabled="quickAddBulkSubmitting" @click="quickAddBulkOpen = false">
              Cancel
            </UButton>
          </div>
        </div>
      </template>
    </UModal>

    <UModal v-model:open="bulkEditCategoryOpen" title="Edit category" :dismissible="!bulkEditSubmitting">
      <template #body>
        <div class="flex flex-col gap-3">
          <p class="text-muted text-sm">
            Applying to {{ selectedIds.size }} item{{ selectedIds.size === 1 ? '' : 's' }}. Categories are added
            alongside each item's existing ones - nothing is removed.
          </p>
          <UFormField label="Categories" hint="Up to 2">
            <UInputMenu
              v-model="bulkCategories"
              :items="topLevelCategoryOptions"
              multiple
              label-key="name"
              :disabled="bulkEditSubmitting"
              class="w-full"
            />
          </UFormField>
          <UFormField label="Subcategories" hint="Up to 2">
            <UInputMenu
              v-model="bulkSubcategories"
              :items="bulkSubcategoryOptions"
              multiple
              label-key="name"
              placeholder="Pick a category first"
              :disabled="bulkEditSubmitting"
              class="w-full"
            />
          </UFormField>
          <p v-if="bulkEditResultMessage" class="text-sm text-amber-600">{{ bulkEditResultMessage }}</p>
          <div class="flex gap-2">
            <UButton
              :disabled="bulkCategories.length === 0 && bulkSubcategories.length === 0"
              :loading="bulkEditSubmitting"
              @click="applyBulkCategory"
            >
              Apply
            </UButton>
            <UButton variant="ghost" :disabled="bulkEditSubmitting" @click="bulkEditCategoryOpen = false">
              {{ bulkEditResultMessage ? 'Done' : 'Cancel' }}
            </UButton>
          </div>
        </div>
      </template>
    </UModal>
  </div>
</template>
