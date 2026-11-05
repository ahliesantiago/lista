<script setup lang="ts">
const supabase = useSupabaseClient()

const {
  data: categories,
  error: categoriesError,
  refresh: refreshCategories,
} = await useAsyncData('trash-categories', async () => {
  const { data, error } = await supabase
    .from('categories')
    .select('id, name, deleted_at, parent_id')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

/**
 * Resolving a trashed subcategory's parent name client-side instead of via a
 * self-join embed (categories!categories_parent_id_fkey) - PostgREST's schema cache
 * doesn't reliably pick up self-referencing FKs, and a plain id->name lookup needs no embed at all
 **/
const { data: allCategoryNames } = await useAsyncData('trash-all-category-names', async () => {
  const { data, error } = await supabase.from('categories').select('id, name')
  if (error) throw error
  return data
})
const categoryNameById = computed(() => new Map((allCategoryNames.value ?? []).map((c) => [c.id, c.name])))

const { data: tags, error: tagsError, refresh: refreshTags } = await useAsyncData('trash-tags', async () => {
  const { data, error } = await supabase
    .from('tags')
    .select('id, name, deleted_at')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

const { data: units, error: unitsError, refresh: refreshUnits } = await useAsyncData('trash-units', async () => {
  const { data, error } = await supabase
    .from('units')
    .select('id, name_singular, deleted_at')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

const { data: items, error: itemsError, refresh: refreshItems } = await useAsyncData('trash-items', async () => {
  const { data, error } = await supabase
    .from('items')
    .select('id, name, deleted_at')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

const { data: lists, error: listsError, refresh: refreshLists } = await useAsyncData('trash-lists', async () => {
  const { data, error } = await supabase
    .from('lists')
    .select('id, name, deleted_at')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

const {
  data: listItems,
  error: listItemsError,
  refresh: refreshListItems,
} = await useAsyncData('trash-list-items', async () => {
  const { data, error } = await supabase
    .from('list_items')
    .select('id, name, deleted_at, list_id, list:lists(id, name, deleted_at)')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

async function restore(table: string, row: Record<string, any>) {
  await supabase.from(table).update({ deleted_at: null }).eq('id', row.id)
  if (table === 'lists') {
    // restore every list item that was trashed *as part of* this list
    // (cascade-deleted alongside it) back along with it
    await supabase
      .from('list_items')
      .update({ deleted_at: null })
      .eq('list_id', row.id)
      .not('deleted_at', 'is', null)
    await refreshListItems()
  } else if (table === 'list_items' && row.list?.deleted_at) {
    // this item's parent list is still trashed, which would leave the
    // restored item orphaned/unreachable - bring the list back too, but
    // don't touch any of its other still-trashed items
    await supabase.from('lists').update({ deleted_at: null }).eq('id', row.list_id)
    await refreshLists()
  }
  await refreshAll()
}

async function destroy(table: string, id: string) {
  await supabase.from(table).delete().eq('id', id)
  await refreshAll()
}

async function refreshAll() {
  await Promise.all([
    refreshCategories(),
    refreshTags(),
    refreshUnits(),
    refreshItems(),
    refreshLists(),
    refreshListItems(),
  ])
}
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <h1 class="mb-6 text-xl font-semibold">Trash</h1>

    <template v-for="section in [
      {
        label: 'Categories',
        table: 'categories',
        rows: categories,
        error: categoriesError,
        display: (r: any) =>
          `${r.name}${r.parent_id ? ' (sub of ' + (categoryNameById.get(r.parent_id) ?? '?') + ')' : ''}`,
      },
      { label: 'Tags', table: 'tags', rows: tags, error: tagsError, display: (r: any) => r.name },
      { label: 'Units', table: 'units', rows: units, error: unitsError, display: (r: any) => r.name_singular },
      { label: 'Items', table: 'items', rows: items, error: itemsError, display: (r: any) => r.name },
      { label: 'Lists', table: 'lists', rows: lists, error: listsError, display: (r: any) => r.name },
      {
        label: 'List Items',
        table: 'list_items',
        rows: listItems,
        error: listItemsError,
        display: (r: any) => `${r.name}${r.list ? ' (' + r.list.name + ')' : ''}`,
      },
    ]" :key="section.label"
    >
      <div class="mb-6">
        <h3 class="mb-2 text-sm font-semibold text-muted">{{ section.label }}</h3>
        <p v-if="section.error" class="text-sm text-red-500">{{ section.error.message }}</p>
        <ul v-else class="flex flex-col gap-2">
          <li
            v-for="row in section.rows"
            :key="row.id"
            class="flex items-center justify-between rounded border border-default px-3 py-2"
          >
            <span>{{ section.display(row) }}</span>
            <div class="flex gap-2">
              <UButton size="sm" variant="outline" @click="restore(section.table, row)">Restore</UButton>
              <UButton size="sm" variant="outline" color="error" @click="destroy(section.table, row.id)">
                Delete Permanently
              </UButton>
            </div>
          </li>
          <li v-if="section.rows && section.rows.length === 0" class="text-muted text-sm">Empty.</li>
        </ul>
      </div>
    </template>
  </div>
</template>
