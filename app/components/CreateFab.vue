<script setup lang="ts">
const supabase = useSupabaseClient()
const { data: space } = await useCurrentSpace()

const createFormOpen = useCreateFormOpen()

const promptOpen = ref(false)
const promptKind = ref<'list' | 'recipe'>('list')
const promptName = ref('')
const promptListType = ref<'checklist' | 'bullet' | 'numbered' | 'note'>('checklist')
const promptError = ref('')
const promptSaving = ref(false)

const listTypeOptions = [
  { label: 'Checklist', value: 'checklist' },
  { label: 'Bullet list', value: 'bullet' },
  { label: 'Numbered list', value: 'numbered' },
  { label: 'Note', value: 'note' },
]

const promptTitle = computed(() => (promptKind.value === 'list' ? 'New List' : 'New Recipe'))
const promptPlaceholder = computed(() => (promptKind.value === 'list' ? 'List name' : 'Recipe name'))

function openNamePrompt(kind: 'list' | 'recipe') {
  promptKind.value = kind
  promptName.value = ''
  promptListType.value = 'checklist'
  promptError.value = ''
  promptOpen.value = true
  createFormOpen.value = true
}

watch(promptOpen, (open) => {
  if (!open) createFormOpen.value = false
})

const menuOpen = ref(false)

function selectAction(onSelect: () => void) {
  menuOpen.value = false
  onSelect()
}

const speedDialItems = [
  { label: 'List', icon: 'i-lucide-clipboard-list', onSelect: () => openNamePrompt('list') },
  { label: 'Recipe', icon: 'i-lucide-cooking-pot', onSelect: () => openNamePrompt('recipe') },
  { label: 'Item', icon: 'i-lucide-pencil-sparkles', onSelect: () => navigateTo('/items?new=1') },
]

async function submitPrompt() {
  if (promptSaving.value) return // already in flight - ignore a second click/Enter
  if (!space.value || !promptName.value.trim()) return
  promptError.value = ''
  promptSaving.value = true

  const table = promptKind.value === 'list' ? 'lists' : 'recipes'
  const { data, error: insertError } =
    table === 'lists'
      ? await supabase
          .from('lists')
          .insert({ space_id: space.value.id, name: promptName.value.trim(), list_type: promptListType.value })
          .select('id')
          .single()
      : await supabase
          .from('recipes')
          .insert({ space_id: space.value.id, name: promptName.value.trim() })
          .select('id')
          .single()

  promptSaving.value = false
  if (insertError || !data) {
    promptError.value = insertError?.message ?? 'Failed to create'
    return
  }

  promptOpen.value = false
  await navigateTo(`/${table}/${data.id}?new=1`)
}
</script>

<template>
  <div
    v-if="!createFormOpen"
    class="fixed right-4 z-40 flex flex-col items-end gap-3"
    style="bottom: calc(5rem + env(safe-area-inset-bottom))"
  >
    <div v-if="menuOpen" class="fixed inset-0 -z-10" @click="menuOpen = false" />

    <TransitionGroup v-if="menuOpen" name="fab-pop">
      <button
        v-for="(item, i) in speedDialItems"
        :key="item.label"
        type="button"
        :style="{ transitionDelay: `${i * 30}ms` }"
        class="flex items-center gap-2 rounded-full border border-default bg-default py-2 pl-4 pr-3 shadow-lg hover:bg-elevated"
        @click="selectAction(item.onSelect)"
      >
        <span class="text-sm font-medium">{{ item.label }}</span>
        <UIcon :name="item.icon" class="size-5 text-primary" />
      </button>
    </TransitionGroup>

    <UButton
      :icon="menuOpen ? 'i-lucide-x' : 'i-lucide-plus'"
      size="xl"
      class="rounded-full shadow-lg transition-transform"
      @click="menuOpen = !menuOpen"
    />
  </div>

  <UModal v-model:open="promptOpen" :title="promptTitle">
    <template #body>
      <form class="flex flex-col gap-3" @submit.prevent="submitPrompt">
        <UInput v-model="promptName" :placeholder="promptPlaceholder" autofocus required class="w-full" />
        <template v-if="promptKind === 'list'">
          <USelect v-model="promptListType" :items="listTypeOptions" value-key="value" class="w-full" />
          <p class="text-muted -mt-1 text-xs">List type can't be changed after creation.</p>
        </template>
        <p v-if="promptError" class="text-sm text-red-500">{{ promptError }}</p>
        <UButton type="submit" block :loading="promptSaving">Create</UButton>
      </form>
    </template>
  </UModal>
</template>

<style scoped>
.fab-pop-enter-active,
.fab-pop-leave-active {
  transition: all 0.18s ease;
}
.fab-pop-enter-from,
.fab-pop-leave-to {
  opacity: 0;
  transform: translateY(8px) scale(0.9);
}
</style>
