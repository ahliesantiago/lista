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

function onCreate(searchTerm: string) {
  item.value = { id: '', name: searchTerm }
  confirmAction.value = !isEditingExistingLink.value
  itemPickerOpen.value = false
}

/**
 * Clears the item field and resets the checkbox to its default state
 * (checked for new items, unchecked for existing items).
 */
function clear() {
  item.value = null
  confirmAction.value = !isEditingExistingLink.value
}
</script>

<template>
  <div class="flex flex-col gap-1">
    <div class="flex items-center gap-2">
      <UInputMenu
        v-model="item"
        v-model:open="itemPickerOpen"
        :items="itemOptions"
        create-item
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
      <UCheckbox v-else v-model="confirmAction" label="Add to master list" class="shrink-0" />
    </div>
    <p v-if="isEditingExistingLink && !(item && item.id) && !confirmAction" class="text-muted text-xs">
      Only applies to this entry, not the shared item.
    </p>
  </div>
</template>
