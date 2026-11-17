<script setup lang="ts">
const supabase = useSupabaseClient()
const { data: currentSpace } = await useCurrentSpace()

const { data: activeLists } = await useAsyncData('dashboard-lists', async () => {
  const { data, error } = await supabase
    .from('lists')
    .select('id, name')
    .eq('status', 'active')
    .is('deleted_at', null)
    .order('updated_at', { ascending: false })
  if (error) throw error
  return data
})

const { data: lowStockItems } = await useAsyncData('dashboard-low-stock', async () => {
  const { data, error } = await supabase
    .from('inventory_items')
    .select('id, stock_status, item:items(name)')
    .in('stock_status', ['low', 'out'])
    .is('deleted_at', null)
  if (error) throw error
  return data
})

const { data: favoriteRecipes } = await useAsyncData('dashboard-favorite-recipes', async () => {
  const { data, error } = await supabase
    .from('recipes')
    .select('id, name')
    .eq('is_favorite', true)
    .is('deleted_at', null)
    .order('updated_at', { ascending: false })
  if (error) throw error
  return data
})

const taxonomyTiles = [
  { to: '/items', label: 'Items', icon: 'i-lucide-folder-cog' },
  { to: '/categories', label: 'Categories', icon: 'i-lucide-folder-tree' },
  { to: '/tags', label: 'Tags', icon: 'i-lucide-tags' },
  { to: '/units', label: 'Units', icon: 'i-lucide-ruler' },
]

const householdTiles = [
  { to: '/home-inventory', label: 'Inventory', icon: 'i-lucide-box' },
  { to: '/equipment', label: 'Equipment', icon: 'i-lucide-wrench' },
  { to: '/appliances', label: 'Appliances', icon: 'i-lucide-washing-machine' },
  { to: '/furniture', label: 'Furniture', icon: 'i-lucide-armchair' },
  { to: '/rooms', label: 'Rooms', icon: 'i-lucide-door-open' },
  { to: '/storage', label: 'Locations', icon: 'i-lucide-map-pin' },
]
</script>

<template>
  <div class="mx-auto max-w-3xl">
    <h2 class="mb-6 text-lg text-muted text-center">
      Welcome back<span v-if="currentSpace"> to {{ currentSpace.name }}</span>
    </h2>

    <!-- Lists & Recipes -->
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
      <div class="rounded border border-default p-4">
        <h3 class="mb-2 font-medium">Lists</h3>
        <p v-if="!activeLists?.length" class="text-muted mb-3 text-sm">No active lists yet.</p>
        <ul v-else class="mb-3 flex flex-col gap-1 text-sm">
          <li v-for="l in activeLists.slice(0, 3)" :key="l.id">
            <NuxtLink :to="`/lists/${l.id}`" class="hover:text-primary">{{ l.name }}</NuxtLink>
          </li>
        </ul>
        <p v-if="activeLists && activeLists.length > 3" class="text-muted mb-3 text-xs">
          +{{ activeLists.length - 3 }} more
        </p>
        <UButton to="/lists" variant="outline" size="sm" block>View all lists</UButton>
      </div>

      <div class="rounded border border-default p-4">
        <h3 class="mb-2 font-medium">Favorite recipes</h3>
        <p v-if="!favoriteRecipes?.length" class="text-muted mb-3 text-sm">No favorites yet.</p>
        <ul v-else class="mb-3 flex flex-col gap-1 text-sm">
          <li v-for="r in favoriteRecipes.slice(0, 3)" :key="r.id">
            <NuxtLink :to="`/recipes/${r.id}`" class="hover:text-primary">{{ r.name }}</NuxtLink>
          </li>
        </ul>
        <p v-if="favoriteRecipes && favoriteRecipes.length > 3" class="text-muted mb-3 text-xs">
          +{{ favoriteRecipes.length - 3 }} more
        </p>
        <UButton to="/recipes" variant="outline" size="sm" block>View all recipes</UButton>
      </div>
    </div>

    <div class="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
      <NuxtLink
        v-for="tile in taxonomyTiles"
        :key="tile.to"
        :to="tile.to"
        class="flex flex-col items-center gap-2 rounded border border-default p-4 text-center hover:bg-elevated"
      >
        <UIcon :name="tile.icon" class="size-6" />
        <span class="text-sm font-medium">{{ tile.label }}</span>
      </NuxtLink>
    </div>

    <!-- Household -->
    <h2 class="mb-3 mt-8 text-sm font-semibold text-muted">Household</h2>
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
      <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <NuxtLink
          v-for="tile in householdTiles"
          :key="tile.to"
          :to="tile.to"
          class="flex flex-col items-center gap-2 rounded border border-default p-4 text-center hover:bg-elevated"
        >
          <UIcon :name="tile.icon" class="size-6" />
          <span class="text-sm font-medium">{{ tile.label }}</span>
        </NuxtLink>
      </div>

      <div class="flex flex-col rounded border border-default p-4">
        <h3 class="mb-2 font-medium">Pantry alerts</h3>
        <p v-if="!lowStockItems?.length" class="text-muted mb-3 text-sm">Everything's stocked.</p>
        <ul v-else class="mb-3 flex flex-col gap-1 text-sm">
          <li v-for="p in lowStockItems.slice(0, 3)" :key="p.id" class="flex items-center justify-between gap-2">
            <span>{{ p.item?.name }}</span>
            <UBadge size="sm" :color="p.stock_status === 'out' ? 'error' : 'warning'">
              {{ p.stock_status === 'out' ? 'Out' : 'Low' }}
            </UBadge>
          </li>
        </ul>
        <p v-if="lowStockItems && lowStockItems.length > 3" class="text-muted mb-3 text-xs">
          +{{ lowStockItems.length - 3 }} more
        </p>
        <UButton to="/pantry" variant="outline" size="sm" block class="mt-auto">Go to pantry</UButton>
      </div>
    </div>
  </div>
</template>
