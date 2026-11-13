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
      id, name, prep_time_minutes, cook_time_minutes, is_favorite, is_interested,
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
    <div class="mb-4 flex items-center justify-between">
      <h1 class="text-xl font-semibold">Recipes</h1>
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
              v-for="rc in recipe.recipe_category_links"
              :key="rc.recipe_categories!.id"
              size="sm"
              :variant="rc.recipe_categories!.parent_id ? 'subtle' : 'solid'"
              class="ml-2"
            >
              {{ rc.recipe_categories!.name }}
            </UBadge>
            <UBadge v-for="t in recipe.recipe_tag_links" :key="t.recipe_tags!.id" size="sm" variant="outline" class="ml-2">
              {{ t.recipe_tags!.name }}
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
