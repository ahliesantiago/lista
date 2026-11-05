<script setup lang="ts">
const supabase = useSupabaseClient()

const { data: categories, refresh: refreshCategories } = await useAsyncData('trash-categories', async () => {
  const { data, error } = await supabase
    .from('categories')
    .select('id, name, deleted_at')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

const { data: tags, refresh: refreshTags } = await useAsyncData('trash-tags', async () => {
  const { data, error } = await supabase
    .from('tags')
    .select('id, name, deleted_at')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

const { data: units, refresh: refreshUnits } = await useAsyncData('trash-units', async () => {
  const { data, error } = await supabase
    .from('units')
    .select('id, name_singular, deleted_at')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

const { data: items, refresh: refreshItems } = await useAsyncData('trash-items', async () => {
  const { data, error } = await supabase
    .from('items')
    .select('id, name, deleted_at')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

const { data: lists, refresh: refreshLists } = await useAsyncData('trash-lists', async () => {
  const { data, error } = await supabase
    .from('lists')
    .select('id, name, deleted_at')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

const { data: listItems, refresh: refreshListItems } = await useAsyncData('trash-list-items', async () => {
  const { data, error } = await supabase
    .from('list_items')
    .select('id, name, deleted_at, list:lists(name)')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

async function restore(table: string, id: string) {
  await supabase.from(table).update({ deleted_at: null }).eq('id', id)
  if (table === 'lists') {
    await supabase.from('list_items').update({ deleted_at: null }).eq('list_id', id).not('deleted_at', 'is', null)
    await refreshListItems()
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
      { label: 'Categories', table: 'categories', rows: categories, display: (r: any) => r.name },
      { label: 'Tags', table: 'tags', rows: tags, display: (r: any) => r.name },
      { label: 'Units', table: 'units', rows: units, display: (r: any) => r.name_singular },
      { label: 'Items', table: 'items', rows: items, display: (r: any) => r.name },
      { label: 'Lists', table: 'lists', rows: lists, display: (r: any) => r.name },
      {
        label: 'List Items',
        table: 'list_items',
        rows: listItems,
        display: (r: any) => `${r.name}${r.list ? ' (' + r.list.name + ')' : ''}`,
      },
    ]" :key="section.label"
    >
      <div class="mb-6">
        <h3 class="mb-2 text-sm font-semibold text-muted">{{ section.label }}</h3>
        <ul class="flex flex-col gap-2">
          <li
            v-for="row in section.rows"
            :key="row.id"
            class="flex items-center justify-between rounded border border-default px-3 py-2"
          >
            <span>{{ section.display(row) }}</span>
            <div class="flex gap-2">
              <UButton size="sm" variant="outline" @click="restore(section.table, row.id)">Restore</UButton>
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
