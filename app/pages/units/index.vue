<script setup lang="ts">
const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: units, refresh } = await useAsyncData('units', async () => {
  const { data, error } = await supabase
    .from('units')
    .select('id, name_singular, name_plural, abbrev_singular, abbrev_plural, unit_type')
    .is('deleted_at', null)
    .order('name_singular')
  if (error) throw error
  return data
})

const UNIT_TYPES = ['count', 'volume', 'weight', 'other'] as const

const nameSingular = ref('')
const namePlural = ref('')
const abbrevSingular = ref('')
const abbrevPlural = ref('')
const unitType = ref<typeof UNIT_TYPES[number]>('other')
const error = ref('')
const saving = ref(false)

async function addUnit() {
  if (!space.value) return
  error.value = ''
  saving.value = true
  const { error: insertError } = await supabase.from('units').insert({
    space_id: space.value.id,
    name_singular: nameSingular.value.trim(),
    name_plural: namePlural.value.trim(),
    abbrev_singular: abbrevSingular.value.trim() || null,
    abbrev_plural: abbrevPlural.value.trim() || null,
    unit_type: unitType.value,
  })
  saving.value = false
  if (insertError) {
    error.value = insertError.message
    return
  }
  nameSingular.value = ''
  namePlural.value = ''
  abbrevSingular.value = ''
  abbrevPlural.value = ''
  unitType.value = 'other'
  await refresh()
}

async function deleteUnit(id: string) {
  // soft delete only: anything referencing this unit keeps the link intact,
  // so restoring it from Trash brings the link right back. Permanently
  // deleting it (a real DELETE, from the Trash page) is what triggers the
  // FK's on-delete-set-null/cascade, not this.
  await supabase.from('units').update({ deleted_at: new Date().toISOString() }).eq('id', id)
  await refresh()
}

type Unit = NonNullable<typeof units.value>[number]
const editingId = ref<string | null>(null)
const editNameSingular = ref('')
const editNamePlural = ref('')
const editAbbrevSingular = ref('')
const editAbbrevPlural = ref('')
const editUnitType = ref<typeof UNIT_TYPES[number]>('other')

function startEdit(unit: Unit) {
  editingId.value = unit.id
  editNameSingular.value = unit.name_singular
  editNamePlural.value = unit.name_plural
  editAbbrevSingular.value = unit.abbrev_singular ?? ''
  editAbbrevPlural.value = unit.abbrev_plural ?? ''
  editUnitType.value = unit.unit_type as typeof UNIT_TYPES[number]
}

function cancelEdit() {
  editingId.value = null
}

async function saveEdit(id: string) {
  await supabase
    .from('units')
    .update({
      name_singular: editNameSingular.value.trim(),
      name_plural: editNamePlural.value.trim(),
      abbrev_singular: editAbbrevSingular.value.trim() || null,
      abbrev_plural: editAbbrevPlural.value.trim() || null,
      unit_type: editUnitType.value,
    })
    .eq('id', id)
  editingId.value = null
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <h1 class="mb-4 text-xl font-semibold">Units</h1>

    <form class="mb-6 grid grid-cols-2 gap-2 sm:grid-cols-5" @submit.prevent="addUnit">
      <UInput v-model="nameSingular" placeholder="Singular (cup)" required />
      <UInput v-model="namePlural" placeholder="Plural (cups)" required />
      <UInput v-model="abbrevSingular" placeholder="Abbrev. (c)" />
      <UInput v-model="abbrevPlural" placeholder="Abbrev. plural" />
      <USelect v-model="unitType" :items="UNIT_TYPES" />
      <UButton type="submit" :loading="saving" class="col-span-2 sm:col-span-5">Add unit</UButton>
    </form>

    <p v-if="error" class="mb-4 text-sm text-red-500">{{ error }}</p>

    <ul class="flex flex-col gap-2">
      <li
        v-for="unit in units"
        :key="unit.id"
        class="rounded border border-default px-3 py-2"
      >
        <div v-if="editingId !== unit.id" class="flex items-center justify-between">
          <span>
            {{ unit.name_singular }} / {{ unit.name_plural }}
            <span v-if="unit.abbrev_singular" class="text-muted">({{ unit.abbrev_singular }})</span>
            <UBadge size="sm" variant="subtle" class="ml-2">{{ unit.unit_type }}</UBadge>
          </span>
          <div class="flex gap-1">
            <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(unit)" />
            <UButton size="sm" variant="ghost" color="error" icon="i-lucide-trash-2" @click="deleteUnit(unit.id)" />
          </div>
        </div>
        <div v-else class="grid grid-cols-2 gap-2 sm:grid-cols-5">
          <UInput v-model="editNameSingular" placeholder="Singular (cup)" />
          <UInput v-model="editNamePlural" placeholder="Plural (cups)" />
          <UInput v-model="editAbbrevSingular" placeholder="Abbrev. (c)" />
          <UInput v-model="editAbbrevPlural" placeholder="Abbrev. plural" />
          <USelect v-model="editUnitType" :items="UNIT_TYPES" />
          <div class="col-span-2 flex gap-2 sm:col-span-5">
            <UButton size="sm" @click="saveEdit(unit.id)">Save</UButton>
            <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
          </div>
        </div>
      </li>
      <li v-if="units && units.length === 0" class="text-muted text-sm">No units yet.</li>
    </ul>
  </div>
</template>
