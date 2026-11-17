<script setup lang="ts">
type Option = { id: string; name: string }
type CategoryOption = { id: string; name: string; parent_id: string | null }

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: lists, refresh } = await useAsyncData('lists', async () => {
  const { data, error } = await supabase
    .from('lists')
    .select(`
      id, name, status, created_at,
      list_categories(categories(id, name, parent_id)),
      list_tags(tags(id, name))
    `)
    .is('deleted_at', null)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data
})
type ListRow = NonNullable<typeof lists.value>[number]

const { data: categoryOptions } = await useAsyncData('category-options', async () => {
  const { data, error } = await supabase
    .from('categories')
    .select('id, name, parent_id')
    .is('deleted_at', null)
    .order('name')
  if (error) throw error
  return data as CategoryOption[]
})

const { data: tagOptions } = await useAsyncData('tag-options', async () => {
  const { data, error } = await supabase.from('tags').select('id, name').is('deleted_at', null).order('name')
  if (error) throw error
  return data as Option[]
})

const statusFilter = ref<'active' | 'archived'>('active')
const filterCategories = ref<CategoryOption[]>([])
const filterTags = ref<Option[]>([])

const filteredLists = computed(() => {
  let list = (lists.value ?? []).filter((l) => l.status === statusFilter.value)
  if (filterCategories.value.length > 0) {
    const ids = new Set(filterCategories.value.map((c) => c.id))
    list = list.filter((l) => l.list_categories.some((lc) => ids.has(lc.categories!.id)))
  }
  if (filterTags.value.length > 0) {
    const ids = new Set(filterTags.value.map((t) => t.id))
    list = list.filter((l) => l.list_tags.some((lt) => ids.has(lt.tags!.id)))
  }
  return list
})

const { sortBy, groupBy, sortOptions, groupOptions, sortedItems: visibleLists, groupedItems: groupedLists } =
  useListControls<ListRow>(
    filteredLists,
    {
      'name-asc': { label: 'Name (A–Z)', compare: (a, b) => a.name.localeCompare(b.name) },
      'name-desc': { label: 'Name (Z–A)', compare: (a, b) => b.name.localeCompare(a.name) },
      'created-desc': { label: 'Newest first', compare: (a, b) => b.created_at.localeCompare(a.created_at) },
      'created-asc': { label: 'Oldest first', compare: (a, b) => a.created_at.localeCompare(b.created_at) },
    },
    {
      category: {
        label: 'Category',
        getKeys: (l) => (l.list_categories.length > 0 ? l.list_categories.map((lc) => lc.categories!.name) : ['Uncategorized']),
      },
      tag: {
        label: 'Tag',
        getKeys: (l) => (l.list_tags.length > 0 ? l.list_tags.map((lt) => lt.tags!.name) : ['Untagged']),
      },
    },
  )

const newName = ref('')
const error = ref('')
const creating = ref(false)

async function createList() {
  if (!space.value) return
  error.value = ''
  creating.value = true
  const { data, error: insertError } = await supabase
    .from('lists')
    .insert({ space_id: space.value.id, name: newName.value.trim() })
    .select('id')
    .single()
  if (insertError || !data) {
    creating.value = false
    error.value = insertError?.message ?? 'Failed to create list'
    return
  }
  // leave `creating` true until navigation completes, so the button stays
  // disabled for the whole transition instead of re-enabling momentarily
  await navigateTo(`/lists/${data.id}`)
}

async function setStatus(id: string, status: 'active' | 'archived') {
  await supabase.from('lists').update({ status }).eq('id', id)
  await refresh()
}

async function deleteList(id: string) {
  const deletedAt = new Date().toISOString()
  await supabase.from('lists').update({ deleted_at: deletedAt }).eq('id', id)
  await supabase.from('list_items').update({ deleted_at: deletedAt }).eq('list_id', id).is('deleted_at', null)
  await refresh()
}
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <form class="mb-6 flex gap-2" @submit.prevent="createList">
      <UInput v-model="newName" placeholder="New list name" required class="flex-1" />
      <UButton type="submit" :loading="creating">Add</UButton>
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
          :items="categoryOptions ?? []"
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
          :items="tagOptions ?? []"
          multiple
          label-key="name"
          placeholder="Any tag"
          class="w-full"
        />
      </div>
    </div>

    <template v-if="groupedLists">
      <div v-for="[groupName, groupLists] in groupedLists" :key="groupName" class="mb-4">
        <h2 class="mb-2 text-sm font-semibold text-muted">{{ groupName }}</h2>
        <ul class="flex flex-col gap-2">
          <li
            v-for="list in groupLists"
            :key="list.id"
            class="flex items-center justify-between rounded border border-default px-3 py-2"
          >
            <NuxtLink :to="`/lists/${list.id}`" class="flex-1">
              <span class="font-medium">{{ list.name }}</span>
              <UBadge
                v-for="lc in list.list_categories"
                :key="lc.categories!.id"
                size="sm"
                :variant="lc.categories!.parent_id ? 'subtle' : 'solid'"
                class="ml-2"
              >
                {{ lc.categories!.name }}
              </UBadge>
              <UBadge v-for="t in list.list_tags" :key="t.tags!.id" size="sm" variant="outline" class="ml-2">
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
              <UButton
                size="sm"
                variant="ghost"
                color="error"
                icon="i-lucide-trash-2"
                @click="deleteList(list.id)"
              />
            </div>
          </li>
        </ul>
      </div>
      <p v-if="groupedLists.length === 0" class="text-muted text-sm">No {{ statusFilter }} lists match.</p>
    </template>

    <ul v-else class="flex flex-col gap-2">
      <li
        v-for="list in visibleLists"
        :key="list.id"
        class="flex items-center justify-between rounded border border-default px-3 py-2"
      >
        <NuxtLink :to="`/lists/${list.id}`" class="flex-1">
          <span class="font-medium">{{ list.name }}</span>
          <UBadge
            v-for="lc in list.list_categories"
            :key="lc.categories!.id"
            size="sm"
            :variant="lc.categories!.parent_id ? 'subtle' : 'solid'"
            class="ml-2"
          >
            {{ lc.categories!.name }}
          </UBadge>
          <UBadge v-for="t in list.list_tags" :key="t.tags!.id" size="sm" variant="outline" class="ml-2">
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
      <li v-if="visibleLists.length === 0" class="text-muted text-sm">No {{ statusFilter }} lists match.</li>
    </ul>
  </div>
</template>
