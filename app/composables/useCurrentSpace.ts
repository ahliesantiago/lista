export function useCurrentSpace() {
  const supabase = useSupabaseClient()

  return useAsyncData('current-space', async () => {
    const { data, error } = await supabase
      .from('spaces')
      .select('id, name')
      .order('created_at')
      .limit(1)
      .single()
    if (error) throw error
    return data
  })
}
