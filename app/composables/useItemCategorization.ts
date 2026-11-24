export function useItemCategorization() {
  const supabase = useSupabaseClient()

  // is_primary applies strictly to main-category rows (parent_id null);
  // is_primary_subcategory to the rest - kept as two flags so an item can
  // have one of each marked primary at the same time (see useGroupedItemTree)
  async function setPrimaryCategory(itemId: string, categoryId: string) {
    await supabase.from('item_categories').update({ is_primary: true }).eq('item_id', itemId).eq('category_id', categoryId)
    await supabase.from('item_categories').update({ is_primary: false }).eq('item_id', itemId).neq('category_id', categoryId)
  }
  async function setPrimarySubcategory(itemId: string, categoryId: string) {
    await supabase
      .from('item_categories')
      .update({ is_primary_subcategory: true })
      .eq('item_id', itemId)
      .eq('category_id', categoryId)
    await supabase
      .from('item_categories')
      .update({ is_primary_subcategory: false })
      .eq('item_id', itemId)
      .neq('category_id', categoryId)
  }
  async function setPrimaryTag(itemId: string, tagId: string) {
    await supabase.from('item_tags').update({ is_primary: true }).eq('item_id', itemId).eq('tag_id', tagId)
    await supabase.from('item_tags').update({ is_primary: false }).eq('item_id', itemId).neq('tag_id', tagId)
  }

  type CategoryLink = {
    categories: { name: string; parent_id: string | null } | null
    is_primary: boolean
    is_primary_subcategory: boolean
  }

  // "Category" grouping - main categories only, subcategories never
  // participate even if that's all an item has linked
  function primaryCategoryKeys(links: CategoryLink[]): string[] {
    const mains = links.filter((l) => !l.categories?.parent_id)
    if (mains.length === 0) return ['Uncategorized']
    const primary = mains.find((l) => l.is_primary) ?? mains[0]!
    return [primary.categories?.name ?? '?']
  }

  // "Category & Subcategory" grouping - subcategory if the item has one,
  // else its main category, else Uncategorized
  function categoryAndSubcategoryKeys(links: CategoryLink[]): string[] {
    const subs = links.filter((l) => l.categories?.parent_id)
    if (subs.length > 0) {
      const primarySub = subs.find((l) => l.is_primary_subcategory) ?? subs[0]!
      return [primarySub.categories?.name ?? '?']
    }
    return primaryCategoryKeys(links)
  }

  // for the "Category & Subcategory" grouping view - lets a group heading
  // show which main category a subcategory group belongs to, so the
  // hierarchy reads as nested rather than a flat list of unrelated names
  function parentCategoryNameFor(
    categoryOptions: { id: string; name: string; parent_id: string | null }[],
    groupName: string,
  ): string | null {
    const sub = categoryOptions.find((c) => c.name === groupName && c.parent_id)
    if (!sub) return null
    return categoryOptions.find((c) => c.id === sub.parent_id)?.name ?? null
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
   * is marked as primary if applicable. `primaryColumn` lets callers target
   * is_primary_subcategory instead of is_primary - used to maintain the
   * main-category and subcategory primaries independently via two calls.
   */
  async function syncPrimaryLinks(
    table: 'item_categories' | 'item_tags',
    idColumn: 'category_id' | 'tag_id',
    itemId: string,
    prevLinks: { id: string; is_primary: boolean }[],
    nextIds: string[],
    primaryColumn: 'is_primary' | 'is_primary_subcategory' = 'is_primary',
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
      // two computed keys in one literal (idColumn + primaryColumn) defeats
      // Supabase's generated insert-type narrowing across the table union -
      // the shape is still correct at runtime, just not provable to tsc here
      const rows = added.map((id) => ({
        item_id: itemId,
        [idColumn]: id,
        [primaryColumn]: id === promoteAdded,
      }))
      await supabase.from(table).insert(rows as never)
    }
    if (promoteKept) {
      await supabase
        .from(table)
        .update({ [primaryColumn]: true } as never)
        .eq('item_id', itemId)
        .eq(idColumn as never, promoteKept)
    }
  }

  return {
    setPrimaryCategory,
    setPrimarySubcategory,
    setPrimaryTag,
    primaryCategoryKeys,
    categoryAndSubcategoryKeys,
    parentCategoryNameFor,
    primaryTagKeys,
    syncPrimaryLinks,
  }
}
