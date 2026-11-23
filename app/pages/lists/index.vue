<script setup lang="ts">
import draggable from 'vuedraggable'

type Option = { id: string; name: string }
type CategoryOption = { id: string; name: string; parent_id: string | null }

const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: lists, refresh } = await useAsyncData('lists', async () => {
  const { data, error } = await supabase
    .from('lists')
    .select(`
      id, name, status, created_at, sort_order, list_type,
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

// "List" groups bullet/unordered + numbered lists together
type TypeTab = 'all' | 'list' | 'checklist' | 'note'
const typeTabs: { value: TypeTab; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'checklist', label: 'Checklist' },
  { value: 'list', label: 'List' },
  { value: 'note', label: 'Note' },
]
const typeTab = ref<TypeTab>('all')
function matchesTypeTab(listType: string) {
  if (typeTab.value === 'all') return true
  if (typeTab.value === 'list') return listType === 'bullet' || listType === 'numbered'
  return listType === typeTab.value
}

const LIST_TYPE_LABELS: Record<string, string> = {
  checklist: 'Checklist',
  bullet: 'Bullet list',
  numbered: 'Numbered list',
  note: 'Note',
}

// success/info are the same green/blue as primary/secondary by default in
// this app's theme, so pick 4 visually distinct tokens instead
const LIST_TYPE_COLORS: Record<string, 'primary' | 'secondary' | 'warning' | 'neutral'> = {
  checklist: 'primary',
  bullet: 'secondary',
  numbered: 'warning',
  note: 'neutral',
}

const filteredLists = computed(() => {
  let list = (lists.value ?? []).filter((l) => l.status === statusFilter.value && matchesTypeTab(l.list_type))
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
      custom: { label: 'Custom order', compare: (a, b) => a.sort_order - b.sort_order },
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

// custom order needs its own mutable local array - visibleLists is a
// computed from useListControls and can't be a drag v-model target
const customOrderList = ref<ListRow[]>([])
watchEffect(() => {
  if (sortBy.value === 'custom') {
    customOrderList.value = [...visibleLists.value]
  }
})

let listPersistQueue: Promise<unknown> = Promise.resolve()
function persistListOrder() {
  listPersistQueue = listPersistQueue.then(async () => {
    await Promise.all(
      customOrderList.value.map((l) => supabase.from('lists').update({ sort_order: l.sort_order }).eq('id', l.id)),
    )
  })
}

function onListReorder() {
  customOrderList.value.forEach((l, i) => {
    l.sort_order = i
  })
  persistListOrder()
}

const newName = ref('')
const newListType = ref<'checklist' | 'bullet' | 'numbered' | 'note'>('checklist')
const listTypeOptions = [
  { label: 'Checklist', value: 'checklist' },
  { label: 'Bullet list', value: 'bullet' },
  { label: 'Numbered list', value: 'numbered' },
  { label: 'Note', value: 'note' },
]
const error = ref('')
const creating = ref(false)

async function createList() {
  if (creating.value) return // already in flight - ignore a second click/Enter
  if (!space.value) return
  error.value = ''
  creating.value = true
  const { data, error: insertError } = await supabase
    .from('lists')
    .insert({ space_id: space.value.id, name: newName.value.trim(), list_type: newListType.value })
    .select('id')
    .single()
  if (insertError || !data) {
    creating.value = false
    error.value = insertError?.message ?? 'Failed to create list'
    return
  }
  // leave `creating` true until navigation completes, so the button stays
  // disabled for the whole transition instead of re-enabling momentarily
  await navigateTo(`/lists/${data.id}?new=1`)
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
    <form class="mb-1 flex gap-2" @submit.prevent="createList">
      <UInput v-model="newName" placeholder="New list name" required class="flex-1" />
      <USelect v-model="newListType" :items="listTypeOptions" value-key="value" class="w-40" />
      <UButton type="submit" :loading="creating">Add</UButton>
    </form>
    <p class="text-muted mb-6 text-xs">List type can't be changed after creation.</p>

    <p v-if="error" class="mb-4 text-sm text-red-500">{{ error }}</p>

    <div class="mb-4 flex items-center justify-between gap-2 border-b border-default">
      <div class="flex gap-2">
        <button
          v-for="tab in typeTabs"
          :key="tab.value"
          type="button"
          class="border-b-2 px-3 py-2 text-sm font-medium"
          :class="
            typeTab === tab.value
              ? 'border-primary text-primary'
              : 'border-transparent text-muted hover:text-default'
          "
          @click="typeTab = tab.value"
        >
          {{ tab.label }}
        </button>
      </div>

      <div class="flex gap-2">
        <UButton size="sm" :variant="statusFilter === 'active' ? 'solid' : 'ghost'" @click="statusFilter = 'active'">
          <UIcon name="i-lucide-list" class="sm:hidden" />
          <span class="hidden sm:inline">Active</span>
        </UButton>
        <UButton
          size="sm"
          :variant="statusFilter === 'archived' ? 'solid' : 'ghost'"
          @click="statusFilter = 'archived'"
        >
          <UIcon name="i-lucide-archive" class="sm:hidden" />
          <span class="hidden sm:inline">Archived</span>
        </UButton>
      </div>
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

    <draggable
      v-if="sortBy === 'custom'"
      v-model="customOrderList"
      item-key="id"
      tag="ul"
      class="flex flex-col gap-2"
      handle=".drag-handle"
      @change="onListReorder"
    >
      <template #item="{ element: list }">
        <li class="flex items-center justify-between rounded border border-default px-3 py-2">
          <UIcon name="i-lucide-grip-vertical" class="drag-handle mr-2 shrink-0 cursor-grab text-muted" />
          <NuxtLink :to="`/lists/${list.id}`" class="flex-1">
            <span class="font-medium">{{ list.name }}</span>
            <UBadge v-if="typeTab === 'all'" size="sm" variant="subtle" :color="LIST_TYPE_COLORS[list.list_type]" class="ml-2">
              {{ LIST_TYPE_LABELS[list.list_type] }}
            </UBadge>
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
      </template>
      <template #footer>
        <p v-if="customOrderList.length === 0" class="text-muted text-sm">No {{ statusFilter }} lists match.</p>
      </template>
    </draggable>

    <template v-else-if="groupedLists">
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
              <UBadge v-if="typeTab === 'all'" size="sm" variant="subtle" :color="LIST_TYPE_COLORS[list.list_type]" class="ml-2">
                {{ LIST_TYPE_LABELS[list.list_type] }}
              </UBadge>
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
          <UBadge v-if="typeTab === 'all'" size="sm" variant="subtle" :color="LIST_TYPE_COLORS[list.list_type]" class="ml-2">
            {{ LIST_TYPE_LABELS[list.list_type] }}
          </UBadge>
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
