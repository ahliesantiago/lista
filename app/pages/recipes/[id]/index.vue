<script setup lang="ts">
type Option = { id: string; name: string; plural_name?: string | null }
type CategoryOption = { id: string; name: string; parent_id: string | null }
type UnitOption = {
  id: string
  name_singular: string
  name_plural: string
  abbrev_singular: string | null
  abbrev_plural: string | null
}
const UNIT_FILTER_FIELDS = ['name_singular', 'name_plural', 'abbrev_singular', 'abbrev_plural']
const ITEM_FILTER_FIELDS = ['name', 'plural_name']
const MAX_CATEGORIES = 2
const MAX_SUBCATEGORIES = 2

const route = useRoute()
const recipeId = route.params.id as string

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: recipe } = await useAsyncData(`recipe-${recipeId}`, async () => {
  const { data, error } = await supabase
    .from('recipes')
    .select(`
      id, name, description, image_url, source_url, servings,
      prep_time_minutes, cook_time_minutes, total_time_minutes,
      is_favorite, is_interested,
      recipe_category_links(recipe_categories(id, name, parent_id)),
      recipe_tag_links(recipe_tags(id, name)),
      recipe_equipment(equipment(id, name))
    `)
    .eq('id', recipeId)
    .is('deleted_at', null)
    .single()
  if (error) throw error
  return data
})

const pageEntityName = usePageEntityName()
watchEffect(() => {
  pageEntityName.value = recipe.value?.name ?? null
})
onUnmounted(() => {
  pageEntityName.value = null
})

const { data: steps, refresh: refreshSteps } = await useAsyncData(`recipe-steps-${recipeId}`, async () => {
  const { data, error } = await supabase
    .from('recipe_steps')
    .select('id, step_number, instruction')
    .eq('recipe_id', recipeId)
    .order('step_number')
  if (error) throw error
  return data
})

const { data: ingredients, refresh: refreshIngredients } = await useAsyncData(
  `recipe-ingredients-${recipeId}`,
  async () => {
    const { data, error } = await supabase
      .from('recipe_ingredients')
      .select(`
        id, name, quantity, note, sort_order,
        item:items!recipe_ingredients_item_id_fkey(id, name),
        unit:units(id, name_singular, name_plural),
        recipe_ingredient_alternatives(item:items(id, name))
      `)
      .eq('recipe_id', recipeId)
      .order('sort_order')
    if (error) throw error
    return data
  },
)

function ingredientDisplayName(ing: { name: string; item: { name: string } | null }) {
  return ing.item?.name ?? ing.name
}

const { data: categoryOptions } = await useAsyncData('recipe-category-options', async () => {
  const { data, error } = await supabase
    .from('recipe_categories')
    .select('id, name, parent_id')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data as CategoryOption[]
})
const topLevelCategoryOptions = computed(() => categoryOptions.value?.filter((c) => !c.parent_id) ?? [])

const tagOptions = ref<Option[]>([])
const { data: tagOptionsInitial } = await useAsyncData('recipe-tag-options', async () => {
  const { data, error } = await supabase.from('recipe_tags').select('id, name').is('deleted_at', null).order('name')
  if (error) throw error
  return data
})
tagOptions.value = tagOptionsInitial.value ?? []

const equipmentOptions = ref<Option[]>([])
const { data: equipmentOptionsInitial } = await useAsyncData('equipment-options', async () => {
  const { data, error } = await supabase.from('equipment').select('id, name').is('deleted_at', null).order('name')
  if (error) throw error
  return data
})
equipmentOptions.value = equipmentOptionsInitial.value ?? []

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

function unitLabel(unit: { name_singular: string; name_plural: string } | null, amount: number | null) {
  if (!unit) return ''
  return amount != null && amount !== 1 ? unit.name_plural : unit.name_singular
}

// --- editable header ---

const name = ref(recipe.value?.name ?? '')
const description = ref(recipe.value?.description ?? '')
const imageUrl = ref(recipe.value?.image_url ?? '')
const servings = ref(recipe.value?.servings ?? '')
const prepTime = ref<number | null>(recipe.value?.prep_time_minutes ?? null)
const cookTime = ref<number | null>(recipe.value?.cook_time_minutes ?? null)
const totalTime = ref<number | null>(recipe.value?.total_time_minutes ?? null)
// dedicated refs (not read/written on `recipe.value` directly) so toggling
// is always instantly reactive, same as every other editable field here
const isFavorite = ref(recipe.value?.is_favorite ?? false)
const isInterested = ref(recipe.value?.is_interested ?? false)

const viewMode = ref<'view' | 'edit'>(route.query.new === '1' ? 'edit' : 'view')
const imageLoadFailed = ref(false)
watch(imageUrl, () => {
  imageLoadFailed.value = false
})

const linkedCategories = recipe.value?.recipe_category_links.map((rc) => rc.recipe_categories!) ?? []
const selectedCategories = ref<CategoryOption[]>(linkedCategories.filter((c) => !c.parent_id))
const selectedSubcategories = ref<CategoryOption[]>(linkedCategories.filter((c) => c.parent_id))
const recipeTags = ref<Option[]>(recipe.value?.recipe_tag_links.map((rt) => rt.recipe_tags!) ?? [])
const recipeEquipment = ref<Option[]>(recipe.value?.recipe_equipment.map((re) => re.equipment!) ?? [])

const subcategoryOptions = computed(() => {
  const parentIds = new Set(selectedCategories.value.map((c) => c.id))
  return categoryOptions.value?.filter((c) => c.parent_id && parentIds.has(c.parent_id)) ?? []
})

async function saveRecipeField(patch: Record<string, unknown>) {
  await supabase.from('recipes').update(patch).eq('id', recipeId)
}

async function toggleFavorite() {
  isFavorite.value = !isFavorite.value
  await saveRecipeField({ is_favorite: isFavorite.value })
}

async function toggleInterested() {
  isInterested.value = !isInterested.value
  await saveRecipeField({ is_interested: isInterested.value })
}

watch(selectedCategories, async (newVal, oldVal) => {
  if (newVal.length > MAX_CATEGORIES) {
    selectedCategories.value = newVal.slice(0, MAX_CATEGORIES)
    return
  }
  const parentIds = new Set(newVal.map((c) => c.id))
  selectedSubcategories.value = selectedSubcategories.value.filter(
    (s) => s.parent_id && parentIds.has(s.parent_id),
  )
  const added = newVal.filter((c) => !oldVal.some((o) => o.id === c.id))
  const removed = oldVal.filter((o) => !newVal.some((c) => c.id === o.id))
  if (added.length > 0) {
    await supabase
      .from('recipe_category_links')
      .insert(added.map((c) => ({ recipe_id: recipeId, category_id: c.id })))
  }
  for (const r of removed) {
    await supabase.from('recipe_category_links').delete().eq('recipe_id', recipeId).eq('category_id', r.id)
  }
})

watch(selectedSubcategories, async (newVal, oldVal) => {
  if (newVal.length > MAX_SUBCATEGORIES) {
    selectedSubcategories.value = newVal.slice(0, MAX_SUBCATEGORIES)
    return
  }
  const added = newVal.filter((c) => !oldVal.some((o) => o.id === c.id))
  const removed = oldVal.filter((o) => !newVal.some((c) => c.id === o.id))
  if (added.length > 0) {
    await supabase
      .from('recipe_category_links')
      .insert(added.map((c) => ({ recipe_id: recipeId, category_id: c.id })))
  }
  for (const r of removed) {
    await supabase.from('recipe_category_links').delete().eq('recipe_id', recipeId).eq('category_id', r.id)
  }
})

watch(recipeTags, async (newVal, oldVal) => {
  const added = newVal.filter((t) => !oldVal.some((o) => o.id === t.id))
  const removed = oldVal.filter((o) => !newVal.some((t) => t.id === o.id))
  if (added.length > 0) {
    await supabase.from('recipe_tag_links').insert(added.map((t) => ({ recipe_id: recipeId, tag_id: t.id })))
  }
  for (const r of removed) {
    await supabase.from('recipe_tag_links').delete().eq('recipe_id', recipeId).eq('tag_id', r.id)
  }
})

watch(recipeEquipment, async (newVal, oldVal) => {
  const added = newVal.filter((e) => !oldVal.some((o) => o.id === e.id))
  const removed = oldVal.filter((o) => !newVal.some((e) => e.id === o.id))
  if (added.length > 0) {
    await supabase
      .from('recipe_equipment')
      .insert(added.map((e) => ({ recipe_id: recipeId, equipment_id: e.id })))
  }
  for (const r of removed) {
    await supabase.from('recipe_equipment').delete().eq('recipe_id', recipeId).eq('equipment_id', r.id)
  }
})

const { onCreateCategoryOption, onCreateSubcategoryOption } = useCategoryCreation(
  'recipe_categories',
  space,
  categoryOptions,
  selectedCategories,
  selectedSubcategories,
)

async function onCreateTagOption(searchTerm: string) {
  if (!space.value) return
  const { data, error: insertError } = await supabase
    .from('recipe_tags')
    .insert({ space_id: space.value.id, name: searchTerm })
    .select('id, name')
    .single()
  if (insertError || !data) return
  tagOptions.value.push(data)
  recipeTags.value.push(data)
}

async function onCreateEquipmentOption(searchTerm: string) {
  if (!space.value) return
  const { data, error: insertError } = await supabase
    .from('equipment')
    .insert({ space_id: space.value.id, name: searchTerm })
    .select('id, name')
    .single()
  if (insertError || !data) return
  equipmentOptions.value.push(data)
  recipeEquipment.value.push(data)
}

async function deleteRecipe() {
  await supabase.from('recipes').update({ deleted_at: new Date().toISOString() }).eq('id', recipeId)
  await navigateTo('/recipes')
}

// --- add to list (merges into an existing line when the item+unit already
// matches on that list, otherwise adds a new line; always records a
// list_item_sources row so the provenance breakdown stays honest even when
// units didn't match and nothing could be summed) ---

const { data: activeLists } = await useAsyncData('pantry-active-lists', async () => {
  const { data, error } = await supabase
    .from('lists')
    .select('id, name')
    .eq('status', 'active')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data
})

const listPicker = ref<Option | null>(null)
const addingToList = ref(false)
const addToListError = ref('')
const addToListResult = ref('')

function onCreateListOption(searchTerm: string) {
  listPicker.value = { id: '', name: searchTerm }
}

async function addRecipeToList() {
  if (!space.value || !listPicker.value || !listPicker.value.name.trim() || !ingredients.value) return
  addToListError.value = ''
  addToListResult.value = ''
  addingToList.value = true

  let listId = listPicker.value.id
  const listName = listPicker.value.name.trim()
  if (!listId) {
    const { data, error: insertError } = await supabase
      .from('lists')
      .insert({ space_id: space.value.id, name: listName })
      .select('id, name')
      .single()
    if (insertError || !data) {
      addingToList.value = false
      addToListError.value = insertError?.message ?? 'Failed to create list'
      return
    }
    listId = data.id
    activeLists.value = [...(activeLists.value ?? []), data]
  }

  let addedCount = 0
  let mergedCount = 0

  for (const ing of ingredients.value) {
    if (!ing.item) continue
    const { data: existingRows } = await supabase
      .from('list_items')
      .select('id, amount, unit_id')
      .eq('list_id', listId)
      .eq('item_id', ing.item.id)
      .is('deleted_at', null)
    const existing = existingRows?.[0]

    let listItemId: string
    if (existing) {
      const unitsMatch = (existing.unit_id ?? null) === (ing.unit?.id ?? null)
      if (unitsMatch && (existing.amount != null || ing.quantity != null)) {
        const newAmount = (existing.amount ?? 0) + (ing.quantity ?? 0)
        await supabase.from('list_items').update({ amount: newAmount }).eq('id', existing.id)
      }
      if (unitsMatch) mergedCount++
      listItemId = existing.id
    } else {
      const { data: newRow } = await supabase
        .from('list_items')
        .insert({
          list_id: listId,
          item_id: ing.item.id,
          name: ing.item.name,
          amount: ing.quantity,
          unit_id: ing.unit?.id ?? null,
        })
        .select('id')
        .single()
      if (!newRow) continue
      listItemId = newRow.id
      addedCount++
    }

    await supabase.from('list_item_sources').insert({
      list_item_id: listItemId,
      recipe_id: recipeId,
      quantity: ing.quantity,
      unit_id: ing.unit?.id ?? null,
    })
  }

  addingToList.value = false
  addToListResult.value = `Added to "${listName}": ${addedCount} new, ${mergedCount} merged.`
  listPicker.value = null
}

// --- mark as cooked: deduct each ingredient from matching pantry stock,
// exact item+unit match only - no conversion, mismatches are skipped ---

const markingCooked = ref(false)
const markCookedResult = ref('')

async function markAsCooked() {
  if (!ingredients.value) return
  markingCooked.value = true
  markCookedResult.value = ''
  let deducted = 0
  let skipped = 0

  for (const ing of ingredients.value) {
    if (!ing.item || ing.quantity == null) {
      skipped++
      continue
    }
    let query = supabase.from('inventory_items').select('id, quantity').eq('item_id', ing.item.id).is('deleted_at', null)
    query = ing.unit?.id ? query.eq('unit_id', ing.unit.id) : query.is('unit_id', null)
    const { data: matches } = await query
    const match = matches?.[0]

    if (match && match.quantity != null) {
      const next = Math.max(0, match.quantity - ing.quantity)
      await supabase.from('inventory_items').update({ quantity: next }).eq('id', match.id)
      deducted++
    } else {
      skipped++
    }
  }

  markingCooked.value = false
  markCookedResult.value = `Deducted ${deducted} of ${ingredients.value.length} ingredients from pantry; ${skipped} skipped — no matching stock or unit.`
}

// --- ingredients ---

type Ingredient = NonNullable<typeof ingredients.value>[number]

const ingredientItem = ref<Option | null>(null)
const ingredientQuantity = ref<number | null>(null)
const ingredientUnitId = ref<string | null>(null)
const ingredientNote = ref('')
const ingredientAlternatives = ref<Option[]>([])
const ingredientError = ref('')

const { resolveItem } = useResolveMasterItem()

function resetIngredientForm() {
  ingredientItem.value = null
  ingredientQuantity.value = null
  ingredientUnitId.value = null
  ingredientNote.value = ''
  ingredientAlternatives.value = []
  ingredientError.value = ''
}

async function addIngredient() {
  if (!ingredientItem.value || !ingredientItem.value.name.trim()) return
  ingredientError.value = ''
  const { itemId, name: resolvedName } = await resolveItem(
    space.value!.id,
    ingredientItem.value,
    true,
    itemOptions
  )
  const { data, error: insertError } = await supabase
    .from('recipe_ingredients')
    .insert({
      recipe_id: recipeId,
      item_id: itemId,
      name: resolvedName,
      quantity: ingredientQuantity.value,
      unit_id: ingredientUnitId.value,
      note: ingredientNote.value.trim() || null,
      sort_order: ingredients.value?.length ?? 0,
    })
    .select('id')
    .single()
  if (insertError || !data) {
    ingredientError.value = insertError?.message ?? 'Failed to add ingredient'
    return
  }
  if (ingredientAlternatives.value.length > 0) {
    await supabase.from('recipe_ingredient_alternatives').insert(
      ingredientAlternatives.value.map((alt) => ({ recipe_ingredient_id: data.id, item_id: alt.id })),
    )
  }
  resetIngredientForm()
  await refreshIngredients()
}

async function deleteIngredient(id: string) {
  await supabase.from('recipe_ingredients').delete().eq('id', id)
  await refreshIngredients()
}

const editingIngredientId = ref<string | null>(null)
const editOriginalItemId = ref<string | null>(null)
const editIngredientName = ref('')
const editIngredientQuantity = ref<number | null>(null)
const editIngredientUnitId = ref<string | null>(null)
const editIngredientNote = ref('')
const editIngredientAlternatives = ref<Option[]>([])

function startEditIngredient(ing: Ingredient) {
  editingIngredientId.value = ing.id
  editOriginalItemId.value = ing.item?.id ?? null
  editIngredientName.value = ingredientDisplayName(ing)
  editIngredientQuantity.value = ing.quantity
  editIngredientUnitId.value = ing.unit?.id ?? null
  editIngredientNote.value = ing.note ?? ''
  editIngredientAlternatives.value = ing.recipe_ingredient_alternatives.map((a) => a.item!)
}

function cancelEditIngredient() {
  editingIngredientId.value = null
}

async function saveEditIngredient(id: string) {
  const name = editIngredientName.value.trim()
  if (!name) return

  let itemId = editOriginalItemId.value
  if (itemId) {
    await supabase.from('items').update({ name }).eq('id', itemId)
    const cached = itemOptions.value.find((o) => o.id === itemId)
    if (cached) cached.name = name
  } else {
    const resolved = await resolveItem(space.value!.id, { id: '', name }, true, itemOptions)
    itemId = resolved.itemId
  }

  await supabase
    .from('recipe_ingredients')
    .update({
      item_id: itemId,
      name,
      quantity: editIngredientQuantity.value,
      unit_id: editIngredientUnitId.value,
      note: editIngredientNote.value.trim() || null,
    })
    .eq('id', id)
  await supabase.from('recipe_ingredient_alternatives').delete().eq('recipe_ingredient_id', id)
  if (editIngredientAlternatives.value.length > 0) {
    await supabase.from('recipe_ingredient_alternatives').insert(
      editIngredientAlternatives.value.map((alt) => ({ recipe_ingredient_id: id, item_id: alt.id })),
    )
  }
  editingIngredientId.value = null
  await refreshIngredients()
}

// --- steps ---

const newStepText = ref('')

async function addStep() {
  const text = newStepText.value.trim()
  if (!text) return
  const nextNumber = (steps.value?.length ?? 0) + 1
  await supabase.from('recipe_steps').insert({ recipe_id: recipeId, step_number: nextNumber, instruction: text })
  newStepText.value = ''
  await refreshSteps()
}

async function deleteStep(id: string) {
  await supabase.from('recipe_steps').delete().eq('id', id)
  await refreshSteps()
}

/**
 * Reordering through a local-first approach with a
 * promise chain to persist the new order in the background.
 * Each reorder operation updates the local state immediately, and then
 * queues a persistence operation to update the database.
 */
let stepPersistQueue: Promise<unknown> = Promise.resolve()

function persistStepOrder() {
  stepPersistQueue = stepPersistQueue.then(async () => {
    if (!steps.value) return
    await Promise.all(
      steps.value.map((s) => supabase.from('recipe_steps').update({ step_number: s.step_number }).eq('id', s.id)),
    )
  })
}

function moveStep(index: number, direction: -1 | 1) {
  if (!steps.value) return
  const targetIndex = index + direction
  if (targetIndex < 0 || targetIndex >= steps.value.length) return
  // build a fresh array rather than splicing in place - useAsyncData's ref
  // isn't guaranteed to pick up in-place array mutations, only a reassigned
  // .value, which is what was making this only show up after a refetch
  const next = [...steps.value]
  const [moved] = next.splice(index, 1)
  next.splice(targetIndex, 0, moved!)
  next.forEach((s, i) => {
    s.step_number = i + 1
  })
  steps.value = next
  persistStepOrder()
}

const editingStepId = ref<string | null>(null)
const editStepText = ref('')

function startEditStep(step: { id: string; instruction: string }) {
  editingStepId.value = step.id
  editStepText.value = step.instruction
}

function cancelEditStep() {
  editingStepId.value = null
}

async function saveEditStep(id: string) {
  await supabase.from('recipe_steps').update({ instruction: editStepText.value.trim() }).eq('id', id)
  editingStepId.value = null
  await refreshSteps()
}
</script>

<template>
  <div v-if="recipe" class="mx-auto max-w-2xl">
    <div class="mb-4 flex flex-col items-start justify-between gap-4 sm:flex-row">
      <div v-if="viewMode === 'view'" class="flex-1">
        <img
          v-if="recipe.image_url && !imageLoadFailed"
          :src="recipe.image_url"
          alt=""
          class="mb-3 max-h-72 w-full rounded object-cover"
          @error="imageLoadFailed = true"
        />
        <h1 class="mb-1 text-lg font-semibold">{{ recipe.name }}</h1>
        <p v-if="recipe.description" class="text-muted mb-2 text-sm">{{ recipe.description }}</p>
        <a
          v-if="recipe.source_url"
          :href="recipe.source_url"
          target="_blank"
          rel="noopener"
          class="text-primary mb-2 block text-sm underline"
        >
          Source
        </a>
        <p v-if="prepTime || cookTime || totalTime || servings" class="text-muted mb-2 text-sm">
          <span v-if="prepTime">Prep {{ prepTime }}m</span>
          <span v-if="cookTime"> &middot; Cook {{ cookTime }}m</span>
          <span v-if="totalTime"> &middot; Total {{ totalTime }}m</span>
          <span v-if="servings"> &middot; {{ servings }}</span>
        </p>
        <div class="flex flex-wrap gap-1">
          <UBadge v-for="c in selectedCategories" :key="c.id" size="sm" variant="solid">{{ c.name }}</UBadge>
          <UBadge v-for="c in selectedSubcategories" :key="c.id" size="sm" variant="subtle">{{ c.name }}</UBadge>
          <UBadge v-for="t in recipeTags" :key="t.id" size="sm" variant="outline">{{ t.name }}</UBadge>
          <UBadge v-for="e in recipeEquipment" :key="e.id" size="sm" variant="outline" color="neutral">
            {{ e.name }}
          </UBadge>
        </div>
      </div>
      <div v-else class="flex-1">
        <UInput v-model="name" class="mb-2 w-full text-lg font-semibold" @blur="saveRecipeField({ name })" />
        <UTextarea
          v-model="description"
          placeholder="Description (optional)"
          class="mb-2 w-full"
          @blur="saveRecipeField({ description: description || null })"
        />
        <UInput
          v-model="imageUrl"
          placeholder="Image URL (optional)"
          class="mb-2 w-full"
          @blur="saveRecipeField({ image_url: imageUrl || null })"
        />
        <a
          v-if="recipe.source_url"
          :href="recipe.source_url"
          target="_blank"
          rel="noopener"
          class="text-primary mb-2 block text-sm underline"
        >
          Source
        </a>
        <div class="mb-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
          <UFormField label="Prep time" hint="Minutes">
            <UInputNumber
              v-model="prepTime"
              :min="0"
              class="w-full"
              @blur="saveRecipeField({ prep_time_minutes: prepTime })"
            />
          </UFormField>
          <UFormField label="Cook time" hint="Minutes">
            <UInputNumber
              v-model="cookTime"
              :min="0"
              class="w-full"
              @blur="saveRecipeField({ cook_time_minutes: cookTime })"
            />
          </UFormField>
          <UFormField label="Total time" hint="Minutes">
            <UInputNumber
              v-model="totalTime"
              :min="0"
              class="w-full"
              @blur="saveRecipeField({ total_time_minutes: totalTime })"
            />
          </UFormField>
          <UFormField label="Servings">
            <UInput
              v-model="servings"
              class="w-full"
              @blur="saveRecipeField({ servings: servings || null })"
            />
          </UFormField>
        </div>
        <div class="mb-2 flex gap-2">
          <UFormField label="Categories" hint="Up to 2 (optional)" class="flex-1">
            <UInputMenu
              v-model="selectedCategories"
              :items="topLevelCategoryOptions"
              multiple
              create-item
              label-key="name"
              class="w-full"
              @create="onCreateCategoryOption"
            />
          </UFormField>
          <UFormField label="Subcategories" hint="Up to 2 (optional)" class="flex-1">
            <UInputMenu
              v-model="selectedSubcategories"
              :items="subcategoryOptions"
              multiple
              create-item
              label-key="name"
              placeholder="Pick a category first"
              class="w-full"
              @create="onCreateSubcategoryOption"
            />
          </UFormField>
        </div>
        <UFormField label="Tags" hint="Optional" class="mb-2">
          <UInputMenu
            v-model="recipeTags"
            :items="tagOptions"
            multiple
            create-item
            label-key="name"
            class="w-full"
            @create="onCreateTagOption"
          />
        </UFormField>
        <UFormField label="Equipment" hint="Optional">
          <UInputMenu
            v-model="recipeEquipment"
            :items="equipmentOptions"
            multiple
            create-item
            label-key="name"
            class="w-full"
            @create="onCreateEquipmentOption"
          />
        </UFormField>
      </div>
      <div class="flex shrink-0 flex-col items-end gap-2">
        <div class="flex gap-1">
          <UButton
            size="sm"
            variant="ghost"
            icon="i-lucide-heart"
            :color="isFavorite ? 'error' : 'neutral'"
            @click="toggleFavorite"
          />
          <UButton
            size="sm"
            variant="ghost"
            icon="i-lucide-bookmark"
            :color="isInterested ? 'warning' : 'neutral'"
            @click="toggleInterested"
          />
        </div>
        <UButton
          size="sm"
          variant="outline"
          @click="viewMode = viewMode === 'view' ? 'edit' : 'view'"
        >
          {{ viewMode === 'view' ? 'Edit' : 'Done editing' }}
        </UButton>
        <UButton size="sm" variant="outline" :to="`/recipes/${recipeId}/cook`">Start cooking</UButton>

        <UPopover>
          <UButton size="sm" variant="outline">Add to list</UButton>
          <template #content>
            <div class="flex w-56 flex-col gap-2 p-3">
              <UInputMenu
                v-model="listPicker"
                :items="activeLists ?? []"
                create-item
                label-key="name"
                placeholder="Pick or create a list"
                @create="onCreateListOption"
              />
              <UButton size="sm" block :loading="addingToList" @click="addRecipeToList">Add</UButton>
            </div>
          </template>
        </UPopover>
        <p v-if="addToListResult" class="text-muted max-w-40 text-right text-xs">{{ addToListResult }}</p>
        <p v-if="addToListError" class="max-w-40 text-right text-xs text-red-500">{{ addToListError }}</p>

        <UButton size="sm" variant="outline" :loading="markingCooked" @click="markAsCooked">Mark as cooked</UButton>
        <p v-if="markCookedResult" class="text-muted max-w-40 text-right text-xs">{{ markCookedResult }}</p>

        <UButton size="sm" variant="outline" color="error" @click="deleteRecipe">Delete recipe</UButton>
      </div>
    </div>

    <h2 class="mb-2 text-lg font-semibold">Ingredients</h2>
    <ul class="mb-4 flex flex-col gap-2">
      <li v-for="ing in ingredients" :key="ing.id" class="rounded border border-default px-3 py-2">
        <div v-if="editingIngredientId !== ing.id" class="flex items-center justify-between">
          <span>
            <span v-if="ing.quantity != null" class="text-muted text-sm">
              {{ ing.quantity }}<span v-if="ing.unit">{{ ' ' + unitLabel(ing.unit, ing.quantity) }}</span>
            </span>
            <span class="ml-1 font-medium">{{ ingredientDisplayName(ing) }}</span>
            <span v-if="ing.note" class="text-muted text-sm">, {{ ing.note }}</span>
            <span v-if="ing.recipe_ingredient_alternatives.length > 0" class="text-muted block text-xs">
              or: {{ ing.recipe_ingredient_alternatives.map((a) => a.item!.name).join(', ') }}
            </span>
          </span>
          <div v-if="viewMode === 'edit'" class="flex gap-1">
            <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEditIngredient(ing)" />
            <UButton
              size="sm"
              variant="ghost"
              color="error"
              icon="i-lucide-trash-2"
              @click="deleteIngredient(ing.id)"
            />
          </div>
        </div>
        <div v-else class="flex flex-col gap-2">
          <UInput v-model="editIngredientName" placeholder="Item name" />
          <div class="grid grid-cols-2 gap-2">
            <UInputNumber v-model="editIngredientQuantity" placeholder="Qty" :min="0" />
            <UInputMenu
              v-model="editIngredientUnitId"
              :items="unitOptions ?? []"
              value-key="id"
              label-key="name_singular"
              :filter-fields="UNIT_FILTER_FIELDS"
              placeholder="Unit"
            />
          </div>
          <UInput v-model="editIngredientNote" placeholder="Note (optional)" />
          <UInputMenu
            v-model="editIngredientAlternatives"
            :items="itemOptions"
            multiple
            label-key="name"
            :filter-fields="ITEM_FILTER_FIELDS"
            placeholder="Alternatives (optional)"
          />
          <div class="flex gap-2">
            <UButton size="sm" @click="saveEditIngredient(ing.id)">Save</UButton>
            <UButton size="sm" variant="ghost" @click="cancelEditIngredient">Cancel</UButton>
          </div>
        </div>
      </li>
      <li v-if="ingredients && ingredients.length === 0" class="text-muted text-sm">No ingredients yet.</li>
    </ul>

    <form
      v-if="viewMode === 'edit'"
      class="mb-6 flex flex-col gap-2 rounded border border-default p-3"
      @submit.prevent="addIngredient"
    >
      <RecipeItemField v-model:item="ingredientItem" :item-options="itemOptions" />
      <div class="grid grid-cols-2 gap-2">
        <UInputNumber v-model="ingredientQuantity" placeholder="Qty" :min="0" />
        <UInputMenu
          v-model="ingredientUnitId"
          :items="unitOptions ?? []"
          value-key="id"
          label-key="name_singular"
          :filter-fields="UNIT_FILTER_FIELDS"
          placeholder="Unit"
        />
      </div>
      <UInput v-model="ingredientNote" placeholder="Note (optional)" />
      <UInputMenu
        v-model="ingredientAlternatives"
        :items="itemOptions"
        multiple
        label-key="name"
        :filter-fields="ITEM_FILTER_FIELDS"
        placeholder="Alternatives (optional)"
      />
      <p v-if="ingredientError" class="text-sm text-red-500">{{ ingredientError }}</p>
      <UButton type="submit">Add ingredient</UButton>
    </form>

    <h2 class="mb-2 text-lg font-semibold">Steps</h2>
    <ul class="mb-4 flex flex-col gap-2">
      <li
        v-for="(step, index) in steps"
        :key="step.id"
        class="rounded border border-default px-3 py-2"
      >
        <div v-if="editingStepId !== step.id" class="flex items-center justify-between gap-2">
          <span><span class="text-muted">{{ index + 1 }}.</span> {{ step.instruction }}</span>
          <div v-if="viewMode === 'edit'" class="flex shrink-0 gap-1">
            <UButton size="sm" variant="ghost" icon="i-lucide-chevron-up" @click="moveStep(index, -1)" />
            <UButton size="sm" variant="ghost" icon="i-lucide-chevron-down" @click="moveStep(index, 1)" />
            <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEditStep(step)" />
            <UButton
              size="sm"
              variant="ghost"
              color="error"
              icon="i-lucide-trash-2"
              @click="deleteStep(step.id)"
            />
          </div>
        </div>
        <div v-else class="flex flex-col gap-2">
          <UTextarea v-model="editStepText" />
          <div class="flex gap-2">
            <UButton size="sm" @click="saveEditStep(step.id)">Save</UButton>
            <UButton size="sm" variant="ghost" @click="cancelEditStep">Cancel</UButton>
          </div>
        </div>
      </li>
      <li v-if="steps && steps.length === 0" class="text-muted text-sm">No steps yet.</li>
    </ul>

    <form v-if="viewMode === 'edit'" class="flex gap-2" @submit.prevent="addStep">
      <UTextarea v-model="newStepText" placeholder="Add a step..." class="flex-1" />
      <UButton type="submit">Add</UButton>
    </form>
  </div>
</template>
