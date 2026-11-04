<script setup lang="ts">
const supabase = useSupabaseClient()

const { data: spaces } = await useAsyncData('my-spaces', async () => {
  const { data, error } = await supabase.from('spaces').select('id, name').order('created_at')
  if (error) throw error
  return data
})

const currentSpace = computed(() => spaces.value?.[0])
</script>

<template>
  <div>
    <h1 class="text-xl font-semibold">
      Welcome to <span v-if="currentSpace">{{ currentSpace.name }}</span>
    </h1>
    <p v-if="!currentSpace" class="text-muted">No space found yet.</p>
  </div>
</template>
