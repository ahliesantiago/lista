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
    .select('id, name, deleted_at, list_id, parent_id, list:lists(id, name, deleted_at)')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

// same self-referencing-FK-embed limitation as categories above: resolve a
// trashed item's parent item client-side via a flat id->row fetch instead
// of a nested parent:list_items(...) embed
const { data: allListItems } = await useAsyncData('trash-all-list-items', async () => {
  const { data, error } = await supabase.from('list_items').select('id, name, deleted_at')
  if (error) throw error
  return data
})
const listItemById = computed(() => new Map((allListItems.value ?? []).map((li) => [li.id, li])))

const {
  data: storageLocations,
  error: storageLocationsError,
  refresh: refreshStorageLocations,
} = await useAsyncData('trash-storage-locations', async () => {
  const { data, error } = await supabase
    .from('storage_locations')
    .select('id, name, deleted_at, room:rooms(name)')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

const { data: rooms, error: roomsError, refresh: refreshRooms } = await useAsyncData('trash-rooms', async () => {
  const { data, error } = await supabase
    .from('rooms')
    .select('id, name, deleted_at')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

const {
  data: inventoryItems,
  error: inventoryItemsError,
  refresh: refreshInventoryItems,
} = await useAsyncData('trash-inventory-items', async () => {
  const { data, error } = await supabase
    .from('inventory_items')
    .select(
      'id, deleted_at, kind, item:items(name), inventory_item_locations(storage_location:storage_locations(id, name, deleted_at))',
    )
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

const {
  data: appliances,
  error: appliancesError,
  refresh: refreshAppliances,
} = await useAsyncData('trash-appliances', async () => {
  const { data, error } = await supabase
    .from('appliances')
    .select('id, name, deleted_at')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

const {
  data: furniture,
  error: furnitureError,
  refresh: refreshFurniture,
} = await useAsyncData('trash-furniture', async () => {
  const { data, error } = await supabase
    .from('furniture')
    .select('id, name, deleted_at')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

const {
  data: recipes,
  error: recipesError,
  refresh: refreshRecipes,
} = await useAsyncData('trash-recipes', async () => {
  const { data, error } = await supabase
    .from('recipes')
    .select('id, name, deleted_at')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

const {
  data: recipeCategories,
  error: recipeCategoriesError,
  refresh: refreshRecipeCategories,
} = await useAsyncData('trash-recipe-categories', async () => {
  const { data, error } = await supabase
    .from('recipe_categories')
    .select('id, name, deleted_at, parent_id')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
  if (error) throw error
  return data
})

// same client-side id->name lookup used for the item-side categories -
// avoids a self-join embed on a self-referencing FK, which PostgREST's
// schema cache doesn't reliably pick up
const { data: allRecipeCategoryNames } = await useAsyncData('trash-all-recipe-category-names', async () => {
  const { data, error } = await supabase.from('recipe_categories').select('id, name')
  if (error) throw error
  return data
})
const recipeCategoryNameById = computed(
  () => new Map((allRecipeCategoryNames.value ?? []).map((c) => [c.id, c.name])),
)

const {
  data: recipeTags,
  error: recipeTagsError,
  refresh: refreshRecipeTags,
} = await useAsyncData('trash-recipe-tags', async () => {
  const { data, error } = await supabase
    .from('recipe_tags')
    .select('id, name, deleted_at')
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
  } else if (table === 'list_items') {
    // these two cascades are independent - a restored item can need its
    // list AND its parent item brought back at the same time, so both run
    // rather than one short-circuiting the other
    if (row.list?.deleted_at) {
      // this item's parent list is still trashed, which would leave the
      // restored item orphaned/unreachable - bring the list back too, but
      // don't touch any of its other still-trashed items
      await supabase.from('lists').update({ deleted_at: null }).eq('id', row.list_id)
      await refreshLists()
    }
    if (row.parent_id && listItemById.value.get(row.parent_id)?.deleted_at) {
      // same orphan-prevention, one level down: this item's parent item is
      // itself still trashed
      await supabase.from('list_items').update({ deleted_at: null }).eq('id', row.parent_id)
    }
    // bring back any children that were cascade-trashed alongside this item
    await supabase
      .from('list_items')
      .update({ deleted_at: null })
      .eq('parent_id', row.id)
      .not('deleted_at', 'is', null)
    await refreshListItems()
  } else if (table === 'storage_locations') {
    // mirrors the lists -> list_items cascade above - goes through the
    // join table since a location is no longer a direct column
    const { data: linked } = await supabase
      .from('inventory_item_locations')
      .select('inventory_item_id')
      .eq('storage_location_id', row.id)
    const linkedIds = (linked ?? []).map((l) => l.inventory_item_id)
    if (linkedIds.length > 0) {
      await supabase
        .from('inventory_items')
        .update({ deleted_at: null })
        .in('id', linkedIds)
        .not('deleted_at', 'is', null)
    }
    await refreshInventoryItems()
  } else if (table === 'inventory_items') {
    const loc = row.inventory_item_locations?.[0]?.storage_location
    if (loc?.deleted_at) {
      await supabase.from('storage_locations').update({ deleted_at: null }).eq('id', loc.id)
      await refreshStorageLocations()
    }
  }
  await refreshAll()
}

async function destroy(table: string, id: string) {
  await supabase.from(table).delete().eq('id', id)
  await refreshAll()
}

const sections = computed(() => [
  {
    label: 'Categories',
    table: 'categories',
    rows: categories.value,
    error: categoriesError.value,
    display: (r: any) =>
      `${r.name}${r.parent_id ? ' (sub of ' + (categoryNameById.value.get(r.parent_id) ?? '?') + ')' : ''}`,
  },
  { label: 'Tags', table: 'tags', rows: tags.value, error: tagsError.value, display: (r: any) => r.name },
  { label: 'Units', table: 'units', rows: units.value, error: unitsError.value, display: (r: any) => r.name_singular },
  { label: 'Items', table: 'items', rows: items.value, error: itemsError.value, display: (r: any) => r.name },
  { label: 'Lists', table: 'lists', rows: lists.value, error: listsError.value, display: (r: any) => r.name },
  {
    label: 'List Items',
    table: 'list_items',
    rows: listItems.value,
    error: listItemsError.value,
    display: (r: any) => {
      const parentName = r.parent_id ? listItemById.value.get(r.parent_id)?.name : null
      const context = [r.list?.name, parentName && `sub-item of ${parentName}`].filter(Boolean).join(', ')
      return `${r.name}${context ? ' (' + context + ')' : ''}`
    },
  },
  {
    label: 'Storage Locations',
    table: 'storage_locations',
    rows: storageLocations.value,
    error: storageLocationsError.value,
    display: (r: any) => `${r.name}${r.room ? ' (' + r.room.name + ')' : ''}`,
  },
  { label: 'Rooms', table: 'rooms', rows: rooms.value, error: roomsError.value, display: (r: any) => r.name },
  {
    label: 'Inventory Items',
    table: 'inventory_items',
    rows: inventoryItems.value,
    error: inventoryItemsError.value,
    display: (r: any) => {
      const loc = r.inventory_item_locations?.[0]?.storage_location
      return `${r.item?.name ?? '?'}${loc ? ' (' + loc.name + ')' : ''}${
        r.kind === 'household' ? ' [Household]' : ''
      }`
    },
  },
  {
    label: 'Appliances',
    table: 'appliances',
    rows: appliances.value,
    error: appliancesError.value,
    display: (r: any) => r.name,
  },
  {
    label: 'Furniture',
    table: 'furniture',
    rows: furniture.value,
    error: furnitureError.value,
    display: (r: any) => r.name,
  },
  {
    label: 'Recipes',
    table: 'recipes',
    rows: recipes.value,
    error: recipesError.value,
    display: (r: any) => r.name,
  },
  {
    label: 'Recipe Categories',
    table: 'recipe_categories',
    rows: recipeCategories.value,
    error: recipeCategoriesError.value,
    display: (r: any) =>
      `${r.name}${r.parent_id ? ' (sub of ' + (recipeCategoryNameById.value.get(r.parent_id) ?? '?') + ')' : ''}`,
  },
  {
    label: 'Recipe Tags',
    table: 'recipe_tags',
    rows: recipeTags.value,
    error: recipeTagsError.value,
    display: (r: any) => r.name,
  },
])

const expandedSections = ref<Record<string, boolean>>({})
function toggleSection(label: string) {
  expandedSections.value[label] = !expandedSections.value[label]
}
function expandAll() {
  for (const s of sections.value) expandedSections.value[s.label] = true
}
function collapseAll() {
  for (const s of sections.value) expandedSections.value[s.label] = false
}

async function refreshAll() {
  await Promise.all([
    refreshCategories(),
    refreshTags(),
    refreshUnits(),
    refreshItems(),
    refreshLists(),
    refreshListItems(),
    refreshStorageLocations(),
    refreshRooms(),
    refreshInventoryItems(),
    refreshAppliances(),
    refreshFurniture(),
    refreshRecipes(),
    refreshRecipeCategories(),
    refreshRecipeTags(),
  ])
}
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <p class="mb-3 text-xs">
      Deleted items are kept here until you remove them for good. "Delete Permanently"
      can't be undone, and anything elsewhere still pointing at it (a recipe's ingredient,
      a list's item) will lose that link rather than disappear itself.
    </p>
    <p class="mb-6 text-xs">
      Restoring something also brings back anything that was removed along with it
      (e.g. a list's items, or a location's pantry entries). Likewise, deleting something
      permanently will also remove anything that was deleted along with it.
    </p>

    <div class="mb-4 flex gap-2">
      <UButton size="sm" variant="ghost" @click="expandAll">Expand all</UButton>
      <UButton size="sm" variant="ghost" @click="collapseAll">Collapse all</UButton>
    </div>

    <template v-for="section in sections" :key="section.label">
      <div class="mb-6">
        <button
          type="button"
          class="mb-2 flex w-full items-center justify-between text-left"
          @click="toggleSection(section.label)"
        >
          <h3 class="text-sm font-semibold text-muted">{{ section.label }}</h3>
          <UIcon
            :name="expandedSections[section.label] ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
            class="size-4 text-muted"
          />
        </button>
        <template v-if="expandedSections[section.label]">
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
        </template>
      </div>
    </template>
  </div>
</template>
