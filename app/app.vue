<script setup>
import { ref, onMounted } from 'vue'
import { createClient } from '@supabase/supabase-js'

const config = useRuntimeConfig()
const supabase = createClient(config.public.supabaseUrl, config.public.supabaseKey)
const lists = ref([])

async function getLists() {
  const { data } = await supabase.from('lists').select()
  lists.value = data
}

onMounted(() => {
  getLists()
})
</script>

<template>
  <ul>
    <li v-for="list in lists" :key="list.id">{{ list.name }}</li>
  </ul>
</template>
