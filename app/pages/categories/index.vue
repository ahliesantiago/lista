<script setup lang="ts">
type Category = { id: string; name: string; parent_id: string | null }

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: categories, refresh } = await useAsyncData('categories', async () => {
  const { data, error } = await supabase
    .from('categories')
    .select('id, name, parent_id')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data as Category[]
})

const topLevelCategories = computed(() => categories.value?.filter((c) => !c.parent_id) ?? [])
const subcategoriesByParent = computed(() => {
  const map = new Map<string, Category[]>()
  for (const c of categories.value ?? []) {
    if (!c.parent_id) continue
    const list = map.get(c.parent_id) ?? []
    list.push(c)
    map.set(c.parent_id, list)
  }
  return map
})

/**
 * Collating subcategories whose parent category has been soft-deleted
 * (i.e. the subcategory itself is still live but the parent_id
 * no longer matches any row in topLevelCategories (which excludes trashed rows).
 */
const liveCategoryIds = computed(() => new Set((categories.value ?? []).map((c) => c.id)))
const orphanedSubcategories = computed(() =>
  (categories.value ?? []).filter((c) => c.parent_id && !liveCategoryIds.value.has(c.parent_id)),
)

const newName = ref('')
const newParentId = ref<string | null>(null)
const error = ref('')
const saving = ref(false)

async function addCategory() {
  if (!space.value) return
  error.value = ''
  saving.value = true
  const { error: insertError } = await supabase
    .from('categories')
    .insert({ space_id: space.value.id, name: newName.value.trim(), parent_id: newParentId.value })
  saving.value = false
  if (insertError) {
    error.value = insertError.message
    return
  }
  newName.value = ''
  newParentId.value = null
  await refresh()
}

async function deleteCategory(id: string) {
  // soft delete only: anything referencing this category keeps the link
  // intact, so restoring it from Trash brings the link right back.
  // Permanently deleting it (a real DELETE, from the Trash page) is what
  // triggers the FK cascade/set-null, not this.
  await supabase.from('categories').update({ deleted_at: new Date().toISOString() }).eq('id', id)
  await refresh()
}

const editingId = ref<string | null>(null)
const editName = ref('')
const editParentId = ref<string | null>(null)

function startEdit(category: Category) {
  editingId.value = category.id
  editName.value = category.name
  editParentId.value = category.parent_id
}

function cancelEdit() {
  editingId.value = null
}

async function saveEdit(id: string) {
  await supabase
    .from('categories')
    .update({ name: editName.value.trim(), parent_id: editParentId.value })
    .eq('id', id)
  editingId.value = null
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-lg">
    <h1 class="mb-4 text-xl font-semibold">Categories</h1>

    <form class="mb-6 flex flex-col gap-2" @submit.prevent="addCategory">
      <div class="flex gap-2">
        <UInput v-model="newName" placeholder="New category" required class="flex-1" />
        <UButton type="submit" :loading="saving">Add</UButton>
      </div>
      <UInputMenu
        v-model="newParentId"
        :items="topLevelCategories"
        value-key="id"
        label-key="name"
        placeholder="Parent category (optional, makes this a subcategory)"
        class="w-full"
      />
    </form>

    <p v-if="error" class="mb-4 text-sm text-red-500">{{ error }}</p>

    <ul class="flex flex-col gap-2">
      <template v-for="category in topLevelCategories" :key="category.id">
        <li class="rounded border border-default px-3 py-2">
          <div v-if="editingId !== category.id" class="flex items-center justify-between">
            <span class="font-medium">{{ category.name }}</span>
            <div class="flex gap-1">
              <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(category)" />
              <UButton
                size="sm"
                variant="ghost"
                color="error"
                icon="i-lucide-trash-2"
                @click="deleteCategory(category.id)"
              />
            </div>
          </div>
          <div v-else class="flex flex-col gap-2">
            <UInput v-model="editName" />
            <UInputMenu
              v-model="editParentId"
              :items="topLevelCategories.filter((c) => c.id !== category.id)"
              value-key="id"
              label-key="name"
              placeholder="Parent category (optional)"
            />
            <div class="flex gap-1">
              <UButton size="sm" @click="saveEdit(category.id)">Save</UButton>
              <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
            </div>
          </div>
        </li>
        <li
          v-for="sub in subcategoriesByParent.get(category.id) ?? []"
          :key="sub.id"
          class="ml-6 rounded border border-default px-3 py-2"
        >
          <div v-if="editingId !== sub.id" class="flex items-center justify-between">
            <span class="text-muted text-sm">{{ sub.name }}</span>
            <div class="flex gap-1">
              <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(sub)" />
              <UButton
                size="sm"
                variant="ghost"
                color="error"
                icon="i-lucide-trash-2"
                @click="deleteCategory(sub.id)"
              />
            </div>
          </div>
          <div v-else class="flex flex-col gap-2">
            <UInput v-model="editName" />
            <UInputMenu v-model="editParentId" :items="topLevelCategories" value-key="id" label-key="name" />
            <div class="flex gap-1">
              <UButton size="sm" @click="saveEdit(sub.id)">Save</UButton>
              <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
            </div>
          </div>
        </li>
      </template>
      <li v-if="categories && categories.length === 0" class="text-muted text-sm">No categories yet.</li>
    </ul>

    <div v-if="orphanedSubcategories.length > 0" class="mt-4">
      <h3 class="mb-2 text-sm font-semibold text-muted">Orphaned subcategories (parent trashed)</h3>
      <ul class="flex flex-col gap-2">
        <li
          v-for="sub in orphanedSubcategories"
          :key="sub.id"
          class="rounded border border-dashed border-default px-3 py-2"
        >
          <div v-if="editingId !== sub.id" class="flex items-center justify-between">
            <span class="text-muted text-sm">{{ sub.name }}</span>
            <div class="flex gap-1">
              <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="startEdit(sub)" />
              <UButton
                size="sm"
                variant="ghost"
                color="error"
                icon="i-lucide-trash-2"
                @click="deleteCategory(sub.id)"
              />
            </div>
          </div>
          <div v-else class="flex flex-col gap-2">
            <UInput v-model="editName" />
            <UInputMenu
              v-model="editParentId"
              :items="topLevelCategories"
              value-key="id"
              label-key="name"
              placeholder="Parent category (optional)"
            />
            <div class="flex gap-1">
              <UButton size="sm" @click="saveEdit(sub.id)">Save</UButton>
              <UButton size="sm" variant="ghost" @click="cancelEdit">Cancel</UButton>
            </div>
          </div>
        </li>
      </ul>
    </div>
  </div>
</template>
