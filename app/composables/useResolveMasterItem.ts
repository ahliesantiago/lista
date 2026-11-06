type Option = { id: string; name: string }

export function useResolveMasterItem() {
  const supabase = useSupabaseClient()

  // resolves a picked-or-typed item into a real item_id (or null for
  // ad-hoc), mirroring list_items' addItem(): a real id if one was picked,
  // a freshly inserted one if the typed name should join the master list,
  // otherwise left unresolved - `name` is always returned regardless
  async function resolveItem(
    spaceId: string,
    item: Option,
    addToMasterList: boolean,
    itemOptions: Ref<Option[]>,
  ): Promise<{ itemId: string | null; name: string }> {
    const name = item.name.trim()
    if (item.id) return { itemId: item.id, name }
    if (addToMasterList) {
      const { data } = await supabase
        .from('items')
        .insert({ space_id: spaceId, name })
        .select('id, name')
        .single()
      if (data) {
        itemOptions.value.push(data)
        return { itemId: data.id, name }
      }
    }
    return { itemId: null, name }
  }

  return { resolveItem }
}
