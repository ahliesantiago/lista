type CategoryOption = { id: string; name: string; parent_id: string | null }
type Space = { id: string } | null | undefined

// shared by items/lists (against the shared `categories` table) and recipes
// (against the dedicated `recipe_categories` table) - the only thing that
// differs between those is which table to write to
export function useCategoryCreation(
  table: 'categories' | 'recipe_categories',
  space: Ref<Space>,
  categoryOptions: Ref<CategoryOption[] | undefined | null>,
  selectedCategories: Ref<CategoryOption[]>,
  selectedSubcategories: Ref<CategoryOption[]>,
) {
  const supabase = useSupabaseClient()

  async function insertCategory(name: string, parentId: string | null): Promise<CategoryOption | null> {
    if (!space.value) return null
    const { data, error } = await supabase
      .from(table)
      .insert({ space_id: space.value.id, name, parent_id: parentId })
      .select('id, name, parent_id')
      .single()
    if (error || !data) return null
    categoryOptions.value = [...(categoryOptions.value ?? []), data]
    return data
  }

  async function onCreateCategoryOption(searchTerm: string) {
    const data = await insertCategory(searchTerm, null)
    if (data) selectedCategories.value.push(data)
  }

  async function onCreateSubcategoryOption(searchTerm: string) {
    // a subcategory needs a parent - default to the first currently
    // selected top-level category, matching the "pick a category first"
    // placeholder already shown on this picker
    const parentId = selectedCategories.value[0]?.id
    if (!parentId) return
    const data = await insertCategory(searchTerm, parentId)
    if (data) selectedSubcategories.value.push(data)
  }

  return { onCreateCategoryOption, onCreateSubcategoryOption }
}
