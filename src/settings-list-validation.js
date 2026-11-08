// Guards: F-PDESC all-provider pilot exit (9 Nov 2026) and G2 audited list controls.
// Only the provider-description whitelist uses [] as a documented "all eligible" scope.
// Every other list setting retains its non-empty validation.
export function parseSettingList(value) {
  return String(value ?? '').split(',').map(item => item.trim()).filter(Boolean)
}

export function validSettingList(key, items) {
  return Array.isArray(items) && (items.length > 0 || key === 'pdesc.provider_keys')
}

export function settingListReadout(key, items) {
  if (key === 'pdesc.provider_keys' && Array.isArray(items) && items.length === 0) {
    return 'All eligible providers (country and type limits still apply)'
  }
  return Array.isArray(items) ? items.join(', ') : String(items ?? '')
}
