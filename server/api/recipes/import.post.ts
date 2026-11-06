function parseISODuration(duration: unknown): number | null {
  if (typeof duration !== 'string') return null
  const match = duration.match(/^P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/)
  if (!match) return null
  const [, days, hours, minutes] = match
  const total = (Number(days) || 0) * 24 * 60 + (Number(hours) || 0) * 60 + (Number(minutes) || 0)
  return total > 0 ? total : null
}

function firstImageUrl(image: unknown): string | null {
  if (!image) return null
  if (typeof image === 'string') return image
  if (Array.isArray(image)) return firstImageUrl(image[0])
  if (typeof image === 'object' && image !== null && 'url' in image) return String((image as any).url)
  return null
}

function flattenInstructions(instructions: unknown): string[] {
  if (!instructions) return []
  if (typeof instructions === 'string') {
    return instructions
      .split(/\n+/)
      .map((s) => s.trim())
      .filter(Boolean)
  }
  if (Array.isArray(instructions)) {
    return instructions.flatMap((item) => {
      if (typeof item === 'string') return [item]
      if (item && typeof item === 'object') {
        const obj = item as any
        if (obj['@type'] === 'HowToSection' && Array.isArray(obj.itemListElement)) {
          return flattenInstructions(obj.itemListElement)
        }
        if (typeof obj.text === 'string') return [obj.text]
      }
      return []
    })
  }
  return []
}

function findRecipe(node: unknown): any | null {
  if (!node) return null
  if (Array.isArray(node)) {
    for (const item of node) {
      const found = findRecipe(item)
      if (found) return found
    }
    return null
  }
  if (typeof node !== 'object') return null
  const obj = node as any
  const type = obj['@type']
  const types = Array.isArray(type) ? type : [type]
  if (types.includes('Recipe')) return obj
  if (Array.isArray(obj['@graph'])) return findRecipe(obj['@graph'])
  return null
}

export default defineEventHandler(async (event) => {
  const { url } = await readBody<{ url: string }>(event)
  if (!url || typeof url !== 'string') {
    throw createError({ statusCode: 400, statusMessage: 'Missing url' })
  }

  let html: string
  try {
    const res = await fetch(url, {
      headers: {
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
      },
    })
    if (!res.ok) throw new Error(`Fetch failed with status ${res.status}`)
    html = await res.text()
  } catch (err: any) {
    throw createError({ statusCode: 502, statusMessage: `Could not fetch URL: ${err.message}` })
  }

  const scriptMatches = html.matchAll(
    /<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi,
  )

  let recipe: any = null
  for (const match of scriptMatches) {
    try {
      const parsed = JSON.parse(match[1].trim())
      recipe = findRecipe(parsed)
      if (recipe) break
    } catch {
      // ignore malformed JSON-LD blocks and keep looking
    }
  }

  if (!recipe) {
    throw createError({ statusCode: 404, statusMessage: 'No schema.org Recipe found on that page' })
  }

  return {
    name: typeof recipe.name === 'string' ? recipe.name : '',
    description: typeof recipe.description === 'string' ? recipe.description : null,
    imageUrl: firstImageUrl(recipe.image),
    servings: recipe.recipeYield
      ? Array.isArray(recipe.recipeYield)
        ? String(recipe.recipeYield[0])
        : String(recipe.recipeYield)
      : null,
    prepTimeMinutes: parseISODuration(recipe.prepTime),
    cookTimeMinutes: parseISODuration(recipe.cookTime),
    totalTimeMinutes: parseISODuration(recipe.totalTime),
    ingredientLines: Array.isArray(recipe.recipeIngredient)
      ? recipe.recipeIngredient.filter((s: unknown) => typeof s === 'string')
      : [],
    steps: flattenInstructions(recipe.recipeInstructions),
  }
})
