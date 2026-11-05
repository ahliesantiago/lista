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
      item_categories(categories(id, name, parent_id)),
      default_unit:units!items_default_unit_id_fkey(id, name_singular),
      item_tags(tags(id, name)),
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

const slideoverOpen = ref(false)
const editingId = ref<string | null>(null)
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

// a unit a item stays linked to can be trashed (soft delete never touches
// the link - only a permanent delete does, via the FK). The picker options
// are live-only, so without this the picker can't find a label for the
// current value and falls back to showing the raw id. Categories don't need
// this: they're a multi-select of whole objects now, so chips render from
// the bound objects directly rather than being re-resolved from :items.
const extraDefaultUnitOption = ref<{ id: string; name_singular: string } | null>(null)
const defaultUnitOptionsForForm = computed(() => {
  const base = unitOptions.value ?? []
  const extra = extraDefaultUnitOption.value
  return extra && !base.some((u) => u.id === extra.id) ? [...base, extra] : base
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
  const linkedCategories = item.item_categories.map((ic) => ic.categories!)
  selectedCategories.value = linkedCategories.filter((c) => !c.parent_id)
  selectedSubcategories.value = linkedCategories.filter((c) => c.parent_id)
  defaultUnitId.value = item.default_unit?.id ?? null
  extraDefaultUnitOption.value = item.default_unit ?? null
  selectedUnits.value = item.item_units.map((iu) => iu.units!)
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
    await supabase.from('item_categories').delete().eq('item_id', itemId)
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
  const allCategories = [...selectedCategories.value, ...selectedSubcategories.value]
  if (allCategories.length > 0) {
    await supabase
      .from('item_categories')
      .insert(allCategories.map((c) => ({ item_id: itemId, category_id: c.id })))
  }

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
          <span v-if="item.price != null" class="text-muted ml-2 text-sm">${{ item.price }}</span>
          <UBadge
            v-for="ic in item.item_categories"
            :key="ic.categories!.id"
            size="sm"
            :variant="ic.categories!.parent_id ? 'subtle' : 'solid'"
            class="ml-2"
          >
            {{ ic.categories!.name }}
          </UBadge>
          <UBadge v-for="t in item.item_tags" :key="t.tags!.id" size="sm" variant="outline" class="ml-2">
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

          <UFormField label="Categories" hint="Optional, up to 2">
            <UInputMenu
              v-model="selectedCategories"
              :items="topLevelCategoryOptions"
              multiple
              label-key="name"
              class="w-full"
            />
          </UFormField>

          <UFormField label="Subcategories" hint="Optional, up to 2">
            <UInputMenu
              v-model="selectedSubcategories"
              :items="subcategoryOptions"
              multiple
              label-key="name"
              placeholder="Pick a category first"
              class="w-full"
            />
          </UFormField>

          <UFormField label="Price" hint="Optional">
            <UInputNumber v-model="price" :min="0" class="w-full" />
          </UFormField>

          <UFormField label="Default Unit" hint="Optional">
            <UInputMenu
              v-model="defaultUnitId"
              :items="defaultUnitOptionsForForm"
              value-key="id"
              label-key="name_singular"
              :filter-fields="UNIT_FILTER_FIELDS"
              class="w-full"
            />
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
