<script setup lang="ts">
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

const { data: listItems, refresh } = await useAsyncData(`list-items-${listId}`, async () => {
  const { data, error } = await supabase
    .from('list_items')
    .select(`
      id, name, amount, size, notes, is_done,
      unit:units!list_items_unit_id_fkey(id, name_singular, name_plural),
      list_item_sources(quantity, unit:units(name_singular, name_plural), recipe:recipes(id, name))
    `)
    .eq('list_id', listId)
    .is('deleted_at', null)
    .order('created_at')
  if (error) throw error
  return data
})

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

const viewMode = ref<'view' | 'edit'>('view')

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

  const { error: insertError } = await supabase.from('list_items').insert({
    list_id: listId,
    item_id: itemId,
    name: resolvedName,
    amount: amount.value,
    unit_id: unitId.value,
    size: size.value.trim() || null,
    notes: itemNotes.value.trim() || null,
  })

  adding.value = false
  if (insertError) {
    error.value = insertError.message
    return
  }

  selectedItem.value = null
  amount.value = null
  unitId.value = null
  size.value = ''
  itemNotes.value = ''
  // force the item picker to remount: its internal search text doesn't
  // reliably clear just from setting the external v-model to null,
  // especially after the create-new-item path.
  itemPickerKey.value++
  await refresh()
}

async function toggleDone(id: string, isDone: boolean) {
  await supabase.from('list_items').update({ is_done: !isDone }).eq('id', id)
  await refresh()
}

async function checkAll(done: boolean) {
  await supabase.from('list_items').update({ is_done: done }).eq('list_id', listId)
  await refresh()
}

async function removeItem(id: string) {
  await supabase.from('list_items').update({ deleted_at: new Date().toISOString() }).eq('id', id)
  await refresh()
}

// --- edit item inline ---

const editingItemId = ref<string | null>(null)
const editAmount = ref<number | null>(null)
const editUnitId = ref<string | null>(null)
const editSize = ref('')
const editNotes = ref('')

function startEdit(li: NonNullable<typeof listItems.value>[number]) {
  editingItemId.value = li.id
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
  await supabase
    .from('list_items')
    .update({
      amount: editAmount.value,
      unit_id: editUnitId.value,
      size: editSize.value.trim() || null,
      notes: editNotes.value.trim() || null,
    })
    .eq('id', id)
  editingItemId.value = null
  await refresh()
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

    <ul class="flex flex-col gap-2">
      <li
        v-for="li in listItems"
        :key="li.id"
        class="rounded border border-default px-3 py-2"
      >
        <div v-if="editingItemId !== li.id" class="flex items-center justify-between">
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
          <div v-if="viewMode === 'edit'" class="flex items-center gap-1">
            <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(li)" />
            <UButton size="sm" variant="ghost" color="error" icon="i-lucide-trash-2" @click="removeItem(li.id)" />
          </div>
        </div>

        <div v-else class="flex flex-col gap-2">
          <span class="font-medium">{{ li.name }}</span>
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
      </li>
      <li v-if="listItems && listItems.length === 0" class="text-muted text-sm">No items yet.</li>
    </ul>
  </div>
</template>
