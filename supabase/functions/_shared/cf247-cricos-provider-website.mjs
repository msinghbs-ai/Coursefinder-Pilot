// CRICOS institution websites from the public register, including bare DNS names.
const WEB_SCHEME = /^https?:\/\//i
const DNS_NAME = /^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z](?:[a-z0-9-]*[a-z0-9])?\.?$/i

export function normaliseCricosProviderWebsite(value) {
  const website = typeof value === 'string' ? value.trim() : ''
  if (!website || /[\s\\\u0000-\u001f\u007f]/u.test(website)) return null
  const explicit = WEB_SCHEME.test(website)
  const authority = website.replace(WEB_SCHEME, '').split(/[/?#]/, 1)[0]
  if (!authority || authority.includes('@')) return null
  const candidate = explicit ? website : 'https://' + website
  try {
    const parsed = new URL(candidate)
    if (!parsed.hostname || parsed.username || parsed.password) return null
    if (!DNS_NAME.test(parsed.hostname)) return null
    return candidate
  } catch {
    return null
  }
}
