export function useItemCategorization() {
  const supabase = useSupabaseClient()

  async function setPrimaryCategory(itemId: string, categoryId: string) {
    await supabase.from('item_categories').update({ is_primary: true }).eq('item_id', itemId).eq('category_id', categoryId)
    await supabase.from('item_categories').update({ is_primary: false }).eq('item_id', itemId).neq('category_id', categoryId)
  }
  async function setPrimaryTag(itemId: string, tagId: string) {
    await supabase.from('item_tags').update({ is_primary: true }).eq('item_id', itemId).eq('tag_id', tagId)
    await supabase.from('item_tags').update({ is_primary: false }).eq('item_id', itemId).neq('tag_id', tagId)
  }

  function primaryCategoryKeys(links: { categories: { name: string } | null; is_primary: boolean }[]): string[] {
    if (links.length === 0) return ['Uncategorized']
    const primary = links.find((l) => l.is_primary) ?? links[0]!
    return [primary.categories?.name ?? '?']
  }
  function primaryTagKeys(links: { tags: { name: string } | null; is_primary: boolean }[]): string[] {
    if (links.length === 0) return ['Untagged']
    const primary = links.find((l) => l.is_primary) ?? links[0]!
    return [primary.tags?.name ?? '?']
  }

  /**
   * @function syncPrimaryLinks
   * @description Synchronizes the primary links for an item in
   * either the item_categories or item_tags table. It updates the
   * database to reflect the new set of links, ensuring that one link
   * is marked as primary if applicable.
   */
  async function syncPrimaryLinks(
    table: 'item_categories' | 'item_tags',
    idColumn: 'category_id' | 'tag_id',
    itemId: string,
    prevLinks: { id: string; is_primary: boolean }[],
    nextIds: string[],
  ) {
    const prevMap = new Map(prevLinks.map((l) => [l.id, l.is_primary]))
    const nextSet = new Set(nextIds)
    const removed = prevLinks.filter((l) => !nextSet.has(l.id))
    const added = nextIds.filter((id) => !prevMap.has(id))
    const kept = nextIds.filter((id) => prevMap.has(id))
    const survivingPrimary = kept.some((id) => prevMap.get(id) === true)
    const promoteKept = !survivingPrimary && kept.length > 0 ? kept[0] : undefined
    const promoteAdded = !survivingPrimary && promoteKept === undefined ? added[0] : undefined

    if (removed.length > 0) {
      await supabase
        .from(table)
        .delete()
        .eq('item_id', itemId)
        .in(idColumn, removed.map((l) => l.id))
    }
    if (added.length > 0) {
      await supabase
        .from(table)
        .insert(added.map((id) => ({ item_id: itemId, [idColumn]: id, is_primary: id === promoteAdded })))
    }
    if (promoteKept) {
      await supabase.from(table).update({ is_primary: true }).eq('item_id', itemId).eq(idColumn, promoteKept)
    }
  }

  return { setPrimaryCategory, setPrimaryTag, primaryCategoryKeys, primaryTagKeys, syncPrimaryLinks }
}
