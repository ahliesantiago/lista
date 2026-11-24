<script setup lang="ts">
// Thin wrapper around UInputMenu that closes the dropdown after each pick.
// Reka's combobox doesn't reliably self-close in every case in this app -
// multi-select keeps it open by design (useful elsewhere, not here, since
// every multi-select here is a quick 0-2 item pick), and a few single-selects
// whose :items list is itself reactive don't close either. All props/
// events/slots pass through untouched - this only adds the auto-close.
defineOptions({ inheritAttrs: false })
const open = ref(false)
</script>

<template>
  <UInputMenu v-model:open="open" v-bind="$attrs" @update:model-value="open = false">
    <template v-for="(_, slotName) in $slots" #[slotName]="slotProps">
      <slot :name="slotName" v-bind="slotProps" />
    </template>
  </UInputMenu>
</template>
