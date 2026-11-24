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
    item_categories: {
      is_primary: boolean
      is_primary_subcategory: boolean
      categories: { id: string; name: string; parent_id: string | null } | null
    }[]
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
  // while true, the left checkbox/marker slot (normally is_done for
  // checklist, a bare marker for plain) is repurposed for bulk selection
  bulkEditMode: boolean
  selected: boolean
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
  'switch-subcategory': [categoryId: string]
  'switch-tag': [tagId: string]
  'toggle-select': []
}>()

const isEditing = computed(() => props.editingId === props.item.id)

const mainCategories = computed(() => props.item.item?.item_categories.filter((ic) => !ic.categories?.parent_id) ?? [])
const subcategories = computed(() => props.item.item?.item_categories.filter((ic) => ic.categories?.parent_id) ?? [])

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

// size/notes stay hidden behind a toggle when editing an item that doesn't
// already have one set, same as the add form - these don't need to reset
// when editing ends since the v-if conditions already fall back to
// draft.size/draft.notes being non-empty regardless of this ref's value
const showEditSize = ref(false)
const showEditNotes = ref(false)

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
    <template v-if="!isEditing">
    <div class="flex flex-wrap items-center justify-between gap-y-2">
      <div class="flex min-w-0 flex-1 items-center gap-1">
        <label v-if="bulkEditMode" class="flex flex-1 items-center gap-3">
          <UCheckbox color="neutral" :model-value="selected" @update:model-value="emit('toggle-select')" />
          <span :class="{ 'text-muted line-through': variant === 'checklist' && item.is_done }">
            {{ item.name }}
            <template v-if="variant === 'checklist'">
              <span v-if="item.amount != null" class="text-muted text-sm">
                {{ item.amount }}<span v-if="item.unit">{{ ' ' + unitLabel(item.unit, item.amount) }}</span>
              </span>
              <span v-if="item.size" class="text-muted text-sm">({{ item.size }})</span>
              <span v-if="item.notes" class="text-muted block text-xs">{{ item.notes }}</span>
              <span v-if="sourcesLabel(item.list_item_sources)" class="text-muted block text-xs">
                {{ sourcesLabel(item.list_item_sources) }}
              </span>
            </template>
          </span>
        </label>

        <template v-else-if="variant === 'plain'">
          <span class="text-muted w-5 shrink-0 text-center">{{ marker }}</span>
          <span class="flex-1">{{ item.name }}</span>
        </template>

        <label v-else class="flex flex-1 items-center gap-3">
          <UCheckbox color="primary" :model-value="item.is_done" @update:model-value="emit('toggle-done')" />
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

        <div v-if="variant === 'checklist'" class="hidden flex-wrap items-center gap-1 sm:flex">
          <UChip v-for="ic in mainCategories" :key="ic.categories!.id" :show="ic.is_primary" color="primary" size="xs">
            <UBadge
              size="sm"
              color="primary"
              variant="solid"
              class="cursor-pointer"
              :title="ic.is_primary ? 'Primary category (used for grouping)' : 'Click to make this the primary category'"
              @click.stop="emit('switch-category', ic.categories!.id)"
            >
              {{ ic.categories!.name }}
            </UBadge>
          </UChip>
          <UChip
            v-for="ic in subcategories"
            :key="ic.categories!.id"
            :show="ic.is_primary_subcategory"
            color="warning"
            size="xs"
          >
            <UBadge
              size="sm"
              color="warning"
              variant="subtle"
              class="cursor-pointer"
              :title="
                ic.is_primary_subcategory
                  ? 'Primary subcategory (used for grouping)'
                  : 'Click to make this the primary subcategory'
              "
              @click.stop="emit('switch-subcategory', ic.categories!.id)"
            >
              {{ ic.categories!.name }}
            </UBadge>
          </UChip>
          <UChip v-for="t in item.item?.item_tags ?? []" :key="t.tags!.id" :show="t.is_primary" color="neutral" size="xs">
            <UBadge
              size="sm"
              color="neutral"
              variant="outline"
              class="cursor-pointer"
              :title="t.is_primary ? 'Primary tag (used for grouping)' : 'Click to make this the primary tag'"
              @click.stop="emit('switch-tag', t.tags!.id)"
            >
              {{ t.tags!.name }}
            </UBadge>
          </UChip>
        </div>
      </div>
      <div class="flex shrink-0 items-center">
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
        <template v-if="editable">
          <UButton size="sm" variant="ghost" icon="i-lucide-pencil" @click="emit('start-edit')" />
          <UButton size="sm" variant="ghost" color="error" icon="i-lucide-trash-2" @click="emit('remove')" />
        </template>
        <UIcon
          v-if="reorderable"
          name="i-lucide-grip-vertical"
          class="drag-handle text-muted shrink-0 cursor-grab"
        />
      </div>
    </div>

    <!-- mobile only: badges drop to their own row below the name instead of
         fighting the name/amount/unit text for space on narrow screens;
         ml-7 lines them up under the name text, past the checkbox+gap-3 -->
    <div
      v-if="variant === 'checklist' && ((item.item?.item_categories.length ?? 0) > 0 || (item.item?.item_tags.length ?? 0) > 0)"
      class="mt-1 ml-7 flex flex-wrap items-center gap-1 sm:hidden"
    >
      <UChip v-for="ic in mainCategories" :key="ic.categories!.id" :show="ic.is_primary" color="primary" size="2xs">
        <UBadge
          size="xs"
          color="primary"
          variant="solid"
          class="cursor-pointer"
          :title="ic.is_primary ? 'Primary category (used for grouping)' : 'Click to make this the primary category'"
          @click.stop="emit('switch-category', ic.categories!.id)"
        >
          {{ ic.categories!.name }}
        </UBadge>
      </UChip>
      <UChip
        v-for="ic in subcategories"
        :key="ic.categories!.id"
        :show="ic.is_primary_subcategory"
        color="warning"
        size="2xs"
      >
        <UBadge
          size="xs"
          color="warning"
          variant="subtle"
          class="cursor-pointer"
          :title="
            ic.is_primary_subcategory
              ? 'Primary subcategory (used for grouping)'
              : 'Click to make this the primary subcategory'
          "
          @click.stop="emit('switch-subcategory', ic.categories!.id)"
        >
          {{ ic.categories!.name }}
        </UBadge>
      </UChip>
      <UChip v-for="t in item.item?.item_tags ?? []" :key="t.tags!.id" :show="t.is_primary" color="neutral" size="2xs">
        <UBadge
          size="xs"
          color="neutral"
          variant="outline"
          class="cursor-pointer"
          :title="t.is_primary ? 'Primary tag (used for grouping)' : 'Click to make this the primary tag'"
          @click.stop="emit('switch-tag', t.tags!.id)"
        >
          {{ t.tags!.name }}
        </UBadge>
      </UChip>
    </div>
    </template>

    <div v-else-if="draft" class="flex flex-col gap-2">
      <UInput v-if="variant === 'plain' || draft.isListOnly" v-model="draft.name" placeholder="Name" />
      <span v-else class="font-medium">{{ item.name }}</span>
      <div v-if="variant === 'checklist'" class="flex flex-wrap items-center gap-1">
        <UInputNumber
          v-model="draft.amount"
          placeholder="Qty"
          :min="0"
          :increment="{ size: 'xs' }"
          :decrement="{ size: 'xs' }"
          class="w-24"
        />
        <USelectMenu
          v-model="draft.unitId"
          :items="editUnitOptionsForAmount"
          value-key="id"
          label-key="label"
          :filter-fields="UNIT_FILTER_FIELDS"
          placeholder="Unit"
          class="flex-1"
        />
        <UButton
          v-if="!showEditSize && !draft.size"
          size="sm"
          variant="ghost"
          icon="i-lucide-ruler"
          title="Add size"
          @click="showEditSize = true"
        />
        <UButton
          v-if="!showEditNotes && !draft.notes"
          size="sm"
          variant="ghost"
          icon="i-lucide-notebook-pen"
          title="Add notes"
          @click="showEditNotes = true"
        />
      </div>
      <div
        v-if="variant === 'checklist' && (showEditSize || draft.size || showEditNotes || draft.notes)"
        class="flex w-full items-start gap-2"
      >
        <UInput
          v-if="showEditSize || draft.size"
          v-model="draft.size"
          placeholder="Size"
          :class="showEditNotes || draft.notes ? 'w-28 sm:w-40' : 'flex-1'"
        />
        <UInput v-if="showEditNotes || draft.notes" v-model="draft.notes" placeholder="Notes (optional)" class="flex-1" />
      </div>
      <div class="flex gap-2">
        <UButton size="sm" @click="emit('save-edit')">Save</UButton>
        <UButton size="sm" variant="ghost" @click="emit('cancel-edit')">Cancel</UButton>
      </div>
    </div>
  </div>
</template>
