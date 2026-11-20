/**
 * Hook to track whether any create form is open in the app,
 * shared across the whole app (layout + every page with its own add/create
 * form) so the floating create button can hide itself whenever any of them
 * is actively open, not just its own popup.
 *
 * @returns A reactive boolean state indicating whether any create form is open.
 */
export function useCreateFormOpen() {
  return useState('create-form-open', () => false)
}
