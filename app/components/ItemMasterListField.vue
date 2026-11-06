<script setup lang="ts">
type Option = { id: string; name: string; plural_name?: string | null }
const ITEM_FILTER_FIELDS = ['name', 'plural_name']

defineProps<{ itemOptions: Option[] }>()

const item = defineModel<Option | null>('item', { default: null })
const addToMasterList = defineModel<boolean>('addToMasterList', { default: true })

const itemPickerOpen = ref(false)

function onCreate(searchTerm: string) {
  item.value = { id: '', name: searchTerm }
  addToMasterList.value = true
  itemPickerOpen.value = false
}
</script>

<template>
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
    <UBadge v-if="item && item.id" size="sm" variant="subtle" color="success" class="shrink-0">
      Already in master list
    </UBadge>
    <UCheckbox
      v-else
      v-model="addToMasterList"
      label="Add to master list"
      class="shrink-0"
    />
  </div>
</template>
