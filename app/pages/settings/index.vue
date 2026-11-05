<script setup lang="ts">
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <h1 class="mb-6 text-xl font-semibold">Settings</h1>

    <div class="flex flex-col gap-4">
      <div class="rounded border border-default px-4 py-3 opacity-60">
        <h2 class="font-medium">Profile</h2>
        <p class="text-muted text-sm">Display name, avatar. Coming soon.</p>
      </div>

      <div class="rounded border border-default px-4 py-3 opacity-60">
        <h2 class="font-medium">Space</h2>
        <p class="text-muted text-sm">Rename your space, manage members. Coming soon.</p>
      </div>

      <div class="rounded border border-default px-4 py-3 opacity-60">
        <h2 class="font-medium">Notifications</h2>
        <p class="text-muted text-sm">Coming soon.</p>
      </div>

      <div class="flex items-center justify-between rounded border border-default px-4 py-3">
        <div>
          <h2 class="font-medium">Trash</h2>
          <p class="text-muted text-sm">Restore or permanently delete anything you've removed.</p>
        </div>
        <UButton to="/trash" variant="outline">Go to Trash</UButton>
      </div>
    </div>
  </div>
</template>
