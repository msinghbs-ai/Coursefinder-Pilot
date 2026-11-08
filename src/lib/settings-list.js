// List settings in Settings > Pipeline settings (CF-247 F-PDESC, 9 Nov 2026). A list setting is typed as comma-separated values.
// Its minimum number of values is the setting's own range minimum (min_value): none recorded means one value, as before; 0 means an empty list is
// allowed where the setting's help says an empty list is valid (for example pdesc.provider_keys: empty is every provider).
export const listShown = x => Array.isArray(x) ? x.join(', ') : String(x ?? '')
export const parseList = text => String(text ?? '').split(',').map(x => x.trim()).filter(Boolean)
export const listMin = s => (s && s.min != null && Number.isFinite(Number(s.min))) ? Math.max(0, Math.floor(Number(s.min))) : 1
export const listValid = (s, text) => parseList(text).length >= listMin(s)
export const listError = s => listMin(s) <= 0 ? '' : listMin(s) === 1 ? 'At least one value.' : `At least ${listMin(s)} values.`
export const listPlaceholder = s => listMin(s) <= 0 ? 'Empty means all' : ''
