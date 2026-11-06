<script setup lang="ts">
const route = useRoute()
const recipeId = route.params.id as string
const supabase = useSupabaseClient()

const { data: recipe } = await useAsyncData(`cook-recipe-${recipeId}`, async () => {
  const { data, error } = await supabase
    .from('recipes')
    .select('id, name')
    .eq('id', recipeId)
    .is('deleted_at', null)
    .single()
  if (error) throw error
  return data
})

const { data: steps } = await useAsyncData(`cook-steps-${recipeId}`, async () => {
  const { data, error } = await supabase
    .from('recipe_steps')
    .select('id, step_number, instruction')
    .eq('recipe_id', recipeId)
    .order('step_number')
  if (error) throw error
  return data
})

const { data: ingredients } = await useAsyncData(`cook-ingredients-${recipeId}`, async () => {
  const { data, error } = await supabase
    .from('recipe_ingredients')
    .select('id, name, quantity, note, unit:units(id, name_singular, name_plural)')
    .eq('recipe_id', recipeId)
    .order('sort_order')
  if (error) throw error
  return data
})

function unitLabel(unit: { name_singular: string; name_plural: string } | null, amount: number | null) {
  if (!unit) return ''
  return amount != null && amount !== 1 ? unit.name_plural : unit.name_singular
}

// ephemeral: this view's whole purpose resets every time it's opened, so
// checkmarks live only in local state and are never written to the database
const checked = ref<Record<string, boolean>>({})
const currentStepId = computed(() => steps.value?.find((s) => !checked.value[s.id])?.id ?? null)
</script>

<template>
  <div v-if="recipe" class="mx-auto max-w-2xl">
    <div class="mb-4 flex items-center justify-between">
      <h1 class="text-xl font-semibold">Cooking: {{ recipe.name }}</h1>
      <UButton :to="`/recipes/${recipeId}`" variant="outline" size="sm">Back to recipe</UButton>
    </div>

    <div v-if="ingredients && ingredients.length > 0" class="mb-6 rounded border border-default p-3">
      <h2 class="mb-2 text-sm font-semibold text-muted">Ingredients</h2>
      <ul class="flex flex-col gap-1">
        <li v-for="ing in ingredients" :key="ing.id" class="text-sm">
          <span v-if="ing.quantity != null">
            {{ ing.quantity }}<span v-if="ing.unit">{{ ' ' + unitLabel(ing.unit, ing.quantity) }}</span>
          </span>
          {{ ing.name }}
          <span v-if="ing.note" class="text-muted">, {{ ing.note }}</span>
        </li>
      </ul>
    </div>

    <h2 class="mb-2 text-lg font-semibold">Steps</h2>
    <ul class="flex flex-col gap-2">
      <li
        v-for="step in steps"
        :key="step.id"
        class="flex items-start gap-3 rounded border px-3 py-3 transition"
        :class="
          step.id === currentStepId
            ? 'border-primary bg-primary/5 text-base font-medium'
            : 'border-default text-sm'
        "
      >
        <UCheckbox v-model="checked[step.id]" />
        <span :class="{ 'text-muted line-through': checked[step.id] }">
          {{ step.step_number }}. {{ step.instruction }}
        </span>
      </li>
      <li v-if="steps && steps.length === 0" class="text-muted text-sm">No steps for this recipe.</li>
    </ul>

    <p v-if="steps && steps.length > 0 && !currentStepId" class="mt-4 text-sm font-medium text-green-600">
      All steps done!
    </p>
  </div>
</template>
