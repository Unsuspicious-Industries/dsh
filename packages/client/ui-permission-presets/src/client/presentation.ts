/** Machine value of the preset that requires an explicit GUI risk gate. */
export const FULL_ACCESS_PRESET = 'danger-full-access'

/**
 * Convert conventional kebab-case preset names into user-facing title case.
 * The host owns the product label (`name` in the preset table); this only
 * prettifies a table key that a deployment left without one.
 * @param name - host-supplied preset label or key.
 * @returns the title-cased conventional key, or a non-kebab label unchanged.
 */
export function displayPresetName(name: string): string {
  if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(name)) return name
  return name.split('-').map(word => word.charAt(0).toUpperCase() + word.slice(1)).join(' ')
}
