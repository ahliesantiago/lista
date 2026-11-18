export type TreeSortBy = 'custom' | 'name-asc'
export type TreeGroupBy = 'none' | 'category' | 'tag'

type Classified = {
  item: {
    item_categories: { categories: { name: string } | null }[]
    item_tags: { tags: { name: string } | null }[]
  } | null
}

export function useGroupedItemTree<
  TChild extends { id: string; name: string; is_done: boolean },
  TNode extends TChild & Classified & { children: TChild[] },
>(itemTree: Ref<TNode[]>, sortBy: Ref<TreeSortBy>, groupBy: Ref<TreeGroupBy>, moveDoneToBottom: Ref<boolean>) {
  function orderNodes<T extends { name: string; is_done: boolean }>(nodes: T[]): T[] {
    const ordered = sortBy.value === 'name-asc' ? [...nodes].sort((a, b) => a.name.localeCompare(b.name)) : nodes
    if (!moveDoneToBottom.value) return ordered
    return [...ordered.filter((n) => !n.is_done), ...ordered.filter((n) => n.is_done)]
  }

  function groupKeys(node: TNode): string[] {
    if (groupBy.value === 'category') {
      const cats = node.item?.item_categories ?? []
      return cats.length > 0 ? cats.map((c) => c.categories?.name ?? '?') : ['Uncategorized']
    }
    if (groupBy.value === 'tag') {
      const tags = node.item?.item_tags ?? []
      return tags.length > 0 ? tags.map((t) => t.tags?.name ?? '?') : ['Untagged']
    }
    return []
  }

  const displayNodes = computed<TNode[]>(() =>
    itemTree.value.map((node) => ({ ...node, children: orderNodes(node.children) })),
  )

  const groupedTree = computed(() => {
    if (groupBy.value === 'none') return null
    const buckets = new Map<string, TNode[]>()
    for (const node of displayNodes.value) {
      for (const key of groupKeys(node)) {
        if (!buckets.has(key)) buckets.set(key, [])
        buckets.get(key)!.push(node)
      }
    }
    return [...buckets.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([groupName, nodes]) => [groupName, orderNodes(nodes)] as const)
  })

  const flatSortedTree = computed(() => (groupBy.value === 'none' ? orderNodes(displayNodes.value) : null))

  return { displayNodes, groupedTree, flatSortedTree }
}
