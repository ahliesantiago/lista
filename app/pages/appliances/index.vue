<script setup lang="ts">
const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: appliances, refresh } = await useAsyncData('appliances', async () => {
  const { data, error } = await supabase
    .from('appliances')
    .select('id, name, brand, quantity, needs_maintenance, needs_replacement, notes')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data
})

const newName = ref('')
const newBrand = ref('')
const newQuantity = ref(1)
const newNeedsMaintenance = ref(false)
const newNeedsReplacement = ref(false)
const newNotes = ref('')
const error = ref('')
const saving = ref(false)

async function addAppliance() {
  if (!space.value) return
  error.value = ''
  saving.value = true
  const { error: insertError } = await supabase.from('appliances').insert({
    space_id: space.value.id,
    name: newName.value.trim(),
    brand: newBrand.value.trim() || null,
    quantity: newQuantity.value,
    needs_maintenance: newNeedsMaintenance.value,
    needs_replacement: newNeedsReplacement.value,
    notes: newNotes.value.trim() || null,
  })
  saving.value = false
  if (insertError) {
    error.value = insertError.message
    return
  }
  newName.value = ''
  newBrand.value = ''
  newQuantity.value = 1
  newNeedsMaintenance.value = false
  newNeedsReplacement.value = false
  newNotes.value = ''
  await refresh()
}

async function deleteAppliance(id: string) {
  await supabase.from('appliances').update({ deleted_at: new Date().toISOString() }).eq('id', id)
  await refresh()
}

type Appliance = NonNullable<typeof appliances.value>[number]
const editingId = ref<string | null>(null)
const editName = ref('')
const editBrand = ref('')
const editQuantity = ref(1)
const editNeedsMaintenance = ref(false)
const editNeedsReplacement = ref(false)
const editNotes = ref('')

function startEdit(appliance: Appliance) {
  editingId.value = appliance.id
  editName.value = appliance.name
  editBrand.value = appliance.brand ?? ''
  editQuantity.value = appliance.quantity
  editNeedsMaintenance.value = appliance.needs_maintenance
  editNeedsReplacement.value = appliance.needs_replacement
  editNotes.value = appliance.notes ?? ''
}

function cancelEdit() {
  editingId.value = null
}

async function saveEdit(id: string) {
  await supabase
    .from('appliances')
    .update({
      name: editName.value.trim(),
      brand: editBrand.value.trim() || null,
      quantity: editQuantity.value,
      needs_maintenance: editNeedsMaintenance.value,
      needs_replacement: editNeedsReplacement.value,
      notes: editNotes.value.trim() || null,
    })
    .eq('id', id)
  editingId.value = null
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <form class="mb-6 grid grid-cols-2 gap-2 sm:grid-cols-4" @submit.prevent="addAppliance">
      <UInput v-model="newName" placeholder="Name (e.g. Dishwasher)" required class="col-span-2" />
      <UInput v-model="newBrand" placeholder="Brand (optional)" />
      <UInputNumber v-model="newQuantity" :min="1" />
      <UCheckbox v-model="newNeedsMaintenance" label="Needs maintenance" />
      <UCheckbox v-model="newNeedsReplacement" label="Needs replacement" />
      <UInput v-model="newNotes" placeholder="Notes (optional)" class="col-span-2" />
      <UButton type="submit" :loading="saving" class="col-span-2 sm:col-span-4">Add appliance</UButton>
    </form>

    <p v-if="error" class="mb-4 text-sm text-red-500">{{ error }}</p>

    <ul class="flex flex-col gap-2">
      <li v-for="appliance in appliances" :key="appliance.id" class="rounded border border-default px-3 py-2">
        <div v-if="editingId !== appliance.id" class="flex items-center justify-between">
          <div>
            <span class="font-medium">{{ appliance.name }}</span>
            <span v-if="appliance.brand" class="text-muted ml-2 text-sm">{{ appliance.brand }}</span>
            <UBadge v-if="appliance.quantity > 1" size="sm" variant="subtle" class="ml-2">
              x{{ appliance.quantity }}
            </UBadge>
            <UBadge v-if="appliance.needs_maintenance" size="sm" color="warning" class="ml-2">
              Needs maintenance
            </UBadge>
            <UBadge v-if="appliance.needs_replacement" size="sm" color="error" class="ml-2">
              Needs replacement
            </UBadge>
            <p v-if="appliance.notes" class="text-muted mt-1 text-sm">{{ appliance.notes }}</p>
          </div>
          <div class="flex gap-1">
            <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(appliance)" />
            <UButton
              size="sm"
              variant="ghost"
              color="error"
              icon="i-lucide-trash-2"
              @click="deleteAppliance(appliance.id)"
            />
          </div>
        </div>
        <div v-else class="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <UInput v-model="editName" placeholder="Name" class="col-span-2" />
          <UInput v-model="editBrand" placeholder="Brand (optional)" />
          <UInputNumber v-model="editQuantity" :min="1" />
          <UCheckbox v-model="editNeedsMaintenance" label="Needs maintenance" />
          <UCheckbox v-model="editNeedsReplacement" label="Needs replacement" />
          <UInput v-model="editNotes" placeholder="Notes (optional)" class="col-span-2" />
          <div class="col-span-2 flex gap-2 sm:col-span-4">
            <UButton size="sm" @click="saveEdit(appliance.id)">Save</UButton>
            <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
          </div>
        </div>
      </li>
      <li v-if="appliances && appliances.length === 0" class="text-muted text-sm">No appliances yet.</li>
    </ul>
  </div>
</template>
