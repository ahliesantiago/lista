export function usePageEntityName() {
  return useState<string | null>('page-entity-name', () => null)
}
