<script setup lang="ts">
type Option = { id: string; name: string }

const route = useRoute()
const listId = route.params.id as string

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: list } = await useAsyncData(`list-${listId}`, async () => {
  const { data, error } = await supabase
    .from('lists')
    .select(`
      id, name, status,
      category:categories(id, name),
      list_tags(tags(id, name))
    `)
    .eq('id', listId)
    .single()
  if (error) throw error
  return data
})

const { data: listItems, refresh } = await useAsyncData(`list-items-${listId}`, async () => {
  const { data, error } = await supabase
    .from('list_items')
    .select(`
      id, name, amount, size, is_done,
      unit:units!list_items_unit_id_fkey(id, name_singular)
    `)
    .eq('list_id', listId)
    .order('created_at')
  if (error) throw error
  return data
})

const { data: itemOptionsInitial } = await useAsyncData('item-options', async () => {
  const { data, error } = await supabase.from('items').select('id, name').order('name')
  if (error) throw error
  return data
})
const itemOptions = ref<Option[]>(itemOptionsInitial.value ?? [])

const { data: unitOptionsRaw } = await useAsyncData('unit-options', async () => {
  const { data, error } = await supabase.from('units').select('id, name_singular').order('name_singular')
  if (error) throw error
  return data
})
const unitOptions = computed<Option[]>(
  () => unitOptionsRaw.value?.map((u) => ({ id: u.id, name: u.name_singular })) ?? [],
)

const selectedItem = ref<Option | null>(null)
const addToMasterList = ref(true)
const amount = ref<number | null>(null)
const unitId = ref<string | null>(null)
const size = ref('')
const error = ref('')
const adding = ref(false)

function onCreateItemOption(searchTerm: string) {
  selectedItem.value = { id: '', name: searchTerm }
}

async function addItem() {
  if (!space.value || !selectedItem.value) return
  const name = selectedItem.value.name.trim()
  if (!name) return

  error.value = ''
  adding.value = true

  let itemId: string | null = selectedItem.value.id || null
  if (!itemId && addToMasterList.value) {
    const { data, error: itemError } = await supabase
      .from('items')
      .insert({ space_id: space.value.id, name })
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

  const { error: insertError } = await supabase.from('list_items').insert({
    list_id: listId,
    item_id: itemId,
    name,
    amount: amount.value,
    unit_id: unitId.value,
    size: size.value.trim() || null,
  })

  adding.value = false
  if (insertError) {
    error.value = insertError.message
    return
  }

  selectedItem.value = null
  addToMasterList.value = true
  amount.value = null
  unitId.value = null
  size.value = ''
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
  await supabase.from('list_items').delete().eq('id', id)
  await refresh()
}

async function setStatus(status: 'active' | 'archived') {
  await supabase.from('lists').update({ status }).eq('id', listId)
  await navigateTo('/lists')
}

async function deleteList() {
  await supabase.from('lists').delete().eq('id', listId)
  await navigateTo('/lists')
}
</script>

<template>
  <div v-if="list" class="mx-auto max-w-2xl">
    <div class="mb-4 flex items-center justify-between">
      <div>
        <h1 class="text-xl font-semibold">{{ list.name }}</h1>
        <div class="mt-1 flex items-center gap-2">
          <span v-if="list.category" class="text-muted text-sm">{{ list.category.name }}</span>
          <UBadge v-for="t in list.list_tags" :key="t.tags!.id" size="sm" variant="subtle">
            {{ t.tags!.name }}
          </UBadge>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <UButton
          v-if="list.status === 'active'"
          size="sm"
          variant="outline"
          @click="setStatus('archived')"
        >
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
      <USelectMenu
        v-model="selectedItem"
        :items="itemOptions"
        create-item
        label-key="name"
        placeholder="Item name"
        class="w-full"
        @create="onCreateItemOption"
      />
      <UCheckbox v-if="selectedItem && !selectedItem.id" v-model="addToMasterList" label="Add to master list" />
      <div class="grid grid-cols-3 gap-2">
        <UInputNumber v-model="amount" placeholder="Qty" :min="0" />
        <USelectMenu v-model="unitId" :items="unitOptions" value-key="id" label-key="name" placeholder="Unit" />
        <UInput v-model="size" placeholder="Size" />
      </div>
      <p v-if="error" class="text-sm text-red-500">{{ error }}</p>
      <UButton type="submit" :loading="adding">Add item</UButton>
    </form>

    <ul class="flex flex-col gap-2">
      <li
        v-for="li in listItems"
        :key="li.id"
        class="flex items-center justify-between rounded border border-default px-3 py-2"
      >
        <label class="flex flex-1 items-center gap-3">
          <UCheckbox :model-value="li.is_done" @update:model-value="toggleDone(li.id, li.is_done)" />
          <span :class="{ 'text-muted line-through': li.is_done }">
            {{ li.name }}
            <span v-if="li.amount != null" class="text-muted text-sm">
              {{ li.amount }}<span v-if="li.unit">{{ ' ' + li.unit.name_singular }}</span>
            </span>
            <span v-if="li.size" class="text-muted text-sm">({{ li.size }})</span>
          </span>
        </label>
        <UButton size="sm" variant="ghost" color="error" icon="i-lucide-trash-2" @click="removeItem(li.id)" />
      </li>
      <li v-if="listItems && listItems.length === 0" class="text-muted text-sm">No items yet.</li>
    </ul>
  </div>
</template>
