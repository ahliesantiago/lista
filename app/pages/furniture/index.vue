<script setup lang="ts">
const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: furniture, refresh } = await useAsyncData('furniture', async () => {
  const { data, error } = await supabase
    .from('furniture')
    .select('id, name, brand, room, quantity, needs_maintenance, needs_replacement, notes')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data
})

const newName = ref('')
const newBrand = ref('')
const newRoom = ref('')
const newQuantity = ref(1)
const newNeedsMaintenance = ref(false)
const newNeedsReplacement = ref(false)
const newNotes = ref('')
const error = ref('')
const saving = ref(false)

async function addFurniture() {
  if (!space.value) return
  error.value = ''
  saving.value = true
  const { error: insertError } = await supabase.from('furniture').insert({
    space_id: space.value.id,
    name: newName.value.trim(),
    brand: newBrand.value.trim() || null,
    room: newRoom.value.trim() || null,
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
  newRoom.value = ''
  newQuantity.value = 1
  newNeedsMaintenance.value = false
  newNeedsReplacement.value = false
  newNotes.value = ''
  await refresh()
}

async function deleteFurniture(id: string) {
  await supabase.from('furniture').update({ deleted_at: new Date().toISOString() }).eq('id', id)
  await refresh()
}

type Furniture = NonNullable<typeof furniture.value>[number]
const editingId = ref<string | null>(null)
const editName = ref('')
const editBrand = ref('')
const editRoom = ref('')
const editQuantity = ref(1)
const editNeedsMaintenance = ref(false)
const editNeedsReplacement = ref(false)
const editNotes = ref('')

function startEdit(item: Furniture) {
  editingId.value = item.id
  editName.value = item.name
  editBrand.value = item.brand ?? ''
  editRoom.value = item.room ?? ''
  editQuantity.value = item.quantity
  editNeedsMaintenance.value = item.needs_maintenance
  editNeedsReplacement.value = item.needs_replacement
  editNotes.value = item.notes ?? ''
}

function cancelEdit() {
  editingId.value = null
}

async function saveEdit(id: string) {
  await supabase
    .from('furniture')
    .update({
      name: editName.value.trim(),
      brand: editBrand.value.trim() || null,
      room: editRoom.value.trim() || null,
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
    <form class="mb-6 grid grid-cols-2 gap-2 sm:grid-cols-4" @submit.prevent="addFurniture">
      <UInput v-model="newName" placeholder="Name (e.g. Sofa)" required class="col-span-2" />
      <UInput v-model="newBrand" placeholder="Brand (optional)" />
      <UInput v-model="newRoom" placeholder="Room (optional)" />
      <UInputNumber v-model="newQuantity" :min="1" />
      <UCheckbox v-model="newNeedsMaintenance" label="Needs maintenance" />
      <UCheckbox v-model="newNeedsReplacement" label="Needs replacement" />
      <UInput v-model="newNotes" placeholder="Notes (optional)" class="col-span-2" />
      <UButton type="submit" :loading="saving" class="col-span-2 sm:col-span-4">Add furniture</UButton>
    </form>

    <p v-if="error" class="mb-4 text-sm text-red-500">{{ error }}</p>

    <ul class="flex flex-col gap-2">
      <li v-for="item in furniture" :key="item.id" class="rounded border border-default px-3 py-2">
        <div v-if="editingId !== item.id" class="flex items-center justify-between">
          <div>
            <span class="font-medium">{{ item.name }}</span>
            <span v-if="item.brand" class="text-muted ml-2 text-sm">{{ item.brand }}</span>
            <span v-if="item.room" class="text-muted ml-2 text-sm">({{ item.room }})</span>
            <UBadge v-if="item.quantity > 1" size="sm" variant="subtle" class="ml-2">
              x{{ item.quantity }}
            </UBadge>
            <UBadge v-if="item.needs_maintenance" size="sm" color="warning" class="ml-2">
              Needs maintenance
            </UBadge>
            <UBadge v-if="item.needs_replacement" size="sm" color="error" class="ml-2">
              Needs replacement
            </UBadge>
            <p v-if="item.notes" class="text-muted mt-1 text-sm">{{ item.notes }}</p>
          </div>
          <div class="flex gap-1">
            <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(item)" />
            <UButton
              size="sm"
              variant="ghost"
              color="error"
              icon="i-lucide-trash-2"
              @click="deleteFurniture(item.id)"
            />
          </div>
        </div>
        <div v-else class="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <UInput v-model="editName" placeholder="Name" class="col-span-2" />
          <UInput v-model="editBrand" placeholder="Brand (optional)" />
          <UInput v-model="editRoom" placeholder="Room (optional)" />
          <UInputNumber v-model="editQuantity" :min="1" />
          <UCheckbox v-model="editNeedsMaintenance" label="Needs maintenance" />
          <UCheckbox v-model="editNeedsReplacement" label="Needs replacement" />
          <UInput v-model="editNotes" placeholder="Notes (optional)" class="col-span-2" />
          <div class="col-span-2 flex gap-2 sm:col-span-4">
            <UButton size="sm" @click="saveEdit(item.id)">Save</UButton>
            <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
          </div>
        </div>
      </li>
      <li v-if="furniture && furniture.length === 0" class="text-muted text-sm">No furniture yet.</li>
    </ul>
  </div>
</template>
