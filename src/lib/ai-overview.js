// Models & services › AI (v2.16.0, Platform Admin 13 Nov 2026 19:14 to 19:36): what the page derives from public.admin_ai_overview_v1().
// Kept apart from the screen so the Settings screens can ask one question of it (which settings now live on Models & services) and so the
// rules that must never fail quietly (no blank model, unknown is never 0) are in one place. Nothing here is an operational value: the family
// and area orders are the display order the Platform Admin gave.
import { supabase } from './supabase'

// Platform Admin 13 Nov 2026 19:14: "Model classified that can be used - Qwen3, Mimo, mistral small, Kimi K2, Gemini, LLama, deepseek"
export const FAMILIES = [
  ['qwen3', 'Qwen3'], ['mimo', 'MiMo'], ['mistral_small', 'Mistral Small'], ['kimi_k2', 'Kimi K2'],
  ['gemini', 'Gemini'], ['llama', 'Llama'], ['deepseek', 'DeepSeek'],
]
export const NOT_ALLOWED_GROUP = 'Not allowed'
const FAMILY_KEYS = new Set(FAMILIES.map(f => f[0]))
export const inAllowedFamily = m => FAMILY_KEYS.has(String(m?.family || '').toLowerCase())

/** Models in the Platform Admin's family order; everything outside the seven families (GPT, Claude, anything else) is the last group. */
export function modelGroups(models = []) {
  const groups = FAMILIES.map(([key, label]) => ({ key, label, models: models.filter(m => String(m.family || '').toLowerCase() === key) }))
  const rest = models.filter(m => !inAllowedFamily(m))
  return [...groups.filter(g => g.models.length), ...(rest.length ? [{ key: 'not_allowed', label: NOT_ALLOWED_GROUP, models: rest }] : [])]
}

// The areas the services are listed under, in the order asked for. The server names an area in its own words ("Course fields", "Central
// pages"); each is placed under the heading it belongs to. An area this list does not know keeps its own name and comes last.
export const AREAS = ['Courses', 'Entry requirements', 'Providers', 'Scholarships', 'Fees', 'Matching and identity', 'Operations']
const AREA_OF = [
  [/^course (field|description)|^courses?$/i, 'Courses'], [/^entry/i, 'Entry requirements'], [/^provider|^central/i, 'Providers'],
  [/^scholarship/i, 'Scholarships'], [/^fee/i, 'Fees'], [/match|identity|^course page/i, 'Matching and identity'], [/^operation|^adapter|^platform/i, 'Operations'],
]
export const areaOf = s => { const a = String(s?.area || '').trim(); return (AREA_OF.find(([re]) => re.test(a)) || [])[1] || a || 'Other' }
export function serviceGroups(services = []) {
  const names = [...AREAS]
  for (const s of services) if (!names.includes(areaOf(s))) names.push(areaOf(s))
  return names.map(area => ({ area, services: services.filter(s => areaOf(s) === area) })).filter(g => g.services.length)
}

/** "Qwen3 30B A3B Instruct (2507)" → "Qwen3 30B": the short name on a cascade chip. The full name stays on hover and in the Models pane. */
export function shortModel(label) {
  const words = String(label || '').replace(/\s*\([^)]*\)\s*/g, ' ').trim().split(/\s+/).filter(Boolean)
  while (words.length > 2 && /^(A\d+B|Instruct|\d+B)$/i.test(words[words.length - 1])) words.pop()
  return words.join(' ')
}
export const usd = (v, digits = 2) => (v == null || !Number.isFinite(Number(v)) ? null : `US$${Number(v).toFixed(digits)}`)
export const tokens = n => { const v = Number(n); if (!Number.isFinite(v) || v <= 0) return null; return v >= 1e6 ? `${(v / 1e6).toFixed(v % 1e6 ? 2 : 0)}M` : v >= 1000 ? `${Math.round(v / 1000)}K` : String(v) }

/** The cascade as the page draws it: every saved code, in order, with its name and whether it may be used. Never empty-handed: [] means no model. */
export function cascadeOf(service, models = []) {
  const byCode = Object.fromEntries(models.map(m => [m.code, m]))
  const detail = Object.fromEntries((service?.cascade_detail || []).map(d => [d.code, d]))
  return (service?.cascade || []).map(code => {
    const d = detail[code] || {}, m = byCode[code] || {}
    return { code, label: d.label || m.label || code, model_identifier: d.model_identifier || m.model_identifier || null, allowed: (d.status || m.status) === 'allowed', known: Boolean(detail[code] || byCode[code]) }
  })
}

/** One state for a service row. Off beats everything; then no allowed model; then a limit (the day's ceiling or the service's own cap). */
export function serviceState(s, openrouter = {}) {
  const allowed = (s?.models || []).length
  if (s?.enabled === false) return { key: 'off', label: 'Off', tone: 'neutral', why: s.held_reason || 'Switched off.' }
  if (!allowed) return { key: 'no_model', label: 'No allowed model', tone: 'danger', why: s?.held_reason || 'No model in its cascade is allowed.' }
  if (s?.held && s.held_kind === 'limit') {
    const ceiling = Number(openrouter.daily_ceiling_usd), spent = Number(openrouter.spent_today_usd)
    const atCeiling = /ceiling/i.test(String(s.held_reason || '')) || (ceiling > 0 && spent >= ceiling)
    return atCeiling ? { key: 'ceiling', label: 'Held: ceiling', tone: 'warning', why: s.held_reason || 'Today\'s spend ceiling is reached.' }
      : { key: 'cap', label: 'Held: cap reached', tone: 'warning', why: s.held_reason || 'Its daily cap is reached.' }
  }
  if (s?.held) return { key: 'off', label: 'Off', tone: 'neutral', why: s.held_reason || 'Held.' }
  return { key: 'running', label: 'Running', tone: 'success', why: '' }
}

/** The one line for the OpenRouter pane. */
export function accountState(or = {}) {
  const bal = or.balance_usd == null ? null : Number(or.balance_usd), floor = Number(or.floor_usd || 0), warn = Number(or.low_warn_usd || 0)
  const ceiling = Number(or.daily_ceiling_usd || 0), spent = Number(or.spent_today_usd || 0)
  if (!or.key_present) return { key: 'no_key', label: 'No key seen', tone: 'danger', text: 'No balance has been read with the key lately. Replace or verify the key below.' }
  if (bal != null && bal <= floor) return { key: 'no_credit', label: 'No credit', tone: 'danger', text: 'The balance is at or below the credit floor. Top up the OpenRouter account.' }
  if (ceiling > 0 && spent >= ceiling) return { key: 'ceiling', label: 'Held: today\'s ceiling reached', tone: 'warning', text: 'Every service is held until the UTC day changes, or until the ceiling is raised. Work an operator asked for under an open request is not held.' }
  if (bal != null && warn > 0 && bal < warn) return { key: 'low', label: 'Low credit', tone: 'warning', text: 'The balance is below the low-balance warning. Top up soon.' }
  if (bal == null) return { key: 'unread', label: 'Balance not read', tone: 'warning', text: 'The balance has not been read yet.' }
  return { key: 'running', label: 'Running', tone: 'success', text: 'Credit is above the floor and today\'s spend is under the ceiling.' }
}

// ---- usage -------------------------------------------------------------------------------------------------------------------------------
const sum = (rows, k) => { const known = rows.filter(r => r[k] != null); return known.length ? known.reduce((n, r) => n + Number(r[k] || 0), 0) : null }
/** Rows grouped by service or model. A null figure stays null (Not measured), never 0. */
export function usageBy(rows, by, { services = [], models = [] } = {}) {
  if (!Array.isArray(rows)) return null
  const sLabel = Object.fromEntries(services.map(s => [s.service_code, s.label])), mLabel = Object.fromEntries(models.map(m => [m.model_identifier, m.label]))
  const keyOf = r => (by === 'model' ? (r.model ?? '') : (r.service_code ?? ''))
  const keys = [...new Set(rows.map(keyOf))]
  return keys.map(k => {
    const mine = rows.filter(r => keyOf(r) === k)
    const label = by === 'model' ? (k ? (mLabel[k] || k) : 'Model not recorded') : (sLabel[k] || k || 'Service not recorded')
    return { key: k || '(none)', label, sub: by === 'model' && k && mLabel[k] ? k : '', usd: sum(mine, 'usd'), calls: sum(mine, 'calls') }
  }).sort((a, b) => (b.usd ?? -1) - (a.usd ?? -1))
}
/** One total per hour (24) or day (14), oldest first; a bucket with no row is "nothing recorded" (null), not a measured zero. */
export function usageBuckets(rows, unit, now = Date.now()) {
  if (!Array.isArray(rows)) return null
  const n = unit === 'hour' ? 24 : 14, step = unit === 'hour' ? 3600e3 : 86400e3, out = []
  const floor = t => Math.floor(t / step) * step
  const tOf = r => floor(new Date(unit === 'hour' ? r.hour : `${String(r.day).slice(0, 10)}T00:00:00Z`).getTime())
  const latest = Math.max(floor(now), ...rows.map(tOf).filter(Number.isFinite))
  for (let i = n - 1; i >= 0; i--) {
    const t = latest - i * step, mine = rows.filter(r => tOf(r) === t)
    out.push({ t, iso: new Date(t).toISOString(), usd: mine.length ? sum(mine, 'usd') : null, calls: mine.length ? sum(mine, 'calls') : null, recorded: mine.length > 0 })
  }
  return out
}

// ---- which settings now live on Models & services ------------------------------------------------------------------------------------------
// A setting marked home = 'models_services' (pipeline.platform_toolset_settings.home, migration 20261113380000) is shown and changed on
// Models & services only. The settings reads may not carry `home` yet, so the keys the overview lists under OpenRouter and under each service
// count too. If the overview cannot be read, nothing is hidden.
export function aiHomeKeys(overview) {
  const out = new Set()
  if (!overview || typeof overview !== 'object' || Array.isArray(overview)) return out
  const add = s => { if (s?.key) out.add(`${s.toolset || 'pipeline'}.${s.key}`) }
  for (const s of overview.openrouter?.settings || []) add(s)
  for (const svc of overview.services || []) for (const s of svc.settings || []) add(s)
  return out
}
export const isAiHome = (s, toolset, keys) => s?.home === 'models_services' || Boolean(keys?.has(`${toolset || s?.toolset || 'pipeline'}.${s?.key}`))
let pending = null
/** The keys, read once per page load (and again after `fresh`). Never throws. */
export function loadAiHomeKeys(fresh = false) {
  if (!pending || fresh) pending = supabase.rpc('admin_ai_overview_v1').then(({ data, error }) => (error ? new Set() : aiHomeKeys(data))).catch(() => new Set())
  return pending
}

// The contract's refusals, said plainly. Anything else goes through the app's one plain reading (lib/errors).
const REFUSALS = [
  [/give a reason/i, 'Give a reason of at least 4 characters. It is kept in the log.'],
  [/cascade is empty/i, 'The cascade is empty: name at least one allowed model.'],
  [/4 models at most/i, 'A cascade holds 4 models at most.'],
  [/names a model twice/i, 'The cascade names a model twice.'],
  [/unknown model in the cascade: ?(.*)/i, (m) => `Not a model in the list: ${m[1]}.`],
  [/not an allowed model: ?([^()]*)/i, (m) => `Not an allowed model: ${m[1].trim()}. Allow it in Models first, or remove it.`],
  [/give a daily US\$ cap/i, 'Give a daily US$ cap: every service has one.'],
  [/cap cannot be negative/i, 'A cap cannot be negative. Leave it empty for no cap.'],
  [/status must be/i, 'A model is either allowed or not allowed.'],
  [/(PIM Operator|Pipeline Operator) role or above required/i, (m) => `${m[1]} role or above is needed for this.`],
]
export function refusal(e) {
  const text = String(e?.message || e || '')
  for (const [re, say] of REFUSALS) { const m = text.match(re); if (m) return typeof say === 'function' ? say(m) : say }
  return null
}
