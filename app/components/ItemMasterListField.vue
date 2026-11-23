<script setup lang="ts">
type Option = { id: string; name: string; plural_name?: string | null }
const ITEM_FILTER_FIELDS = ['name', 'plural_name']

const props = defineProps<{
  itemOptions: Option[]
  originalItem?: Option | null // Only when editing an existing list item; decides which checkbox to show when the typed text no longer resolves to a saved item
}>()

const item = defineModel<Option | null>('item', { default: null })
const confirmAction = defineModel<boolean>('addToMasterList', { default: true })

const itemPickerOpen = ref(false)
const isEditingExistingLink = computed(() => !!props.originalItem)

// Show "Create" unless the typed text exactly matches an existing item's name (case-insensitive)
const searchTerm = ref('')
const hasExactMatch = computed(() => {
  const term = searchTerm.value.trim().toLowerCase()
  if (!term) return false
  return props.itemOptions.some((o) => o.name.toLowerCase() === term)
})
const createItemConfig = computed(() => (hasExactMatch.value ? false : { when: 'always' as const, position: 'bottom' as const }))

function onCreate(searchTerm: string) {
  item.value = { id: '', name: searchTerm }
  /**
   * "Add to master list" checkbox state persists and resets to true only
   * when adding an existing item to the list.
   */
  // editing an existing link: reset to the default each time, since it's a
  // new item every time this opens. Adding new items to a list: leave it
  // alone, so the user's choice carries over to the next item they add.
  if (isEditingExistingLink.value) confirmAction.value = false
  itemPickerOpen.value = false
}

function clear() {
  item.value = null
  if (isEditingExistingLink.value) confirmAction.value = false
}
</script>

<template>
  <div class="flex flex-col gap-1">
    <div class="flex flex-wrap items-center gap-2">
      <UInputMenu
        v-model="item"
        v-model:open="itemPickerOpen"
        v-model:search-term="searchTerm"
        :items="itemOptions"
        :create-item="createItemConfig"
        label-key="name"
        :filter-fields="ITEM_FILTER_FIELDS"
        placeholder="Item name"
        class="flex-1"
        @create="onCreate"
      />
      <UButton v-if="item" size="sm" variant="ghost" icon="i-lucide-x" class="shrink-0" @click="clear" />
      <UBadge v-if="item && item.id" size="sm" variant="subtle" color="success" class="shrink-0">
        Already in master list
      </UBadge>
      <UCheckbox
        v-else-if="isEditingExistingLink"
        v-model="confirmAction"
        label="Update saved item"
        class="shrink-0"
      />
      <UCheckbox
        v-else
        v-model="confirmAction"
        label="Add to master list"
        class="shrink-0 items-center sm:max-w-24"
        :ui="{ base: 'sm:size-3', icon: 'sm:size-2.5', container: 'sm:h-4', wrapper: 'sm:text-xs' }"
      />
    </div>
    <p v-if="isEditingExistingLink && !(item && item.id) && !confirmAction" class="text-muted text-xs">
      Only applies to this entry, not the shared item.
    </p>
  </div>
</template>
