<script setup lang="ts">
/**
 * This is a simplified version of ItemMasterListField,
 * used only in the recipe page for adding a new ingredient (either by
 * picking an item from the master list or creating a new one on the fly)
 * or editing the linked item.
 */
type Option = { id: string; name: string; plural_name?: string | null }
const ITEM_FILTER_FIELDS = ['name', 'plural_name']

defineProps<{ itemOptions: Option[] }>()

const item = defineModel<Option | null>('item', { default: null })

function onCreate(searchTerm: string) {
  item.value = { id: '', name: searchTerm }
}
</script>

<template>
  <UInputMenu
    v-model="item"
    :items="itemOptions"
    create-item
    label-key="name"
    :filter-fields="ITEM_FILTER_FIELDS"
    placeholder="Item name"
    class="w-full"
    @create="onCreate"
  />
</template>
