<script setup lang="ts">
import draggable from 'vuedraggable'

type Option = { id: string; name: string; plural_name?: string | null }
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
      id, name, description, notes, status,
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
      list_item_sources(quantity, unit:units(name_singular, name_plural), recipe:recipes(id, name))
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

const isDragging = ref(false)
const draggedItemId = ref<string | null>(null)
function onDragStart(evt: { item: HTMLElement }) {
  isDragging.value = true
  draggedItemId.value = evt.item.dataset.id ?? null
}
function onDragEnd() {
  isDragging.value = false
  draggedItemId.value = null
}

// blocks dropping a parent-with-children into another parent's child zone -
// without this, that single drag would silently create 3 levels of nesting
// (the moved item's own children would become grandchildren)
function checkMove(evt: { to: HTMLElement; draggedContext: { element: ListItemNode | ListItemRow } }) {
  const dragged = evt.draggedContext.element as ListItemNode
  if (dragged.children && dragged.children.length > 0) return false
  // an item's own children zone sits directly below its own row, so it's
  // physically possible to drag an item a few pixels into its own zone -
  // block that specifically, or it'd become its own parent
  if (evt.to.dataset.parentId === dragged.id) return false
  return true
}

const { data: itemOptionsInitial } = await useAsyncData('item-options', async () => {
  const { data, error } = await supabase
    .from('items')
    .select('id, name, plural_name')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data
})
const itemOptions = ref<Option[]>(itemOptionsInitial.value ?? [])

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

function unitLabel(unit: { name_singular: string; name_plural: string } | null, amount: number | null) {
  if (!unit) return ''
  return amount != null && amount !== 1 ? unit.name_plural : unit.name_singular
}

function sourcesLabel(
  sources: { quantity: number | null; unit: { name_singular: string; name_plural: string } | null; recipe: { name: string } | null }[],
) {
  const withRecipe = sources.filter((s) => s.recipe)
  if (withRecipe.length === 0) return ''
  return withRecipe
    .map((s) => {
      const qty = s.quantity != null ? `${s.quantity} ${unitLabel(s.unit, s.quantity)}`.trim() : ''
      return `${qty ? qty + ' ' : ''}from ${s.recipe!.name}`
    })
    .join(', ')
}

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
const editUnitOptionsForAmount = computed(() => {
  const label = (u: { name_singular: string; name_plural: string }) =>
    editAmount.value != null && editAmount.value !== 1 ? u.name_plural : u.name_singular
  const base = unitOptions.value?.map((u) => ({ ...u, label: label(u) })) ?? []
  const extra = extraEditUnitOption.value
  if (extra && !base.some((u) => u.id === extra.id)) {
    return [...base, { ...extra, abbrev_singular: null, abbrev_plural: null, label: label(extra) }]
  }
  return base
})

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
      // new items always start at the top level, appended at the end -
      // nesting only happens afterward, via the indent button
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

const editingItemId = ref<string | null>(null)
const editName = ref('')
const editIsListOnly = ref(false)
const editAmount = ref<number | null>(null)
const editUnitId = ref<string | null>(null)
const editSize = ref('')
const editNotes = ref('')

function startEdit(li: NonNullable<typeof listItems.value>[number]) {
  editingItemId.value = li.id
  editName.value = li.name
  editIsListOnly.value = !li.item_id
  editAmount.value = li.amount
  editUnitId.value = li.unit?.id ?? null
  extraEditUnitOption.value = li.unit ?? null
  editSize.value = li.size ?? ''
  editNotes.value = li.notes ?? ''
}

function cancelEdit() {
  editingItemId.value = null
}

async function saveEdit(id: string) {
  const sizeValue = editSize.value.trim() || null
  const notesValue = editNotes.value.trim() || null
  await supabase
    .from('list_items')
    .update({
      ...(editIsListOnly.value ? { name: editName.value.trim() } : {}),
      amount: editAmount.value,
      unit_id: editUnitId.value,
      size: sizeValue,
      notes: notesValue,
    })
    .eq('id', id)

  const found = findItem(id)
  if (found) {
    if (editIsListOnly.value) found.item.name = editName.value.trim()
    found.item.amount = editAmount.value
    found.item.size = sizeValue
    found.item.notes = notesValue
    const unitMatch = editUnitId.value
      ? (unitOptions.value?.find((u) => u.id === editUnitId.value) ?? extraEditUnitOption.value)
      : null
    found.item.unit = unitMatch
      ? { id: unitMatch.id, name_singular: unitMatch.name_singular, name_plural: unitMatch.name_plural }
      : null
  }
  editingItemId.value = null
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
        <p v-if="list.notes" class="text-muted mb-2 text-sm">{{ list.notes }}</p>
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
        <UInput
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

    <div class="mb-4 flex gap-2">
      <UButton size="sm" variant="ghost" @click="checkAll(true)">Check all</UButton>
      <UButton size="sm" variant="ghost" @click="checkAll(false)">Uncheck all</UButton>
    </div>

    <form
      v-if="viewMode === 'edit'"
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

    <draggable
      v-model="itemTree"
      item-key="id"
      tag="ul"
      class="flex flex-col gap-2"
      group="list-items"
      handle=".drag-handle"
      :disabled="viewMode !== 'edit'"
      @start="onDragStart"
      @end="onDragEnd"
      @change="onItemTreeChange"
    >
      <template #item="{ element: li }">
        <li :data-id="li.id">
          <div class="rounded border border-default px-3 py-2">
            <div v-if="editingItemId !== li.id" class="flex items-center justify-between">
              <div class="flex flex-1 items-center gap-1">
                <UIcon
                  v-if="viewMode === 'edit'"
                  name="i-lucide-grip-vertical"
                  class="drag-handle text-muted shrink-0 cursor-grab"
                />
                <label class="flex flex-1 items-center gap-3">
                  <UCheckbox :model-value="li.is_done" @update:model-value="toggleDone(li.id, li.is_done)" />
                  <span :class="{ 'text-muted line-through': li.is_done }">
                    {{ li.name }}
                    <span v-if="li.amount != null" class="text-muted text-sm">
                      {{ li.amount }}<span v-if="li.unit">{{ ' ' + unitLabel(li.unit, li.amount) }}</span>
                    </span>
                    <span v-if="li.size" class="text-muted text-sm">({{ li.size }})</span>
                    <span v-if="li.notes" class="text-muted block text-xs">{{ li.notes }}</span>
                    <span v-if="sourcesLabel(li.list_item_sources)" class="text-muted block text-xs">
                      {{ sourcesLabel(li.list_item_sources) }}
                    </span>
                  </span>
                </label>
              </div>
              <div v-if="viewMode === 'edit'" class="flex items-center gap-1">
                <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(li)" />
                <UButton
                  size="sm"
                  variant="ghost"
                  color="error"
                  icon="i-lucide-trash-2"
                  @click="removeItem(li.id)"
                />
              </div>
            </div>

            <div v-else class="flex flex-col gap-2">
              <UInput v-if="editIsListOnly" v-model="editName" placeholder="Name" />
              <span v-else class="font-medium">{{ li.name }}</span>
              <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
                <UInputNumber v-model="editAmount" placeholder="Qty" :min="0" />
                <USelectMenu
                  v-model="editUnitId"
                  :items="editUnitOptionsForAmount"
                  value-key="id"
                  label-key="label"
                  :filter-fields="UNIT_FILTER_FIELDS"
                  placeholder="Unit"
                />
                <UInput v-model="editSize" placeholder="Size" />
              </div>
              <UInput v-model="editNotes" placeholder="Notes (optional)" />
              <div class="flex gap-2">
                <UButton size="sm" @click="saveEdit(li.id)">Save</UButton>
                <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
              </div>
            </div>
          </div>

          <draggable
            v-if="viewMode === 'edit' || li.children.length > 0"
            v-model="li.children"
            item-key="id"
            tag="ul"
            :data-parent-id="li.id"
            class="ml-6 mt-2 flex flex-col gap-2"
            :class="isDragging ? 'min-h-8' : ''"
            group="list-items"
            handle=".drag-handle"
            :disabled="viewMode !== 'edit'"
            :move="checkMove"
            @start="onDragStart"
            @end="onDragEnd"
            @change="onItemTreeChange"
          >
            <template #footer>
              <li
                v-if="isDragging && li.children.length === 0 && li.id !== draggedItemId"
                class="rounded border border-dashed border-default px-3 py-2 text-xs text-muted"
              >
                Drop here to nest under "{{ li.name }}"
              </li>
            </template>
            <template #item="{ element: child }">
              <li :data-id="child.id" class="rounded border border-default px-3 py-2">
                <div v-if="editingItemId !== child.id" class="flex items-center justify-between">
                  <div class="flex flex-1 items-center gap-1">
                    <UIcon
                      v-if="viewMode === 'edit'"
                      name="i-lucide-grip-vertical"
                      class="drag-handle text-muted shrink-0 cursor-grab"
                    />
                    <label class="flex flex-1 items-center gap-3">
                      <UCheckbox
                        :model-value="child.is_done"
                        @update:model-value="toggleDone(child.id, child.is_done)"
                      />
                      <span :class="{ 'text-muted line-through': child.is_done }">
                        {{ child.name }}
                        <span v-if="child.amount != null" class="text-muted text-sm">
                          {{ child.amount }}<span v-if="child.unit">{{ ' ' + unitLabel(child.unit, child.amount) }}</span>
                        </span>
                        <span v-if="child.size" class="text-muted text-sm">({{ child.size }})</span>
                        <span v-if="child.notes" class="text-muted block text-xs">{{ child.notes }}</span>
                        <span v-if="sourcesLabel(child.list_item_sources)" class="text-muted block text-xs">
                          {{ sourcesLabel(child.list_item_sources) }}
                        </span>
                      </span>
                    </label>
                  </div>
                  <div v-if="viewMode === 'edit'" class="flex items-center gap-1">
                    <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(child)" />
                    <UButton
                      size="sm"
                      variant="ghost"
                      color="error"
                      icon="i-lucide-trash-2"
                      @click="removeItem(child.id)"
                    />
                  </div>
                </div>

                <div v-else class="flex flex-col gap-2">
                  <UInput v-if="editIsListOnly" v-model="editName" placeholder="Name" />
                  <span v-else class="font-medium">{{ child.name }}</span>
                  <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
                    <UInputNumber v-model="editAmount" placeholder="Qty" :min="0" />
                    <USelectMenu
                      v-model="editUnitId"
                      :items="editUnitOptionsForAmount"
                      value-key="id"
                      label-key="label"
                      :filter-fields="UNIT_FILTER_FIELDS"
                      placeholder="Unit"
                    />
                    <UInput v-model="editSize" placeholder="Size" />
                  </div>
                  <UInput v-model="editNotes" placeholder="Notes (optional)" />
                  <div class="flex gap-2">
                    <UButton size="sm" @click="saveEdit(child.id)">Save</UButton>
                    <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
                  </div>
                </div>
              </li>
            </template>
          </draggable>
        </li>
      </template>
    </draggable>
    <p v-if="itemTree.length === 0" class="text-muted text-sm">No items yet.</p>
  </div>
</template>
