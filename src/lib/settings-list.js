// List settings in Settings > Pipeline settings (CF-247 F-PDESC, 9 Nov 2026). A list setting is typed as comma-separated values.
// Its minimum number of values is the setting's own range minimum (min_value): none recorded means one value, as before; 0 means an empty list is
// allowed where the setting's help says an empty list is valid (for example pdesc.provider_keys: empty is every provider).
export const listShown = x => Array.isArray(x) ? x.join(', ') : String(x ?? '')
export const parseList = text => String(text ?? '').split(',').map(x => x.trim()).filter(Boolean)
export const listMin = s => (s && s.min != null && Number.isFinite(Number(s.min))) ? Math.max(0, Math.floor(Number(s.min))) : 1
export const listValid = (s, text) => parseList(text).length >= listMin(s)
export const listError = s => listMin(s) <= 0 ? '' : listMin(s) === 1 ? 'At least one value.' : `At least ${listMin(s)} values.`
// an empty list means "none" where the setting's help says so (intake_dates.nearest_start_providers, Decision 271), otherwise "all" as before
export const listPlaceholder = s => listMin(s) <= 0 ? (/\bempty\b[^.]*\bno provider\b/i.test(String(s?.help || '')) ? 'Empty means none' : 'Empty means all') : ''
// A list of provider ids (CF-247 F-OPS, 11 Nov 2026, Platform Admin 14:38 "there has to be better way in UI rather that using the provider's ID"): the setting's
// unit is "provider ids", or every value it holds is a provider id. Such a list is shown by provider name and providers are added by name (ProviderListPicker).
export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
export const isProviderIdList = s => !!s && s.kind === 'list' && (String(s.unit || '').toLowerCase() === 'provider ids'
  || (Array.isArray(s.value) && s.value.length > 0 && s.value.every(x => UUID_RE.test(String(x)))))
