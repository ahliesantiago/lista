type SortDef<T> = { label: string; compare: (a: T, b: T) => number }
type GroupDef<T> = { label: string; getKeys: (item: T) => string[] }

export function useListControls<T>(
  filteredItems: Ref<T[]>,
  sorts: Record<string, SortDef<T>>,
  groups: Record<string, GroupDef<T>>,
) {
  const sortOptions = Object.entries(sorts).map(([value, { label }]) => ({ value, label }))
  const groupOptions = [
    { value: 'none', label: 'None' },
    ...Object.entries(groups).map(([value, { label }]) => ({ value, label })),
  ]

  const sortBy = ref(sortOptions[0]?.value ?? '')
  const groupBy = ref('none')

  const sortedItems = computed(() => {
    const list = [...filteredItems.value]
    const sort = sorts[sortBy.value]
    if (sort) list.sort(sort.compare)
    return list
  })

  const groupedItems = computed(() => {
    const group = groups[groupBy.value]
    if (!group) return null
    const buckets = new Map<string, T[]>()
    for (const item of sortedItems.value) {
      for (const key of group.getKeys(item)) {
        if (!buckets.has(key)) buckets.set(key, [])
        buckets.get(key)!.push(item)
      }
    }
    return [...buckets.entries()].sort((a, b) => a[0].localeCompare(b[0]))
  })

  return { sortBy, groupBy, sortOptions, groupOptions, sortedItems, groupedItems }
}
