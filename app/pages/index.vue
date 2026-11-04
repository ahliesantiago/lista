<script setup lang="ts">
const { data: currentSpace } = await useCurrentSpace()
</script>

<template>
  <div>
    <h1 class="text-xl font-semibold">
      Welcome to <span v-if="currentSpace">{{ currentSpace.name }}</span>
    </h1>
    <p v-if="!currentSpace" class="text-muted">No space found yet.</p>
  </div>
</template>
