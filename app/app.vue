<script setup>
import { ref, onMounted } from 'vue'

const supabase = useSupabaseClient()
const lists = ref([])

async function getLists() {
  const { data } = await supabase.from('lists').select()
  lists.value = data
  console.log(data)
}

onMounted(() => {
  getLists()
})
</script>

<template>
  <p>
    Hello!
  </p>
  <ul>
    <li v-for="list in lists" :key="list.id">{{ list.name }}</li>

    <li>Masterlist</li>
    <li>Categories</li>
    <li>Custom Lists</li>
    <li>Units</li>
  </ul>
</template>
