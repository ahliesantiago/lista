<script setup lang="ts">
type Option = { id: string; name: string }

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: items, error: itemsError, refresh } = await useAsyncData('items', async () => {
  const { data, error } = await supabase
    .from('items')
    .select(`
      id, name, plural_name, price,
      category:categories(id, name),
      default_unit:units!items_default_unit_id_fkey(id, name_singular),
      item_tags(tags(id, name)),
      item_units(units(id, name_singular))
    `)
    .order('name')
  if (error) throw error
  return data
})

const { data: categoryOptions } = await useAsyncData('category-options', async () => {
  const { data, error } = await supabase.from('categories').select('id, name').order('name')
  if (error) throw error
  return data
})

const { data: unitOptionsRaw } = await useAsyncData('unit-options', async () => {
  const { data, error } = await supabase.from('units').select('id, name_singular').order('name_singular')
  if (error) throw error
  return data
})
const unitOptions = computed<Option[]>(
  () => unitOptionsRaw.value?.map((u) => ({ id: u.id, name: u.name_singular })) ?? [],
)

const tagOptions = ref<Option[]>([])
const { data: tagOptionsInitial } = await useAsyncData('tag-options', async () => {
  const { data, error } = await supabase.from('tags').select('id, name').order('name')
  if (error) throw error
  return data
})
tagOptions.value = tagOptionsInitial.value ?? []

const slideoverOpen = ref(false)
const editingId = ref<string | null>(null)
const name = ref('')
const pluralName = ref('')
const price = ref<number | null>(null)
const categoryId = ref<string | null>(null)
const defaultUnitId = ref<string | null>(null)
const selectedUnits = ref<Option[]>([])
const selectedTags = ref<Option[]>([])
const error = ref('')
const saving = ref(false)

function resetForm() {
  editingId.value = null
  name.value = ''
  pluralName.value = ''
  price.value = null
  categoryId.value = null
  defaultUnitId.value = null
  selectedUnits.value = []
  selectedTags.value = []
  error.value = ''
}

function openCreate() {
  resetForm()
  slideoverOpen.value = true
}

function openEdit(item: NonNullable<typeof items.value>[number]) {
  editingId.value = item.id
  name.value = item.name
  pluralName.value = item.plural_name ?? ''
  price.value = item.price
  categoryId.value = item.category?.id ?? null
  defaultUnitId.value = item.default_unit?.id ?? null
  selectedUnits.value = item.item_units.map((iu) => ({ id: iu.units!.id, name: iu.units!.name_singular }))
  selectedTags.value = item.item_tags.map((it) => ({ id: it.tags!.id, name: it.tags!.name }))
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

  const payload = {
    space_id: space.value.id,
    name: name.value.trim(),
    plural_name: pluralName.value.trim() || null,
    category_id: categoryId.value,
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
    await supabase.from('item_tags').delete().eq('item_id', itemId)
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

  if (selectedTags.value.length > 0) {
    await supabase.from('item_tags').insert(selectedTags.value.map((t) => ({ item_id: itemId, tag_id: t.id })))
  }
  if (selectedUnits.value.length > 0) {
    await supabase.from('item_units').insert(selectedUnits.value.map((u) => ({ item_id: itemId, unit_id: u.id })))
  }

  saving.value = false
  slideoverOpen.value = false
  await refresh()
}

async function deleteItem(id: string) {
  await supabase.from('items').delete().eq('id', id)
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <div class="mb-4 flex items-center justify-between">
      <h1 class="text-xl font-semibold">Items</h1>
      <UButton icon="i-lucide-plus" @click="openCreate">Add item</UButton>
    </div>

    <p v-if="itemsError" class="mb-4 text-sm text-red-500">{{ itemsError.message }}</p>

    <ul class="flex flex-col gap-2">
      <li
        v-for="item in items"
        :key="item.id"
        class="flex cursor-pointer items-center justify-between rounded border border-default px-3 py-2"
        @click="openEdit(item)"
      >
        <div>
          <span class="font-medium">{{ item.name }}</span>
          <span v-if="item.category" class="text-muted ml-2 text-sm">{{ item.category.name }}</span>
          <span v-if="item.price != null" class="text-muted ml-2 text-sm">${{ item.price }}</span>
          <UBadge v-for="t in item.item_tags" :key="t.tags!.id" size="sm" variant="subtle" class="ml-2">
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
      <li v-if="items && items.length === 0" class="text-muted text-sm">No items yet.</li>
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

          <UFormField label="Category" hint="Optional">
            <USelectMenu
              v-model="categoryId"
              :items="categoryOptions ?? []"
              value-key="id"
              label-key="name"
              class="w-full"
            />
          </UFormField>

          <UFormField label="Price" hint="Optional">
            <UInputNumber v-model="price" :min="0" class="w-full" />
          </UFormField>

          <UFormField label="Default Unit" hint="Optional">
            <USelectMenu
              v-model="defaultUnitId"
              :items="unitOptions"
              value-key="id"
              label-key="name"
              class="w-full"
            />
          </UFormField>

          <UFormField label="Allowed Units" hint="Optional">
            <USelectMenu v-model="selectedUnits" :items="unitOptions" multiple label-key="name" class="w-full" />
          </UFormField>

          <UFormField label="Tags" hint="Optional">
            <USelectMenu
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
