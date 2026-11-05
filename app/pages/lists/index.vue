<script setup lang="ts">
const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const { data: lists, refresh } = await useAsyncData('lists', async () => {
  const { data, error } = await supabase
    .from('lists')
    .select(`
      id, name, status,
      list_categories(categories(id, name, parent_id)),
      list_tags(tags(id, name))
    `)
    .is('deleted_at', null)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data
})

const statusFilter = ref<'active' | 'archived'>('active')
const visibleLists = computed(() => lists.value?.filter((l) => l.status === statusFilter.value) ?? [])

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
    <h1 class="mb-4 text-xl font-semibold">Lists</h1>

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

    <ul class="flex flex-col gap-2">
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
      <li v-if="visibleLists.length === 0" class="text-muted text-sm">No {{ statusFilter }} lists.</li>
    </ul>
  </div>
</template>
