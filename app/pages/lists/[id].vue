<script setup lang="ts">
type Option = { id: string; name: string }
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
      category:categories(id, name),
      list_tags(tags(id, name))
    `)
    .eq('id', listId)
    .is('deleted_at', null)
    .single()
  if (error) throw error
  return data
})

const { data: listItems, refresh } = await useAsyncData(`list-items-${listId}`, async () => {
  const { data, error } = await supabase
    .from('list_items')
    .select(`
      id, name, amount, size, notes, is_done,
      unit:units!list_items_unit_id_fkey(id, name_singular, name_plural)
    `)
    .eq('list_id', listId)
    .is('deleted_at', null)
    .order('created_at')
  if (error) throw error
  return data
})

const { data: itemOptionsInitial } = await useAsyncData('item-options', async () => {
  const { data, error } = await supabase.from('items').select('id, name').is('deleted_at', null).order('name')
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
    .select('id, name')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data
})

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

// --- editable header: name/description/notes/category/tags ---

const name = ref(list.value?.name ?? '')
const description = ref(list.value?.description ?? '')
const notes = ref(list.value?.notes ?? '')
const categoryId = ref<string | null>(list.value?.category?.id ?? null)
const listTags = ref<Option[]>(list.value?.list_tags.map((lt) => lt.tags!) ?? [])

async function saveListField(patch: Record<string, unknown>) {
  await supabase.from('lists').update(patch).eq('id', listId)
}

watch(categoryId, (val) => {
  saveListField({ category_id: val })
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
const itemPickerOpen = ref(false)
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
const editUnitOptionsForAmount = computed(
  () =>
    unitOptions.value?.map((u) => ({
      ...u,
      label: editAmount.value != null && editAmount.value !== 1 ? u.name_plural : u.name_singular,
    })) ?? [],
)

function onCreateItemOption(searchTerm: string) {
  selectedItem.value = { id: '', name: searchTerm }
  itemPickerOpen.value = false
}

async function addItem() {
  if (!space.value || !selectedItem.value) return
  const itemName = selectedItem.value.name.trim()
  if (!itemName) return

  error.value = ''
  adding.value = true

  let itemId: string | null = selectedItem.value.id || null
  if (!itemId && addToMasterList.value) {
    const { data, error: itemError } = await supabase
      .from('items')
      .insert({ space_id: space.value.id, name: itemName })
      .select('id, name')
      .single()
    if (itemError) {
      adding.value = false
      error.value = itemError.message
      return
    }
    itemId = data.id
    itemOptions.value.push(data)
  }

  if (itemId && unitId.value) {
    await supabase
      .from('item_units')
      .upsert({ item_id: itemId, unit_id: unitId.value }, { ignoreDuplicates: true })
  }

  const { error: insertError } = await supabase.from('list_items').insert({
    list_id: listId,
    item_id: itemId,
    name: itemName,
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
    <div class="mb-4 flex items-start justify-between gap-4">
      <div class="flex-1">
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
        <div class="flex gap-2">
          <UFormField label="Category" hint="Optional" class="flex-1">
            <UInputMenu
              v-model="categoryId"
              :items="categoryOptions ?? []"
              value-key="id"
              label-key="name"
              class="w-full"
            />
          </UFormField>
          <UFormField label="Tags" hint="Optional" class="flex-1">
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
      </div>
      <div class="flex shrink-0 items-center gap-2">
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

    <form class="mb-6 flex flex-col gap-2 rounded border border-default p-3" @submit.prevent="addItem">
      <UInputMenu
        :key="itemPickerKey"
        v-model="selectedItem"
        v-model:open="itemPickerOpen"
        :items="itemOptions"
        create-item
        label-key="name"
        placeholder="Item name"
        class="w-full"
        @create="onCreateItemOption"
      />
      <UCheckbox
        v-if="!selectedItem || !selectedItem.id"
        v-model="addToMasterList"
        label="Add to master list"
      />
      <div class="grid grid-cols-3 gap-2">
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
            </span>
          </label>
          <div class="flex items-center gap-1">
            <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(li)" />
            <UButton size="sm" variant="ghost" color="error" icon="i-lucide-trash-2" @click="removeItem(li.id)" />
          </div>
        </div>

        <div v-else class="flex flex-col gap-2">
          <span class="font-medium">{{ li.name }}</span>
          <div class="grid grid-cols-3 gap-2">
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
