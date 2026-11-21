<script setup lang="ts">
type UnitOption = {
  id: string
  name_singular: string
  name_plural: string
  abbrev_singular: string | null
  abbrev_plural: string | null
}
type ItemRow = {
  id: string
  name: string
  amount: number | null
  size: string | null
  notes: string | null
  is_done: boolean
  item_id: string | null
  unit: { id: string; name_singular: string; name_plural: string } | null
  list_item_sources: {
    quantity: number | null
    unit: { name_singular: string; name_plural: string } | null
    recipe: { name: string } | null
  }[]
  item: {
    item_categories: { is_primary: boolean; categories: { id: string; name: string; parent_id: string | null } | null }[]
    item_tags: { is_primary: boolean; tags: { id: string; name: string } | null }[]
  } | null
}
type EditDraft = {
  name: string
  isListOnly: boolean
  amount: number | null
  unitId: string | null
  size: string
  notes: string
}

const UNIT_FILTER_FIELDS = ['name_singular', 'name_plural', 'abbrev_singular', 'abbrev_plural']

const props = defineProps<{
  item: ItemRow
  // 'checklist': checkbox + amount/unit/size/notes/sources + category/tag
  // badges, as before. 'plain': a bullet/number marker + name only, no
  // master-item link ever exists for these rows so none of that applies.
  variant: 'checklist' | 'plain'
  marker: string | null
  // null => no nest affordance shown at all; caller decides when indenting
  // or outdenting this particular row is actually valid
  nestButton: 'indent' | 'outdent' | null
  reorderable: boolean
  editable: boolean
  editingId: string | null
  unitOptions: UnitOption[]
  extraEditUnitOption: { id: string; name_singular: string; name_plural: string } | null
}>()

const draft = defineModel<EditDraft | null>('draft', { required: true })

const emit = defineEmits<{
  'toggle-done': []
  'start-edit': []
  'cancel-edit': []
  'save-edit': []
  remove: []
  nest: []
  'switch-category': [categoryId: string]
  'switch-tag': [tagId: string]
}>()

const isEditing = computed(() => props.editingId === props.item.id)

function unitLabel(unit: { name_singular: string; name_plural: string } | null, amount: number | null) {
  if (!unit) return ''
  return amount != null && amount !== 1 ? unit.name_plural : unit.name_singular
}

function sourcesLabel(sources: ItemRow['list_item_sources']) {
  const withRecipe = sources.filter((s) => s.recipe)
  if (withRecipe.length === 0) return ''
  return withRecipe
    .map((s) => {
      const qty = s.quantity != null ? `${s.quantity} ${unitLabel(s.unit, s.quantity)}`.trim() : ''
      return `${qty ? qty + ' ' : ''}from ${s.recipe!.name}`
    })
    .join(', ')
}

const editUnitOptionsForAmount = computed(() => {
  const label = (u: { name_singular: string; name_plural: string }) =>
    draft.value?.amount != null && draft.value.amount !== 1 ? u.name_plural : u.name_singular
  const base = props.unitOptions.map((u) => ({ ...u, label: label(u) }))
  const extra = props.extraEditUnitOption
  if (extra && !base.some((u) => u.id === extra.id)) {
    return [...base, { ...extra, abbrev_singular: null, abbrev_plural: null, label: label(extra) }]
  }
  return base
})
</script>

<template>
  <div class="rounded border border-default px-3 py-2">
    <div v-if="!isEditing" class="flex items-center justify-between">
      <div class="flex flex-1 items-center gap-1">
        <UIcon
          v-if="reorderable"
          name="i-lucide-grip-vertical"
          class="drag-handle text-muted shrink-0 cursor-grab"
        />
        <UButton
          v-if="nestButton === 'indent'"
          size="sm"
          variant="ghost"
          icon="i-lucide-chevron-right"
          title="Nest under previous item"
          @click="emit('nest')"
        />
        <UButton
          v-if="nestButton === 'outdent'"
          size="sm"
          variant="ghost"
          icon="i-lucide-chevron-left"
          title="Move to top level"
          @click="emit('nest')"
        />
        <span v-if="variant === 'plain'" class="text-muted w-5 shrink-0 text-center">{{ marker }}</span>

        <label v-if="variant === 'checklist'" class="flex flex-1 items-center gap-3">
          <UCheckbox :model-value="item.is_done" @update:model-value="emit('toggle-done')" />
          <span :class="{ 'text-muted line-through': item.is_done }">
            {{ item.name }}
            <span v-if="item.amount != null" class="text-muted text-sm">
              {{ item.amount }}<span v-if="item.unit">{{ ' ' + unitLabel(item.unit, item.amount) }}</span>
            </span>
            <span v-if="item.size" class="text-muted text-sm">({{ item.size }})</span>
            <span v-if="item.notes" class="text-muted block text-xs">{{ item.notes }}</span>
            <span v-if="sourcesLabel(item.list_item_sources)" class="text-muted block text-xs">
              {{ sourcesLabel(item.list_item_sources) }}
            </span>
          </span>
        </label>
        <span v-else class="flex-1">{{ item.name }}</span>

        <template v-if="variant === 'checklist'">
          <UBadge
            v-for="ic in item.item?.item_categories ?? []"
            :key="ic.categories!.id"
            size="sm"
            :variant="ic.categories!.parent_id ? 'subtle' : 'solid'"
            class="cursor-pointer"
            :title="ic.is_primary ? 'Primary category (used for grouping)' : 'Click to make this the primary category'"
            @click.stop="emit('switch-category', ic.categories!.id)"
          >
            <UIcon v-if="ic.is_primary" name="i-lucide-star" class="mr-1 size-3" />
            {{ ic.categories!.name }}
          </UBadge>
          <UBadge
            v-for="t in item.item?.item_tags ?? []"
            :key="t.tags!.id"
            size="sm"
            variant="outline"
            class="cursor-pointer"
            :title="t.is_primary ? 'Primary tag (used for grouping)' : 'Click to make this the primary tag'"
            @click.stop="emit('switch-tag', t.tags!.id)"
          >
            <UIcon v-if="t.is_primary" name="i-lucide-star" class="mr-1 size-3" />
            {{ t.tags!.name }}
          </UBadge>
        </template>
      </div>
      <div v-if="editable" class="flex items-center gap-1">
        <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="emit('start-edit')" />
        <UButton size="sm" variant="ghost" color="error" icon="i-lucide-trash-2" @click="emit('remove')" />
      </div>
    </div>

    <div v-else-if="draft" class="flex flex-col gap-2">
      <UInput v-if="variant === 'plain' || draft.isListOnly" v-model="draft.name" placeholder="Name" />
      <span v-else class="font-medium">{{ item.name }}</span>
      <div v-if="variant === 'checklist'" class="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <UInputNumber v-model="draft.amount" placeholder="Qty" :min="0" />
        <USelectMenu
          v-model="draft.unitId"
          :items="editUnitOptionsForAmount"
          value-key="id"
          label-key="label"
          :filter-fields="UNIT_FILTER_FIELDS"
          placeholder="Unit"
        />
        <UInput v-model="draft.size" placeholder="Size" />
      </div>
      <UInput v-if="variant === 'checklist'" v-model="draft.notes" placeholder="Notes (optional)" />
      <div class="flex gap-2">
        <UButton size="sm" @click="emit('save-edit')">Save</UButton>
        <UButton size="sm" variant="ghost" @click="emit('cancel-edit')">Cancel</UButton>
      </div>
    </div>
  </div>
</template>
