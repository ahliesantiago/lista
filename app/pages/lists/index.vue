<script setup lang="ts">
type Option = { id: string; name: string }

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: lists, refresh } = await useAsyncData('lists', async () => {
  const { data, error } = await supabase
    .from('lists')
    .select(`
      id, name, status,
      category:categories(id, name),
      list_tags(tags(id, name))
    `)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data
})

const { data: categoryOptions } = await useAsyncData('category-options', async () => {
  const { data, error } = await supabase.from('categories').select('id, name').order('name')
  if (error) throw error
  return data
})

const tagOptions = ref<Option[]>([])
const { data: tagOptionsInitial } = await useAsyncData('tag-options', async () => {
  const { data, error } = await supabase.from('tags').select('id, name').order('name')
  if (error) throw error
  return data
})
tagOptions.value = tagOptionsInitial.value ?? []

const statusFilter = ref<'active' | 'archived'>('active')
const visibleLists = computed(() => lists.value?.filter((l) => l.status === statusFilter.value) ?? [])

const newName = ref('')
const newCategoryId = ref<string | null>(null)
const newTags = ref<Option[]>([])
const error = ref('')
const saving = ref(false)

async function onCreateTag(searchTerm: string) {
  if (!space.value) return
  const { data, error: insertError } = await supabase
    .from('tags')
    .insert({ space_id: space.value.id, name: searchTerm })
    .select('id, name')
    .single()
  if (insertError || !data) return
  tagOptions.value.push(data)
  newTags.value.push(data)
}

async function createList() {
  if (!space.value) return
  error.value = ''
  saving.value = true
  const { data, error: insertError } = await supabase
    .from('lists')
    .insert({ space_id: space.value.id, name: newName.value.trim(), category_id: newCategoryId.value })
    .select('id')
    .single()
  if (insertError || !data) {
    saving.value = false
    error.value = insertError?.message ?? 'Failed to create list'
    return
  }
  if (newTags.value.length > 0) {
    await supabase.from('list_tags').insert(newTags.value.map((t) => ({ list_id: data.id, tag_id: t.id })))
  }
  saving.value = false
  newName.value = ''
  newCategoryId.value = null
  newTags.value = []
  await refresh()
}

async function setStatus(id: string, status: 'active' | 'archived') {
  await supabase.from('lists').update({ status }).eq('id', id)
  await refresh()
}

async function deleteList(id: string) {
  await supabase.from('lists').delete().eq('id', id)
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <h1 class="mb-4 text-xl font-semibold">Lists</h1>

    <form class="mb-6 flex flex-col gap-2" @submit.prevent="createList">
      <div class="flex gap-2">
        <UInput v-model="newName" placeholder="New list name" required class="flex-1" />
        <UButton type="submit" :loading="saving">Add</UButton>
      </div>
      <div class="flex gap-2">
        <USelectMenu
          v-model="newCategoryId"
          :items="categoryOptions ?? []"
          value-key="id"
          label-key="name"
          placeholder="Category"
          class="flex-1"
        />
        <USelectMenu
          v-model="newTags"
          :items="tagOptions"
          multiple
          create-item
          label-key="name"
          placeholder="Tags"
          class="flex-1"
          @create="onCreateTag"
        />
      </div>
    </form>

    <p v-if="error" class="mb-4 text-sm text-red-500">{{ error }}</p>

    <div class="mb-4 flex gap-2">
      <UButton
        size="sm"
        :variant="statusFilter === 'active' ? 'solid' : 'ghost'"
        @click="statusFilter = 'active'"
      >
        Active
      </UButton>
      <UButton
        size="sm"
        :variant="statusFilter === 'archived' ? 'solid' : 'ghost'"
        @click="statusFilter = 'archived'"
      >
        Archived
      </UButton>
    </div>

    <ul class="flex flex-col gap-2">
      <li
        v-for="list in visibleLists"
        :key="list.id"
        class="flex items-center justify-between rounded border border-default px-3 py-2"
      >
        <NuxtLink :to="`/lists/${list.id}`" class="flex-1">
          <span class="font-medium">{{ list.name }}</span>
          <span v-if="list.category" class="text-muted ml-2 text-sm">{{ list.category.name }}</span>
          <UBadge v-for="t in list.list_tags" :key="t.tags!.id" size="sm" variant="subtle" class="ml-2">
            {{ t.tags!.name }}
          </UBadge>
        </NuxtLink>
        <div class="flex items-center gap-2">
          <UButton
            v-if="list.status === 'active'"
            size="sm"
            variant="ghost"
            icon="i-lucide-archive"
            @click="setStatus(list.id, 'archived')"
          />
          <UButton
            v-else
            size="sm"
            variant="ghost"
            icon="i-lucide-archive-restore"
            @click="setStatus(list.id, 'active')"
          />
          <UButton size="sm" variant="ghost" color="error" icon="i-lucide-trash-2" @click="deleteList(list.id)" />
        </div>
      </li>
      <li v-if="visibleLists.length === 0" class="text-muted text-sm">No {{ statusFilter }} lists.</li>
    </ul>
  </div>
</template>
