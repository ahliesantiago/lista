<script setup lang="ts">
type Option = { id: string; name: string }
type UnitOption = {
  id: string
  name_singular: string
  name_plural: string
  abbrev_singular: string | null
  abbrev_plural: string | null
}

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: recipes, refresh } = await useAsyncData('recipes', async () => {
  const { data, error } = await supabase
    .from('recipes')
    .select(`
      id, name, prep_time_minutes, cook_time_minutes, is_favorite, is_interested,
      recipe_categories(categories(id, name, parent_id)),
      recipe_tags(tags(id, name))
    `)
    .is('deleted_at', null)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data
})

const filter = ref<'all' | 'favorites' | 'interested'>('all')
const visibleRecipes = computed(() => {
  if (!recipes.value) return []
  if (filter.value === 'favorites') return recipes.value.filter((r) => r.is_favorite)
  if (filter.value === 'interested') return recipes.value.filter((r) => r.is_interested)
  return recipes.value
})

const newName = ref('')
const createError = ref('')
const creating = ref(false)

async function createRecipe() {
  if (!space.value) return
  createError.value = ''
  creating.value = true
  const { data, error: insertError } = await supabase
    .from('recipes')
    .insert({ space_id: space.value.id, name: newName.value.trim() })
    .select('id')
    .single()
  if (insertError || !data) {
    creating.value = false
    createError.value = insertError?.message ?? 'Failed to create recipe'
    return
  }
  await navigateTo(`/recipes/${data.id}`)
}

async function deleteRecipe(id: string) {
  await supabase.from('recipes').update({ deleted_at: new Date().toISOString() }).eq('id', id)
  await refresh()
}

// --- import from URL ---

const importUrl = ref('')
const importing = ref(false)
const importError = ref('')

function parseQuantity(text: string): { value: number | null; rest: string } {
  const fractionMatch = text.match(/^(\d+)\s*\/\s*(\d+)\s*/)
  if (fractionMatch) {
    return { value: Number(fractionMatch[1]) / Number(fractionMatch[2]), rest: text.slice(fractionMatch[0].length) }
  }
  const numMatch = text.match(/^(\d*\.?\d+)\s*/)
  if (numMatch) {
    return { value: Number(numMatch[1]), rest: text.slice(numMatch[0].length) }
  }
  return { value: null, rest: text }
}

function parseIngredientLine(line: string, unitOptions: UnitOption[]) {
  const { value: quantity, rest } = parseQuantity(line.trim())
  let remaining = rest.trim()
  let unitId: string | null = null
  const words = remaining.split(/\s+/)
  for (const wordCount of [2, 1]) {
    if (words.length < wordCount) continue
    const candidate = words.slice(0, wordCount).join(' ').toLowerCase().replace(/[.,]/g, '')
    const match = unitOptions.find((u) =>
      [u.name_singular, u.name_plural, u.abbrev_singular, u.abbrev_plural]
        .filter((v): v is string => !!v)
        .some((v) => v.toLowerCase() === candidate),
    )
    if (match) {
      unitId = match.id
      remaining = words.slice(wordCount).join(' ')
      break
    }
  }
  const [itemNamePart, ...noteParts] = remaining.split(',')
  return {
    quantity,
    unitId,
    itemName: itemNamePart.trim(),
    note: noteParts.join(',').trim() || null,
  }
}

async function importFromUrl() {
  if (!space.value || !importUrl.value.trim()) return
  importError.value = ''
  importing.value = true

  try {
    const result = await $fetch<{
      name: string
      description: string | null
      imageUrl: string | null
      servings: string | null
      prepTimeMinutes: number | null
      cookTimeMinutes: number | null
      totalTimeMinutes: number | null
      ingredientLines: string[]
      steps: string[]
    }>('/api/recipes/import', { method: 'POST', body: { url: importUrl.value.trim() } })

    const { data: recipeRow, error: insertError } = await supabase
      .from('recipes')
      .insert({
        space_id: space.value.id,
        name: result.name || 'Imported recipe',
        description: result.description,
        image_url: result.imageUrl,
        source_url: importUrl.value.trim(),
        servings: result.servings,
        prep_time_minutes: result.prepTimeMinutes,
        cook_time_minutes: result.cookTimeMinutes,
        total_time_minutes: result.totalTimeMinutes,
      })
      .select('id')
      .single()
    if (insertError || !recipeRow) throw new Error(insertError?.message ?? 'Failed to create recipe')

    if (result.steps.length > 0) {
      await supabase.from('recipe_steps').insert(
        result.steps.map((instruction, i) => ({ recipe_id: recipeRow.id, step_number: i + 1, instruction })),
      )
    }

    if (result.ingredientLines.length > 0) {
      const { data: itemOptions } = await supabase.from('items').select('id, name').is('deleted_at', null)
      const { data: unitOptions } = await supabase
        .from('units')
        .select('id, name_singular, name_plural, abbrev_singular, abbrev_plural')
        .is('deleted_at', null)

      const items = itemOptions ?? []
      for (let i = 0; i < result.ingredientLines.length; i++) {
        const parsed = parseIngredientLine(result.ingredientLines[i], unitOptions ?? [])
        if (!parsed.itemName) continue

        let item = items.find((it) => it.name.toLowerCase() === parsed.itemName.toLowerCase())
        if (!item) {
          const { data: newItem } = await supabase
            .from('items')
            .insert({ space_id: space.value.id, name: parsed.itemName })
            .select('id, name')
            .single()
          if (newItem) {
            items.push(newItem)
            item = newItem
          }
        }
        if (!item) continue

        await supabase.from('recipe_ingredients').insert({
          recipe_id: recipeRow.id,
          item_id: item.id,
          quantity: parsed.quantity,
          unit_id: parsed.unitId,
          note: parsed.note,
          sort_order: i,
        })
      }
    }

    await navigateTo(`/recipes/${recipeRow.id}`)
  } catch (err: any) {
    importError.value = err?.data?.statusMessage ?? err?.message ?? 'Import failed'
  } finally {
    importing.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <div class="mb-4 flex items-center justify-between">
      <h1 class="text-xl font-semibold">Recipes</h1>
      <UButton to="/equipment" variant="outline" size="sm">Manage equipment</UButton>
    </div>

    <form class="mb-4 flex gap-2" @submit.prevent="createRecipe">
      <UInput v-model="newName" placeholder="New recipe name" required class="flex-1" />
      <UButton type="submit" :loading="creating">Add</UButton>
    </form>
    <p v-if="createError" class="mb-4 text-sm text-red-500">{{ createError }}</p>

    <form class="mb-6 flex gap-2 rounded border border-default p-3" @submit.prevent="importFromUrl">
      <UInput v-model="importUrl" placeholder="Import from URL..." class="flex-1" />
      <UButton type="submit" :loading="importing" variant="outline">Import</UButton>
    </form>
    <p v-if="importError" class="mb-4 text-sm text-red-500">{{ importError }}</p>

    <div class="mb-4 flex gap-2">
      <UButton size="sm" :variant="filter === 'all' ? 'solid' : 'ghost'" @click="filter = 'all'">All</UButton>
      <UButton
        size="sm"
        :variant="filter === 'favorites' ? 'solid' : 'ghost'"
        @click="filter = 'favorites'"
      >
        Favorites
      </UButton>
      <UButton
        size="sm"
        :variant="filter === 'interested' ? 'solid' : 'ghost'"
        @click="filter = 'interested'"
      >
        Interested
      </UButton>
    </div>

    <ul class="flex flex-col gap-2">
      <li
        v-for="recipe in visibleRecipes"
        :key="recipe.id"
        class="flex items-center justify-between rounded border border-default px-3 py-2"
      >
        <NuxtLink :to="`/recipes/${recipe.id}`" class="flex-1">
          <span class="font-medium">{{ recipe.name }}</span>
          <UIcon v-if="recipe.is_favorite" name="i-lucide-heart" class="ml-2 text-red-500" />
          <UIcon v-if="recipe.is_interested" name="i-lucide-bookmark" class="ml-1 text-amber-500" />
          <UBadge
            v-for="rc in recipe.recipe_categories"
            :key="rc.categories!.id"
            size="sm"
            :variant="rc.categories!.parent_id ? 'subtle' : 'solid'"
            class="ml-2"
          >
            {{ rc.categories!.name }}
          </UBadge>
          <UBadge v-for="t in recipe.recipe_tags" :key="t.tags!.id" size="sm" variant="outline" class="ml-2">
            {{ t.tags!.name }}
          </UBadge>
          <span v-if="recipe.prep_time_minutes || recipe.cook_time_minutes" class="text-muted ml-2 text-sm">
            <span v-if="recipe.prep_time_minutes">Prep {{ recipe.prep_time_minutes }}m</span>
            <span v-if="recipe.cook_time_minutes"> Cook {{ recipe.cook_time_minutes }}m</span>
          </span>
        </NuxtLink>
        <UButton
          size="sm"
          variant="ghost"
          color="error"
          icon="i-lucide-trash-2"
          @click="deleteRecipe(recipe.id)"
        />
      </li>
      <li v-if="visibleRecipes.length === 0" class="text-muted text-sm">No recipes yet.</li>
    </ul>
  </div>
</template>
