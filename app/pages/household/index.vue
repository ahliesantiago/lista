<script setup lang="ts">
const sections = [
  {
    label: 'Pantry',
    description: 'Food stock and storage location (linked to the Items masterlist).',
    to: '/pantry'
  },
  {
    label: 'Home Inventory',
    description: 'Linens, toilet paper, cleaning supplies, and other non-food stock.',
    to: '/home-inventory',
  },
  {
    label: 'Equipment',
    description: 'Cooking tools, cookware, etc.',
    to: '/equipment',
  },
  {
    label: 'Appliances',
    description: 'Brand, quantity, maintenance/replacement flags.',
    to: '/appliances'
  },
  {
    label: 'Furniture',
    description: 'Brand, room, quantity, maintenance/replacement flags.',
    to: '/furniture'
  },
  {
    label: 'Storage',
    description: 'Rooms and the storage locations within them.',
    to: '/rooms',
  },
]
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <div class="flex flex-col gap-4">
      <div
        v-for="section in sections"
        :key="section.to"
        class="flex items-center justify-between rounded border border-default px-4 py-3"
      >
        <div>
          <h2 class="font-medium">{{ section.label }}</h2>
          <p class="text-muted text-sm">{{ section.description }}</p>
        </div>
        <UButton :to="section.to" variant="outline" class="w-20 shrink-0 justify-center">View</UButton>
      </div>
    </div>
  </div>
</template>
