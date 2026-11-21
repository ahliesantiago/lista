<script setup lang="ts">
import draggable from 'vuedraggable'
import type { TreeGroupBy, TreeSortBy } from '~/composables/useGroupedItemTree'

type Option = { id: string; name: string; plural_name?: string | null }
type ItemOption = Option & {
  item_categories: { is_primary: boolean; categories: { id: string; name: string; parent_id: string | null } | null }[]
  item_tags: { is_primary: boolean; tags: { id: string; name: string } | null }[]
}
type CategoryOption = { id: string; name: string; parent_id: string | null }
type UnitOption = {
  id: string
  name_singular: string
  name_plural: string
  abbrev_singular: string | null
  abbrev_plural: string | null
}
const UNIT_FILTER_FIELDS = ['name_singular', 'name_plural', 'abbrev_singular', 'abbrev_plural']

const route = useRoute()
const listId = route.params.id as string

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: list } = await useAsyncData(`list-${listId}`, async () => {
  const { data, error } = await supabase
    .from('lists')
    .select(`
      id, name, description, notes, status, move_done_to_bottom, list_type,
      list_categories(categories(id, name, parent_id)),
      list_tags(tags(id, name))
    `)
    .eq('id', listId)
    .is('deleted_at', null)
    .single()
  if (error) throw error
  return data
})

const pageEntityName = usePageEntityName()
watchEffect(() => {
  pageEntityName.value = list.value?.name ?? null
})
onUnmounted(() => {
  pageEntityName.value = null
})

const { data: listItems } = await useAsyncData(`list-items-${listId}`, async () => {
  const { data, error } = await supabase
    .from('list_items')
    .select(`
      id, name, amount, size, notes, is_done, item_id, parent_id, sort_order,
      unit:units!list_items_unit_id_fkey(id, name_singular, name_plural),
      list_item_sources(quantity, unit:units(name_singular, name_plural), recipe:recipes(id, name)),
      item:items(item_categories(is_primary, categories(id, name, parent_id)), item_tags(is_primary, tags(id, name)))
    `)
    .eq('list_id', listId)
    .is('deleted_at', null)
    .order('created_at')
  if (error) throw error
  return data
})

type ListItemRow = NonNullable<typeof listItems.value>[number]
type ListItemNode = ListItemRow & { children: ListItemRow[] }

function buildItemTree(all: ListItemRow[]) {
  const byId = new Map(all.map((i) => [i.id, i]))
  const hasValidParent = (item: ListItemRow) => {
    if (!item.parent_id) return false
    const parent = byId.get(item.parent_id)
    return !!parent && !parent.parent_id
  }
  const hadInvalidChain = all.some((i) => i.parent_id && !hasValidParent(i))
  const topLevel = all.filter((i) => !hasValidParent(i)).sort((a, b) => a.sort_order - b.sort_order)
  const tree: ListItemNode[] = topLevel.map((parent) => ({
    ...parent,
    children: all
      .filter((c) => hasValidParent(c) && c.parent_id === parent.id)
      .sort((a, b) => a.sort_order - b.sort_order),
  }))
  return { tree, hadInvalidChain }
}

const itemTree = ref<ListItemNode[]>([])

let itemOrderPersistQueue: Promise<unknown> = Promise.resolve()
function persistItemOrder() {
  itemOrderPersistQueue = itemOrderPersistQueue.then(async () => {
    const updates: Promise<unknown>[] = []
    itemTree.value.forEach((parent, i) => {
      updates.push(supabase.from('list_items').update({ sort_order: i, parent_id: null }).eq('id', parent.id))
      parent.children.forEach((child, j) => {
        updates.push(supabase.from('list_items').update({ sort_order: j, parent_id: parent.id }).eq('id', child.id))
      })
    })
    await Promise.all(updates)
  })
}

{
  const { tree, hadInvalidChain } = buildItemTree(listItems.value ?? [])
  itemTree.value = tree
  if (hadInvalidChain) persistItemOrder()
}

function findItem(id: string): { item: ListItemNode | ListItemRow; parent: ListItemNode | null } | null {
  const topIndex = itemTree.value.findIndex((p) => p.id === id)
  if (topIndex !== -1) return { item: itemTree.value[topIndex]!, parent: null }
  for (const parent of itemTree.value) {
    const child = parent.children.find((c) => c.id === id)
    if (child) return { item: child, parent }
  }
  return null
}

function onItemTreeChange() {
  persistItemOrder()
}

// findItem is keyed by a list_item's own id and returns one node - not
// reusable here, since the same master item_id can appear on multiple
// list_item rows (added twice, or as both a parent and elsewhere)
function forEachNodeWithItem(itemId: string, fn: (node: ListItemNode | ListItemRow) => void) {
  for (const parent of itemTree.value) {
    if (parent.item_id === itemId) fn(parent)
    for (const child of parent.children) {
      if (child.item_id === itemId) fn(child)
    }
  }
}

const { setPrimaryCategory: setPrimaryCategoryLink, setPrimaryTag: setPrimaryTagLink } = useItemCategorization()

function setPrimaryCategory(itemId: string | null, categoryId: string) {
  if (!itemId) return
  setPrimaryCategoryLink(itemId, categoryId)
  forEachNodeWithItem(itemId, (node) => {
    if (!node.item) return
    node.item.item_categories = node.item.item_categories.map((ic) => ({
      ...ic,
      is_primary: ic.categories?.id === categoryId,
    }))
  })
}

function setPrimaryTag(itemId: string | null, tagId: string) {
  if (!itemId) return
  setPrimaryTagLink(itemId, tagId)
  forEachNodeWithItem(itemId, (node) => {
    if (!node.item) return
    node.item.item_tags = node.item.item_tags.map((it) => ({ ...it, is_primary: it.tags?.id === tagId }))
  })
}

function indentItem(id: string) {
  const index = itemTree.value.findIndex((p) => p.id === id)
  if (index <= 0) return // nothing to nest under
  const item = itemTree.value[index]!
  if (item.children.length > 0) return // would push its own children to depth 3
  const [removed] = itemTree.value.splice(index, 1)
  itemTree.value[index - 1]!.children.push(removed as ListItemRow)
  persistItemOrder()
}

function outdentItem(id: string, parentId: string) {
  const parentIndex = itemTree.value.findIndex((p) => p.id === parentId)
  if (parentIndex === -1) return
  const parent = itemTree.value[parentIndex]!
  const childIndex = parent.children.findIndex((c) => c.id === id)
  if (childIndex === -1) return
  const [child] = parent.children.splice(childIndex, 1)
  itemTree.value.splice(parentIndex + 1, 0, { ...child!, children: [] })
  persistItemOrder()
}

// --- display: sort / group / done-to-bottom ---

const sortByOptions = [
  { value: 'custom', label: 'Custom order' },
  { value: 'name-asc', label: 'Name (A–Z)' },
]
const groupByOptions = [
  { value: 'none', label: 'None' },
  { value: 'category', label: 'Category' },
  { value: 'tag', label: 'Tag' },
]
const sortBy = ref<TreeSortBy>('custom')
const groupBy = ref<TreeGroupBy>('none')
const moveDoneToBottom = ref(list.value?.move_done_to_bottom ?? false)
watch(moveDoneToBottom, (v) => saveListField({ move_done_to_bottom: v }))

const { groupedTree, flatSortedTree } = useGroupedItemTree(itemTree, sortBy, groupBy, moveDoneToBottom)

// bullet/numbered lists have no sort/group/done-to-bottom UI at all (see
// addPlainItem below) - they're always in live drag order, so this only
// ever falls through to the grouped/flat read-only branches for checklist
const isLiveCustomOrder = computed(
  () =>
    list.value?.list_type !== 'checklist' ||
    (sortBy.value === 'custom' && groupBy.value === 'none' && !moveDoneToBottom.value),
)

// markers for bullet/numbered rows - top-level numbers, lettered children
// (a classic outline convention), computed from the item's own position
function markerFor(index: number, depth: 0 | 1): string | null {
  if (list.value?.list_type === 'bullet') return depth === 0 ? '•' : '◦'
  if (list.value?.list_type === 'numbered') {
    return depth === 0 ? `${index + 1}.` : `${String.fromCharCode(97 + index)}.`
  }
  return null
}

const { data: itemOptionsInitial } = await useAsyncData('item-options', async () => {
  const { data, error } = await supabase
    .from('items')
    .select(
      'id, name, plural_name, item_categories(is_primary, categories(id, name, parent_id)), item_tags(is_primary, tags(id, name))',
    )
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data
})
const itemOptions = ref<ItemOption[]>(itemOptionsInitial.value ?? [])

const { data: unitOptions } = await useAsyncData('unit-options', async () => {
  const { data, error } = await supabase
    .from('units')
    .select('id, name_singular, name_plural, abbrev_singular, abbrev_plural')
    .is('deleted_at', null)
    .order('name_singular')
  if (error) throw error
  return data as UnitOption[]
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

const tagOptions = ref<Option[]>([])
const { data: tagOptionsInitial } = await useAsyncData('tag-options', async () => {
  const { data, error } = await supabase.from('tags').select('id, name').is('deleted_at', null).order('name')
  if (error) throw error
  return data
})
tagOptions.value = tagOptionsInitial.value ?? []

// --- editable header: name/description/notes/category/tags ---

const name = ref(list.value?.name ?? '')
const description = ref(list.value?.description ?? '')
const notes = ref(list.value?.notes ?? '')

const viewMode = ref<'view' | 'edit'>(route.query.new === '1' ? 'edit' : 'view')

const linkedCategories = list.value?.list_categories.map((lc) => lc.categories!) ?? []
const MAX_CATEGORIES = 2
const MAX_SUBCATEGORIES = 2
const selectedCategories = ref<CategoryOption[]>(linkedCategories.filter((c) => !c.parent_id))
const selectedSubcategories = ref<CategoryOption[]>(linkedCategories.filter((c) => c.parent_id))
const listTags = ref<Option[]>(list.value?.list_tags.map((lt) => lt.tags!) ?? [])

const subcategoryOptions = computed(() => {
  const parentIds = new Set(selectedCategories.value.map((c) => c.id))
  return categoryOptions.value?.filter((c) => c.parent_id && parentIds.has(c.parent_id)) ?? []
})

async function saveListField(patch: Record<string, unknown>) {
  await supabase.from('lists').update(patch).eq('id', listId)
}

watch(selectedCategories, async (newVal, oldVal) => {
  if (newVal.length > MAX_CATEGORIES) {
    selectedCategories.value = newVal.slice(0, MAX_CATEGORIES)
    return
  }
  const parentIds = new Set(newVal.map((c) => c.id))
  selectedSubcategories.value = selectedSubcategories.value.filter(
    (s) => s.parent_id && parentIds.has(s.parent_id),
  )
  const added = newVal.filter((c) => !oldVal.some((o) => o.id === c.id))
  const removed = oldVal.filter((o) => !newVal.some((c) => c.id === o.id))
  if (added.length > 0) {
    await supabase.from('list_categories').insert(added.map((c) => ({ list_id: listId, category_id: c.id })))
  }
  for (const r of removed) {
    await supabase.from('list_categories').delete().eq('list_id', listId).eq('category_id', r.id)
  }
})

watch(selectedSubcategories, async (newVal, oldVal) => {
  if (newVal.length > MAX_SUBCATEGORIES) {
    selectedSubcategories.value = newVal.slice(0, MAX_SUBCATEGORIES)
    return
  }
  const added = newVal.filter((c) => !oldVal.some((o) => o.id === c.id))
  const removed = oldVal.filter((o) => !newVal.some((c) => c.id === o.id))
  if (added.length > 0) {
    await supabase.from('list_categories').insert(added.map((c) => ({ list_id: listId, category_id: c.id })))
  }
  for (const r of removed) {
    await supabase.from('list_categories').delete().eq('list_id', listId).eq('category_id', r.id)
  }
})

watch(listTags, async (newVal, oldVal) => {
  const added = newVal.filter((t) => !oldVal.some((o) => o.id === t.id))
  const removed = oldVal.filter((o) => !newVal.some((t) => t.id === o.id))
  if (added.length > 0) {
    await supabase.from('list_tags').insert(added.map((t) => ({ list_id: listId, tag_id: t.id })))
  }
  for (const r of removed) {
    await supabase.from('list_tags').delete().eq('list_id', listId).eq('tag_id', r.id)
  }
})

const { onCreateCategoryOption, onCreateSubcategoryOption } = useCategoryCreation(
  'categories',
  space,
  categoryOptions,
  selectedCategories,
  selectedSubcategories,
)

async function onCreateListTag(searchTerm: string) {
  if (!space.value) return
  const { data, error: insertError } = await supabase
    .from('tags')
    .insert({ space_id: space.value.id, name: searchTerm })
    .select('id, name')
    .single()
  if (insertError || !data) return
  tagOptions.value.push(data)
  listTags.value.push(data)
}

// --- add item ---

const selectedItem = ref<Option | null>(null)
const itemPickerKey = ref(0)
const addToMasterList = ref(true)
const amount = ref<number | null>(null)
const unitId = ref<string | null>(null)
const size = ref('')
const itemNotes = ref('')
const error = ref('')
const adding = ref(false)

const unitOptionsForAmount = computed(
  () =>
    unitOptions.value?.map((u) => ({
      ...u,
      label: amount.value != null && amount.value !== 1 ? u.name_plural : u.name_singular,
    })) ?? [],
)
// the list item can stay linked to a trashed unit (soft delete never
// touches the link); without this, re-opening it for edit would have no
// live option to resolve a label from and fall back to showing the raw id.
const extraEditUnitOption = ref<{ id: string; name_singular: string; name_plural: string } | null>(null)

const { resolveItem } = useResolveMasterItem()

async function addItem() {
  if (!space.value || !selectedItem.value || !selectedItem.value.name.trim()) return

  error.value = ''
  adding.value = true

  const { itemId, name: resolvedName } = await resolveItem(
    space.value.id,
    selectedItem.value,
    addToMasterList.value,
    itemOptions,
  )

  if (itemId && unitId.value) {
    await supabase
      .from('item_units')
      .upsert({ item_id: itemId, unit_id: unitId.value }, { ignoreDuplicates: true })
  }

  const amountValue = amount.value
  const unitIdValue = unitId.value
  const sizeValue = size.value.trim() || null
  const notesValue = itemNotes.value.trim() || null

  const { data: newRow, error: insertError } = await supabase
    .from('list_items')
    .insert({
      list_id: listId,
      item_id: itemId,
      name: resolvedName,
      amount: amountValue,
      unit_id: unitIdValue,
      size: sizeValue,
      notes: notesValue,
      parent_id: null,
      sort_order: itemTree.value.length,
    })
    .select('id')
    .single()

  adding.value = false
  if (insertError || !newRow) {
    error.value = insertError?.message ?? 'Failed to add item'
    return
  }

  const unitMatch = unitIdValue ? unitOptions.value?.find((u) => u.id === unitIdValue) ?? null : null
  // a brand-new item (just created via "add to master list") has no
  // category/tag links yet - the option resolveItem() pushes only has
  // {id, name}, so these default to [] rather than crashing on undefined
  const optionMatch = itemId ? itemOptions.value.find((o) => o.id === itemId) : null
  itemTree.value.push({
    id: newRow.id,
    name: resolvedName,
    amount: amountValue,
    size: sizeValue,
    notes: notesValue,
    is_done: false,
    item_id: itemId,
    parent_id: null,
    sort_order: itemTree.value.length,
    unit: unitMatch ? { id: unitMatch.id, name_singular: unitMatch.name_singular, name_plural: unitMatch.name_plural } : null,
    list_item_sources: [],
    item: { item_categories: optionMatch?.item_categories ?? [], item_tags: optionMatch?.item_tags ?? [] },
    children: [],
  })

  selectedItem.value = null
  amount.value = null
  unitId.value = null
  size.value = ''
  itemNotes.value = ''
  // force the item picker to remount: its internal search text doesn't
  // reliably clear just from setting the external v-model to null,
  // especially after the create-new-item path.
  itemPickerKey.value++
}

const plainItemName = ref('')

// bullet/numbered items are never linked to the master item table at all -
// no resolveItem(), no item_units, no amount/unit/size
async function addPlainItem() {
  if (!plainItemName.value.trim()) return
  error.value = ''
  adding.value = true

  const nameValue = plainItemName.value.trim()
  const { data: newRow, error: insertError } = await supabase
    .from('list_items')
    .insert({ list_id: listId, item_id: null, name: nameValue, parent_id: null, sort_order: itemTree.value.length })
    .select('id')
    .single()

  adding.value = false
  if (insertError || !newRow) {
    error.value = insertError?.message ?? 'Failed to add item'
    return
  }

  itemTree.value.push({
    id: newRow.id,
    name: nameValue,
    amount: null,
    size: null,
    notes: null,
    is_done: false,
    item_id: null,
    parent_id: null,
    sort_order: itemTree.value.length,
    unit: null,
    list_item_sources: [],
    item: null,
    children: [],
  })
  plainItemName.value = ''
}

async function toggleDone(id: string, isDone: boolean) {
  await supabase.from('list_items').update({ is_done: !isDone }).eq('id', id)
  const found = findItem(id)
  if (found) found.item.is_done = !isDone
}

async function checkAll(done: boolean) {
  await supabase.from('list_items').update({ is_done: done }).eq('list_id', listId)
  for (const parent of itemTree.value) {
    parent.is_done = done
    for (const child of parent.children) child.is_done = done
  }
}

async function removeItem(id: string) {
  const deletedAt = new Date().toISOString()
  await supabase.from('list_items').update({ deleted_at: deletedAt }).eq('id', id)
  // mirrors deleteList()'s cascade to list_items - a removed parent's
  // children would otherwise be left dangling, invisible under a hidden row
  await supabase.from('list_items').update({ deleted_at: deletedAt }).eq('parent_id', id).is('deleted_at', null)

  const topIndex = itemTree.value.findIndex((p) => p.id === id)
  if (topIndex !== -1) {
    // removing the whole parent node removes its children array with it,
    // matching the DB cascade above - no separate splice needed for them
    itemTree.value.splice(topIndex, 1)
    return
  }
  for (const parent of itemTree.value) {
    const childIndex = parent.children.findIndex((c) => c.id === id)
    if (childIndex !== -1) {
      parent.children.splice(childIndex, 1)
      break
    }
  }
}

// --- edit item inline ---

type EditDraft = {
  name: string
  isListOnly: boolean
  amount: number | null
  unitId: string | null
  size: string
  notes: string
}

const editingItemId = ref<string | null>(null)
const editDraft = ref<EditDraft | null>(null)

function startEdit(li: NonNullable<typeof listItems.value>[number]) {
  editingItemId.value = li.id
  editDraft.value = {
    name: li.name,
    isListOnly: !li.item_id,
    amount: li.amount,
    unitId: li.unit?.id ?? null,
    size: li.size ?? '',
    notes: li.notes ?? '',
  }
  extraEditUnitOption.value = li.unit ?? null
}

function cancelEdit() {
  editingItemId.value = null
  editDraft.value = null
}

async function saveEdit(id: string) {
  const draft = editDraft.value
  if (!draft) return
  const sizeValue = draft.size.trim() || null
  const notesValue = draft.notes.trim() || null
  await supabase
    .from('list_items')
    .update({
      ...(draft.isListOnly ? { name: draft.name.trim() } : {}),
      amount: draft.amount,
      unit_id: draft.unitId,
      size: sizeValue,
      notes: notesValue,
    })
    .eq('id', id)

  const found = findItem(id)
  if (found) {
    if (draft.isListOnly) found.item.name = draft.name.trim()
    found.item.amount = draft.amount
    found.item.size = sizeValue
    found.item.notes = notesValue
    const unitMatch = draft.unitId
      ? (unitOptions.value?.find((u) => u.id === draft.unitId) ?? extraEditUnitOption.value)
      : null
    found.item.unit = unitMatch
      ? { id: unitMatch.id, name_singular: unitMatch.name_singular, name_plural: unitMatch.name_plural }
      : null
  }
  editingItemId.value = null
  editDraft.value = null
}

// --- list-level actions ---

async function setStatus(status: 'active' | 'archived') {
  await saveListField({ status })
  await navigateTo('/lists')
}

async function deleteList() {
  const deletedAt = new Date().toISOString()
  await supabase.from('lists').update({ deleted_at: deletedAt }).eq('id', listId)
  await supabase.from('list_items').update({ deleted_at: deletedAt }).eq('list_id', listId).is('deleted_at', null)
  await navigateTo('/lists')
}
</script>

<template>
  <div v-if="list" class="mx-auto max-w-2xl">
    <div class="mb-4 flex flex-col items-start justify-between gap-4 sm:flex-row">
      <div v-if="viewMode === 'view'" class="flex-1">
        <h1 class="mb-1 text-lg font-semibold">{{ list.name }}</h1>
        <p v-if="list.description" class="text-muted mb-2 text-sm">{{ list.description }}</p>
        <p v-if="list.notes && list.list_type !== 'note'" class="text-muted mb-2 text-sm">{{ list.notes }}</p>
        <p v-if="list.list_type === 'note' && list.notes" class="mb-2 whitespace-pre-wrap">{{ list.notes }}</p>
        <div class="flex flex-wrap gap-1">
          <UBadge v-for="c in selectedCategories" :key="c.id" size="sm" variant="solid">{{ c.name }}</UBadge>
          <UBadge v-for="c in selectedSubcategories" :key="c.id" size="sm" variant="subtle">{{ c.name }}</UBadge>
          <UBadge v-for="t in listTags" :key="t.id" size="sm" variant="outline">{{ t.name }}</UBadge>
        </div>
      </div>
      <div v-else class="flex-1">
        <UInput
          v-model="name"
          class="mb-2 w-full text-lg font-semibold"
          @blur="saveListField({ name })"
        />
        <UTextarea
          v-model="description"
          placeholder="Description (optional)"
          class="mb-2 w-full"
          @blur="saveListField({ description: description || null })"
        />
        <UTextarea
          v-if="list.list_type === 'note'"
          v-model="notes"
          placeholder="Write your note..."
          :rows="12"
          class="mb-2 w-full"
          @blur="saveListField({ notes: notes || null })"
        />
        <UInput
          v-else
          v-model="notes"
          placeholder="Notes (optional)"
          class="mb-2 w-full"
          @blur="saveListField({ notes: notes || null })"
        />
        <div class="mb-2 flex gap-2">
          <UFormField label="Categories" hint="Up to 2 (optional)" class="flex-1">
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
          <UFormField label="Subcategories" hint="Up to 2 (optional)" class="flex-1">
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
        </div>
        <UFormField label="Tags" hint="Optional">
          <UInputMenu
            v-model="listTags"
            :items="tagOptions"
            multiple
            create-item
            label-key="name"
            class="w-full"
            @create="onCreateListTag"
          />
        </UFormField>
      </div>
      <div class="flex shrink-0 flex-wrap items-center gap-2">
        <UButton size="sm" variant="outline" @click="viewMode = viewMode === 'view' ? 'edit' : 'view'">
          {{ viewMode === 'view' ? 'Edit' : 'Done editing' }}
        </UButton>
        <UButton v-if="list.status === 'active'" size="sm" variant="outline" @click="setStatus('archived')">
          Archive
        </UButton>
        <UButton v-else size="sm" variant="outline" @click="setStatus('active')">Unarchive</UButton>
        <UButton size="sm" variant="outline" color="error" @click="deleteList">Delete list</UButton>
      </div>
    </div>

    <template v-if="list.list_type !== 'note'">
    <div v-if="list.list_type === 'checklist'" class="mb-4 flex gap-2">
      <UButton size="sm" variant="ghost" @click="checkAll(true)">Check all</UButton>
      <UButton size="sm" variant="ghost" @click="checkAll(false)">Uncheck all</UButton>
    </div>

    <template v-if="list.list_type === 'checklist'">
    <div class="mb-4 grid grid-cols-1 gap-2 sm:grid-cols-3">
      <div>
        <label class="text-muted mb-1 block text-xs">Sort by</label>
        <USelect v-model="sortBy" :items="sortByOptions" class="w-full" />
      </div>
      <div>
        <label class="text-muted mb-1 block text-xs">Group by</label>
        <USelect v-model="groupBy" :items="groupByOptions" class="w-full" />
      </div>
      <div class="flex items-end">
        <USwitch v-model="moveDoneToBottom" label="Move crossed-off items to the bottom" />
      </div>
    </div>
    <p v-if="!isLiveCustomOrder && sortBy === 'custom'" class="text-muted mb-4 text-xs">
      Drag-and-drop reordering and nesting are only available with custom order, no grouping, and crossed-off items kept in place.
    </p>
    </template>

    <form
      v-if="viewMode === 'edit' && list.list_type === 'checklist'"
      class="mb-6 flex flex-col gap-2 rounded border border-default p-3"
      @submit.prevent="addItem"
    >
      <ItemMasterListField
        :key="itemPickerKey"
        v-model:item="selectedItem"
        v-model:add-to-master-list="addToMasterList"
        :item-options="itemOptions"
      />
      <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <UInputNumber v-model="amount" placeholder="Qty" :min="0" />
        <USelectMenu
          v-model="unitId"
          :items="unitOptionsForAmount"
          value-key="id"
          label-key="label"
          :filter-fields="UNIT_FILTER_FIELDS"
          placeholder="Unit"
        />
        <UInput v-model="size" placeholder="Size" />
      </div>
      <UInput v-model="itemNotes" placeholder="Notes (optional)" />
      <p v-if="error" class="text-sm text-red-500">{{ error }}</p>
      <UButton type="submit" :loading="adding">Add item</UButton>
    </form>

    <form
      v-if="viewMode === 'edit' && list.list_type !== 'checklist'"
      class="mb-6 flex gap-2"
      @submit.prevent="addPlainItem"
    >
      <UInput v-model="plainItemName" placeholder="New item" class="flex-1" />
      <UButton type="submit" :loading="adding">Add</UButton>
    </form>

    <template v-if="isLiveCustomOrder">
      <draggable
        v-model="itemTree"
        item-key="id"
        tag="ul"
        class="flex flex-col gap-2"
        handle=".drag-handle"
        :disabled="viewMode !== 'edit'"
        @change="onItemTreeChange"
      >
        <template #item="{ element: li }">
          <li>
            <ListItemRow
              :item="li"
              :variant="list.list_type === 'checklist' ? 'checklist' : 'plain'"
              :marker="markerFor(itemTree.indexOf(li), 0)"
              :nest-button="viewMode === 'edit' && itemTree.indexOf(li) > 0 && li.children.length === 0 ? 'indent' : null"
              :reorderable="viewMode === 'edit'"
              :editable="viewMode === 'edit'"
              :editing-id="editingItemId"
              v-model:draft="editDraft"
              :unit-options="list.list_type === 'checklist' ? (unitOptions ?? []) : []"
              :extra-edit-unit-option="list.list_type === 'checklist' ? extraEditUnitOption : null"
              @toggle-done="toggleDone(li.id, li.is_done)"
              @start-edit="startEdit(li)"
              @cancel-edit="cancelEdit"
              @save-edit="saveEdit(li.id)"
              @remove="removeItem(li.id)"
              @nest="indentItem(li.id)"
              @switch-category="(categoryId) => setPrimaryCategory(li.item_id, categoryId)"
              @switch-tag="(tagId) => setPrimaryTag(li.item_id, tagId)"
            />
            <draggable
              v-if="li.children.length > 0"
              v-model="li.children"
              item-key="id"
              tag="ul"
              class="ml-6 mt-2 flex flex-col gap-2"
              handle=".drag-handle"
              :disabled="viewMode !== 'edit'"
              @change="onItemTreeChange"
            >
              <template #item="{ element: child }">
                <li>
                  <ListItemRow
                    :item="child"
                    :variant="list.list_type === 'checklist' ? 'checklist' : 'plain'"
                    :marker="markerFor(li.children.indexOf(child), 1)"
                    :nest-button="viewMode === 'edit' ? 'outdent' : null"
                    :reorderable="viewMode === 'edit'"
                    :editable="viewMode === 'edit'"
                    :editing-id="editingItemId"
                    v-model:draft="editDraft"
                    :unit-options="list.list_type === 'checklist' ? (unitOptions ?? []) : []"
                    :extra-edit-unit-option="list.list_type === 'checklist' ? extraEditUnitOption : null"
                    @toggle-done="toggleDone(child.id, child.is_done)"
                    @start-edit="startEdit(child)"
                    @cancel-edit="cancelEdit"
                    @save-edit="saveEdit(child.id)"
                    @remove="removeItem(child.id)"
                    @nest="outdentItem(child.id, li.id)"
                    @switch-category="(categoryId) => setPrimaryCategory(child.item_id, categoryId)"
                    @switch-tag="(tagId) => setPrimaryTag(child.item_id, tagId)"
                  />
                </li>
              </template>
            </draggable>
          </li>
        </template>
      </draggable>
    </template>
    <template v-else-if="groupedTree">
      <div v-for="[groupName, nodes] in groupedTree" :key="groupName" class="mb-4">
        <h2 class="mb-2 text-sm font-semibold text-muted">{{ groupName }}</h2>
        <ul class="flex flex-col gap-2">
          <li v-for="node in nodes" :key="node.id">
            <ListItemRow
              :item="node"
              variant="checklist"
              :marker="null"
              :nest-button="null"
              :reorderable="false"
              :editable="viewMode === 'edit'"
              :editing-id="editingItemId"
              v-model:draft="editDraft"
              :unit-options="unitOptions ?? []"
              :extra-edit-unit-option="extraEditUnitOption"
              @toggle-done="toggleDone(node.id, node.is_done)"
              @start-edit="startEdit(node)"
              @cancel-edit="cancelEdit"
              @save-edit="saveEdit(node.id)"
              @remove="removeItem(node.id)"
              @switch-category="(categoryId) => setPrimaryCategory(node.item_id, categoryId)"
              @switch-tag="(tagId) => setPrimaryTag(node.item_id, tagId)"
            />
            <ul v-if="node.children.length > 0" class="ml-6 mt-2 flex flex-col gap-2">
              <li v-for="child in node.children" :key="child.id">
                <ListItemRow
                  :item="child"
                  variant="checklist"
                  :marker="null"
                  :nest-button="null"
                  :reorderable="false"
                  :editable="viewMode === 'edit'"
                  :editing-id="editingItemId"
                  v-model:draft="editDraft"
                  :unit-options="unitOptions ?? []"
                  :extra-edit-unit-option="extraEditUnitOption"
                  @toggle-done="toggleDone(child.id, child.is_done)"
                  @start-edit="startEdit(child)"
                  @cancel-edit="cancelEdit"
                  @save-edit="saveEdit(child.id)"
                  @remove="removeItem(child.id)"
                  @switch-category="(categoryId) => setPrimaryCategory(child.item_id, categoryId)"
                  @switch-tag="(tagId) => setPrimaryTag(child.item_id, tagId)"
                />
              </li>
            </ul>
          </li>
        </ul>
      </div>
    </template>
    <ul v-else class="flex flex-col gap-2">
      <li v-for="node in flatSortedTree" :key="node.id">
        <ListItemRow
          :item="node"
          variant="checklist"
          :marker="null"
          :nest-button="null"
          :reorderable="false"
          :editable="viewMode === 'edit'"
          :editing-id="editingItemId"
          v-model:draft="editDraft"
          :unit-options="unitOptions ?? []"
          :extra-edit-unit-option="extraEditUnitOption"
          @toggle-done="toggleDone(node.id, node.is_done)"
          @start-edit="startEdit(node)"
          @cancel-edit="cancelEdit"
          @save-edit="saveEdit(node.id)"
          @remove="removeItem(node.id)"
          @switch-category="(categoryId) => setPrimaryCategory(node.item_id, categoryId)"
          @switch-tag="(tagId) => setPrimaryTag(node.item_id, tagId)"
        />
        <ul v-if="node.children.length > 0" class="ml-6 mt-2 flex flex-col gap-2">
          <li v-for="child in node.children" :key="child.id">
            <ListItemRow
              :item="child"
              variant="checklist"
              :marker="null"
              :nest-button="null"
              :reorderable="false"
              :editable="viewMode === 'edit'"
              :editing-id="editingItemId"
              v-model:draft="editDraft"
              :unit-options="unitOptions ?? []"
              :extra-edit-unit-option="extraEditUnitOption"
              @toggle-done="toggleDone(child.id, child.is_done)"
              @start-edit="startEdit(child)"
              @cancel-edit="cancelEdit"
              @save-edit="saveEdit(child.id)"
              @remove="removeItem(child.id)"
              @switch-category="(categoryId) => setPrimaryCategory(child.item_id, categoryId)"
              @switch-tag="(tagId) => setPrimaryTag(child.item_id, tagId)"
            />
          </li>
        </ul>
      </li>
    </ul>
    <p v-if="itemTree.length === 0" class="text-muted text-sm">No items yet.</p>
    </template>
  </div>
</template>
