<script setup lang="ts">
type Option = { id: string; name: string; plural_name?: string | null }
type UnitOption = {
  id: string
  name_singular: string
  name_plural: string
  abbrev_singular: string | null
  abbrev_plural: string | null
}
const UNIT_FILTER_FIELDS = ['name_singular', 'name_plural', 'abbrev_singular', 'abbrev_plural']
const ITEM_FILTER_FIELDS = ['name', 'plural_name']

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()
const { resolveItem } = useResolveMasterItem()

const { data: recipes, refresh } = await useAsyncData('recipes', async () => {
  const { data, error } = await supabase
    .from('recipes')
    .select(`
      id, name, image_url, prep_time_minutes, cook_time_minutes, is_favorite, is_interested,
      recipe_category_links(recipe_categories(id, name, parent_id)),
      recipe_tag_links(recipe_tags(id, name))
    `)
    .is('deleted_at', null)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data
})

const itemOptions = ref<Option[]>([])
const { data: itemOptionsInitial } = await useAsyncData('item-options', async () => {
  const { data, error } = await supabase
    .from('items')
    .select('id, name, plural_name')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data
})
itemOptions.value = itemOptionsInitial.value ?? []

const { data: unitOptions } = await useAsyncData('unit-options', async () => {
  const { data, error } = await supabase
    .from('units')
    .select('id, name_singular, name_plural, abbrev_singular, abbrev_plural')
    .is('deleted_at', null)
    .order('name_singular')
  if (error) throw error
  return data as UnitOption[]
})

type RecipeOption = { id: string; name: string; parent_id: string | null }
type RecipeRow = NonNullable<typeof recipes.value>[number]

const { data: recipeCategoryOptions } = await useAsyncData('recipe-category-options', async () => {
  const { data, error } = await supabase
    .from('recipe_categories')
    .select('id, name, parent_id')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data as RecipeOption[]
})

const { data: recipeTagOptions } = await useAsyncData('recipe-tag-options', async () => {
  const { data, error } = await supabase
    .from('recipe_tags')
    .select('id, name')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data as Option[]
})

const filter = ref<'all' | 'favorites' | 'interested'>('all')
const filterCategories = ref<RecipeOption[]>([])
const filterTags = ref<Option[]>([])

const filteredRecipes = computed(() => {
  let list = recipes.value ?? []
  if (filter.value === 'favorites') list = list.filter((r) => r.is_favorite)
  if (filter.value === 'interested') list = list.filter((r) => r.is_interested)
  if (filterCategories.value.length > 0) {
    const ids = new Set(filterCategories.value.map((c) => c.id))
    list = list.filter((r) => r.recipe_category_links.some((rc) => ids.has(rc.recipe_categories!.id)))
  }
  if (filterTags.value.length > 0) {
    const ids = new Set(filterTags.value.map((t) => t.id))
    list = list.filter((r) => r.recipe_tag_links.some((rt) => ids.has(rt.recipe_tags!.id)))
  }
  return list
})

const {
  sortBy,
  groupBy,
  sortOptions,
  groupOptions,
  sortedItems: visibleRecipes,
  groupedItems: groupedRecipes,
} = useListControls<RecipeRow>(
  filteredRecipes,
  {
    'name-asc': { label: 'Name (A–Z)', compare: (a, b) => a.name.localeCompare(b.name) },
    'name-desc': { label: 'Name (Z–A)', compare: (a, b) => b.name.localeCompare(a.name) },
    'prep-asc': {
      label: 'Prep time (short to long)',
      compare: (a, b) => (a.prep_time_minutes ?? Infinity) - (b.prep_time_minutes ?? Infinity),
    },
    'cook-asc': {
      label: 'Cook time (short to long)',
      compare: (a, b) => (a.cook_time_minutes ?? Infinity) - (b.cook_time_minutes ?? Infinity),
    },
  },
  {
    category: {
      label: 'Category',
      getKeys: (r) =>
        r.recipe_category_links.length > 0
          ? r.recipe_category_links.map((rc) => rc.recipe_categories!.name)
          : ['Uncategorized'],
    },
    tag: {
      label: 'Tag',
      getKeys: (r) =>
        r.recipe_tag_links.length > 0 ? r.recipe_tag_links.map((rt) => rt.recipe_tags!.name) : ['Untagged'],
    },
  },
)

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

// --- import from URL: fetch + parse into a draft, write nothing until Save ---

type DraftIngredient = {
  key: string
  item: Option
  quantity: number | null
  unitId: string | null
  note: string
}

type ImportDraft = {
  name: string
  description: string
  imageUrl: string
  sourceUrl: string
  servings: string
  prepTimeMinutes: number | null
  cookTimeMinutes: number | null
  totalTimeMinutes: number | null
  steps: string[]
  ingredients: DraftIngredient[]
}

const importUrl = ref('')
const importing = ref(false)
const importError = ref('')
const importDraft = ref<ImportDraft | null>(null)

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

function parseIngredientLine(line: string, units: UnitOption[]) {
  const { value: quantity, rest } = parseQuantity(line.trim())
  let remaining = rest.trim()
  let unitId: string | null = null
  const words = remaining.split(/\s+/)
  for (const wordCount of [2, 1]) {
    if (words.length < wordCount) continue
    const candidate = words.slice(0, wordCount).join(' ').toLowerCase().replace(/[.,]/g, '')
    const match = units.find((u) =>
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
  if (!importUrl.value.trim()) return
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

    const draftIngredients: DraftIngredient[] = result.ingredientLines.map((line) => {
      const parsed = parseIngredientLine(line, unitOptions.value ?? [])
      const target = parsed.itemName.toLowerCase()
      const existing = itemOptions.value.find(
        (it) => it.name.toLowerCase() === target || it.plural_name?.toLowerCase() === target,
      )
      return {
        key: crypto.randomUUID(),
        item: existing ? { id: existing.id, name: existing.name } : { id: '', name: parsed.itemName },
        quantity: parsed.quantity,
        unitId: parsed.unitId,
        note: parsed.note ?? '',
      }
    })

    importDraft.value = {
      name: result.name || 'Imported recipe',
      description: result.description ?? '',
      imageUrl: result.imageUrl ?? '',
      sourceUrl: importUrl.value.trim(),
      servings: result.servings ?? '',
      prepTimeMinutes: result.prepTimeMinutes,
      cookTimeMinutes: result.cookTimeMinutes,
      totalTimeMinutes: result.totalTimeMinutes,
      steps: [...result.steps],
      ingredients: draftIngredients,
    }
  } catch (err: any) {
    importError.value = err?.data?.statusMessage ?? err?.message ?? 'Import failed'
  } finally {
    importing.value = false
  }
}

function cancelImportDraft() {
  importDraft.value = null
  importUrl.value = ''
  importError.value = ''
}

function addDraftIngredient() {
  importDraft.value?.ingredients.push({
    key: crypto.randomUUID(),
    item: { id: '', name: '' },
    quantity: null,
    unitId: null,
    note: '',
  })
}

function removeDraftIngredient(key: string) {
  if (!importDraft.value) return
  importDraft.value.ingredients = importDraft.value.ingredients.filter((i) => i.key !== key)
}

function addDraftStep() {
  importDraft.value?.steps.push('')
}

function removeDraftStep(index: number) {
  importDraft.value?.steps.splice(index, 1)
}

const savingImport = ref(false)
const saveImportError = ref('')

async function saveImportDraft() {
  if (!importDraft.value || !space.value) return
  saveImportError.value = ''
  savingImport.value = true
  const draft = importDraft.value

  const { data: recipeRow, error: insertError } = await supabase
    .from('recipes')
    .insert({
      space_id: space.value.id,
      name: draft.name.trim() || 'Imported recipe',
      description: draft.description.trim() || null,
      image_url: draft.imageUrl.trim() || null,
      source_url: draft.sourceUrl || null,
      servings: draft.servings.trim() || null,
      prep_time_minutes: draft.prepTimeMinutes,
      cook_time_minutes: draft.cookTimeMinutes,
      total_time_minutes: draft.totalTimeMinutes,
    })
    .select('id')
    .single()
  if (insertError || !recipeRow) {
    savingImport.value = false
    saveImportError.value = insertError?.message ?? 'Failed to save recipe'
    return
  }

  const steps = draft.steps.map((s) => s.trim()).filter(Boolean)
  if (steps.length > 0) {
    await supabase.from('recipe_steps').insert(
      steps.map((instruction, i) => ({ recipe_id: recipeRow.id, step_number: i + 1, instruction })),
    )
  }

  for (let i = 0; i < draft.ingredients.length; i++) {
    const row = draft.ingredients[i]!
    if (!row.item.name.trim()) continue
    const { itemId, name } = await resolveItem(space.value.id, row.item, true, itemOptions)
    await supabase.from('recipe_ingredients').insert({
      recipe_id: recipeRow.id,
      item_id: itemId,
      name,
      quantity: row.quantity,
      unit_id: row.unitId,
      note: row.note.trim() || null,
      sort_order: i,
    })
  }

  savingImport.value = false
  importDraft.value = null
  await navigateTo(`/recipes/${recipeRow.id}`)
}
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <div class="mb-4 flex justify-end">
      <UButton to="/recipe-categories" variant="outline" size="sm">Manage recipe categories</UButton>
    </div>

    <template v-if="!importDraft">
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

      <div class="mb-4 grid grid-cols-1 gap-2 sm:grid-cols-2">
        <div>
          <label class="text-muted mb-1 block text-xs">Sort by</label>
          <USelect v-model="sortBy" :items="sortOptions" class="w-full" />
        </div>
        <div>
          <label class="text-muted mb-1 block text-xs">Group by</label>
          <USelect v-model="groupBy" :items="groupOptions" class="w-full" />
        </div>
        <div>
          <label class="text-muted mb-1 block text-xs">Filter by category</label>
          <UInputMenu
            v-model="filterCategories"
            :items="recipeCategoryOptions ?? []"
            multiple
            label-key="name"
            placeholder="Any category"
            class="w-full"
          />
        </div>
        <div>
          <label class="text-muted mb-1 block text-xs">Filter by tag</label>
          <UInputMenu
            v-model="filterTags"
            :items="recipeTagOptions ?? []"
            multiple
            label-key="name"
            placeholder="Any tag"
            class="w-full"
          />
        </div>
      </div>

      <template v-if="groupedRecipes">
        <div v-for="[groupName, groupRecipes] in groupedRecipes" :key="groupName" class="mb-4">
          <h2 class="mb-2 text-sm font-semibold text-muted">{{ groupName }}</h2>
          <ul class="flex flex-col gap-2">
            <li
              v-for="recipe in groupRecipes"
              :key="recipe.id"
              class="flex items-center justify-between rounded border border-default px-3 py-2"
            >
              <NuxtLink :to="`/recipes/${recipe.id}`" class="flex flex-1 items-center gap-2">
                <img
                  v-if="recipe.image_url"
                  :src="recipe.image_url"
                  alt=""
                  class="h-10 w-10 shrink-0 rounded object-cover"
                  @error="(e) => ((e.target as HTMLImageElement).style.display = 'none')"
                />
                <div class="flex flex-wrap items-center gap-1">
                  <span class="font-medium">{{ recipe.name }}</span>
                  <UIcon v-if="recipe.is_favorite" name="i-lucide-heart" class="text-red-500" />
                  <UIcon v-if="recipe.is_interested" name="i-lucide-bookmark" class="text-amber-500" />
                  <UBadge
                    v-for="rc in recipe.recipe_category_links"
                    :key="rc.recipe_categories!.id"
                    size="sm"
                    :variant="rc.recipe_categories!.parent_id ? 'subtle' : 'solid'"
                  >
                    {{ rc.recipe_categories!.name }}
                  </UBadge>
                  <UBadge v-for="t in recipe.recipe_tag_links" :key="t.recipe_tags!.id" size="sm" variant="outline">
                    {{ t.recipe_tags!.name }}
                  </UBadge>
                  <span v-if="recipe.prep_time_minutes || recipe.cook_time_minutes" class="text-muted text-sm">
                    <span v-if="recipe.prep_time_minutes">Prep {{ recipe.prep_time_minutes }}m</span>
                    <span v-if="recipe.cook_time_minutes"> Cook {{ recipe.cook_time_minutes }}m</span>
                  </span>
                </div>
              </NuxtLink>
              <UButton
                size="sm"
                variant="ghost"
                color="error"
                icon="i-lucide-trash-2"
                @click="deleteRecipe(recipe.id)"
              />
            </li>
          </ul>
        </div>
        <p v-if="groupedRecipes.length === 0" class="text-muted text-sm">No recipes match.</p>
      </template>

      <ul v-else class="flex flex-col gap-2">
        <li
          v-for="recipe in visibleRecipes"
          :key="recipe.id"
          class="flex items-center justify-between rounded border border-default px-3 py-2"
        >
          <NuxtLink :to="`/recipes/${recipe.id}`" class="flex flex-1 items-center gap-2">
            <img
              v-if="recipe.image_url"
              :src="recipe.image_url"
              alt=""
              class="h-10 w-10 shrink-0 rounded object-cover"
              @error="(e) => ((e.target as HTMLImageElement).style.display = 'none')"
            />
            <div class="flex flex-wrap items-center gap-1">
              <span class="font-medium">{{ recipe.name }}</span>
              <UIcon v-if="recipe.is_favorite" name="i-lucide-heart" class="text-red-500" />
              <UIcon v-if="recipe.is_interested" name="i-lucide-bookmark" class="text-amber-500" />
              <UBadge
                v-for="rc in recipe.recipe_category_links"
                :key="rc.recipe_categories!.id"
                size="sm"
                :variant="rc.recipe_categories!.parent_id ? 'subtle' : 'solid'"
              >
                {{ rc.recipe_categories!.name }}
              </UBadge>
              <UBadge v-for="t in recipe.recipe_tag_links" :key="t.recipe_tags!.id" size="sm" variant="outline">
                {{ t.recipe_tags!.name }}
              </UBadge>
              <span v-if="recipe.prep_time_minutes || recipe.cook_time_minutes" class="text-muted text-sm">
                <span v-if="recipe.prep_time_minutes">Prep {{ recipe.prep_time_minutes }}m</span>
                <span v-if="recipe.cook_time_minutes"> Cook {{ recipe.cook_time_minutes }}m</span>
              </span>
            </div>
          </NuxtLink>
          <UButton
            size="sm"
            variant="ghost"
            color="error"
            icon="i-lucide-trash-2"
            @click="deleteRecipe(recipe.id)"
          />
        </li>
        <li v-if="visibleRecipes.length === 0" class="text-muted text-sm">No recipes match.</li>
      </ul>
    </template>

    <template v-else>
      <div class="mb-4 flex items-center justify-between">
        <h2 class="text-lg font-semibold">Review import</h2>
        <UButton variant="ghost" @click="cancelImportDraft">Cancel</UButton>
      </div>

      <div class="mb-4 flex flex-col gap-2 rounded border border-default p-3">
        <UFormField label="Name">
          <UInput v-model="importDraft.name" class="w-full" />
        </UFormField>
        <UFormField label="Description" hint="Optional">
          <UTextarea v-model="importDraft.description" class="w-full" />
        </UFormField>
        <UFormField label="Image URL" hint="Optional">
          <UInput v-model="importDraft.imageUrl" class="w-full" />
        </UFormField>
        <div class="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <UFormField label="Prep time" hint="Minutes">
            <UInputNumber v-model="importDraft.prepTimeMinutes" :min="0" class="w-full" />
          </UFormField>
          <UFormField label="Cook time" hint="Minutes">
            <UInputNumber v-model="importDraft.cookTimeMinutes" :min="0" class="w-full" />
          </UFormField>
          <UFormField label="Total time" hint="Minutes">
            <UInputNumber v-model="importDraft.totalTimeMinutes" :min="0" class="w-full" />
          </UFormField>
          <UFormField label="Servings">
            <UInput v-model="importDraft.servings" class="w-full" />
          </UFormField>
        </div>
      </div>

      <h3 class="mb-2 font-semibold">Ingredients</h3>
      <ul class="mb-2 flex flex-col gap-2">
        <li
          v-for="row in importDraft.ingredients"
          :key="row.key"
          class="rounded border border-default px-3 py-2"
        >
          <div class="flex flex-col gap-2">
            <RecipeItemField v-model:item="row.item" :item-options="itemOptions" />
            <div class="grid grid-cols-2 gap-2">
              <UInputNumber v-model="row.quantity" placeholder="Qty" :min="0" />
              <UInputMenu
                v-model="row.unitId"
                :items="unitOptions ?? []"
                value-key="id"
                label-key="name_singular"
                :filter-fields="UNIT_FILTER_FIELDS"
                placeholder="Unit"
              />
            </div>
            <div class="flex gap-2">
              <UInput v-model="row.note" placeholder="Note (optional)" class="flex-1" />
              <UButton
                size="sm"
                variant="ghost"
                color="error"
                icon="i-lucide-trash-2"
                @click="removeDraftIngredient(row.key)"
              />
            </div>
          </div>
        </li>
        <li v-if="importDraft.ingredients.length === 0" class="text-muted text-sm">No ingredients parsed.</li>
      </ul>
      <UButton size="sm" variant="outline" class="mb-6" @click="addDraftIngredient">Add ingredient row</UButton>

      <h3 class="mb-2 font-semibold">Steps</h3>
      <ul class="mb-2 flex flex-col gap-2">
        <li v-for="(_, index) in importDraft.steps" :key="index" class="flex gap-2">
          <UTextarea v-model="importDraft.steps[index]" class="flex-1" />
          <UButton size="sm" variant="ghost" color="error" icon="i-lucide-trash-2" @click="removeDraftStep(index)" />
        </li>
        <li v-if="importDraft.steps.length === 0" class="text-muted text-sm">No steps parsed.</li>
      </ul>
      <UButton size="sm" variant="outline" class="mb-6" @click="addDraftStep">Add step</UButton>

      <p v-if="saveImportError" class="mb-4 text-sm text-red-500">{{ saveImportError }}</p>
      <UButton block :loading="savingImport" @click="saveImportDraft">Save recipe</UButton>
    </template>
  </div>
</template>
