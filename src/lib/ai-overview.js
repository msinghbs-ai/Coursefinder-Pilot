// Models & services › AI (v2.16.0, Platform Admin 13 Nov 2026 19:14 to 19:36): what the page derives from public.admin_ai_overview_v1().
// Kept apart from the screen so the Settings screens can ask one question of it (which settings now live on Models & services) and so the
// rules that must never fail quietly (no blank model, unknown is never 0) are in one place. Nothing here is an operational value: the family
// and area orders are the display order the Platform Admin gave.

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

// The areas the services are listed under, in the order asked for. The server names each area in these words; an area this list does not
// know keeps its own name and comes last.
export const AREAS = ['Courses', 'Entry requirements', 'Providers', 'Scholarships', 'Fees', 'Matching and identity', 'Operations']
export const areaOf = s => String(s?.area || '').trim() || 'Other'
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

// One state for a service row, from the server's own held_kind (cap, ceiling, credit_floor, off, no_model or null). Nothing is inferred.
const STATES = {
  off: ['Off', 'neutral', 'Switched off.'], no_model: ['No allowed model', 'danger', 'No model in its cascade is allowed.'],
  cap: ['Held: cap reached', 'warning', 'Its daily cap is reached.'], ceiling: ['Held: ceiling', 'warning', 'Today\'s spend ceiling for all AI is reached.'],
  credit_floor: ['Held: no credit', 'danger', 'The OpenRouter balance is at or below the credit floor. All AI work is stopped, including Run now.'],
}
export function serviceState(s) {
  // a row with no allowed model is never shown as running, whatever else the answer says
  const key = s?.held_kind && STATES[s.held_kind] ? s.held_kind : s?.enabled === false ? 'off' : !(s?.models || []).length ? 'no_model' : s?.held ? 'held' : 'running'
  if (key === 'running') return { key, label: 'Running', tone: 'success', why: '' }
  if (key === 'held') return { key, label: 'Held', tone: 'warning', why: s.held_reason || 'Held.' }
  const [label, tone, why] = STATES[key], said = s?.held_reason && s.held_reason !== key ? s.held_reason : why
  return { key, label, tone, why: said + (s?.on_demand_exempt ? ' Work asked for under an open request is still let through.' : '') }
}

/** The one line for the OpenRouter pane. */
export function accountState(or = {}) {
  const bal = or.balance_usd == null ? null : Number(or.balance_usd), floor = Number(or.floor_usd || 0), warn = Number(or.low_warn_usd || 0)
  const ceiling = Number(or.daily_ceiling_usd || 0), spent = Number(or.spent_today_usd || 0)
  if (!or.key_present) return { key: 'no_key', label: 'No key seen', tone: 'danger', text: 'No balance has been read with the key lately. Replace or verify the key below.' }
  if (or.balance_known === false) return { key: 'unread', label: 'Balance not measured', tone: 'warning', text: or.balance_note || 'There is no balance reading, so the credit floor holds nothing. Check the key and the job that reads the balance.' }
  if (bal != null && bal <= floor) return { key: 'no_credit', label: 'No credit', tone: 'danger', text: 'The balance is at or below the credit floor. All AI work is stopped, including Run now. Top up the OpenRouter account.' }
  if (ceiling > 0 && spent >= ceiling) return { key: 'ceiling', label: 'Held: today\'s ceiling reached', tone: 'warning', text: 'Every service is held until the UTC day changes, or until the ceiling is raised. Work an operator asked for under an open request is not held.' }
  if (bal != null && warn > 0 && bal < warn) return { key: 'low', label: 'Low credit', tone: 'warning', text: 'The balance is below the low-balance warning. Top up soon.' }
  if (bal == null) return { key: 'unread', label: 'Balance not measured', tone: 'warning', text: 'The balance has not been read yet.' }
  return { key: 'running', label: 'Running', tone: 'success', text: 'Credit is above the floor and today\'s spend is under the ceiling.' }
}

// ---- what the worker really does with a service (Platform Admin written review 13 Nov 2026 22:10: "Do not display a model cascade as
// operational unless the worker actually executes it") ---------------------------------------------------------------------------------
// migration_state: routed (the worker runs the cascade), routed_single (it uses one model: no fallback yet), not_migrated (its reader does
// not ask the route). A row that does not say is read from the older keys: enforced false is not_migrated, otherwise routed.
export const migrationOf = s => (['routed', 'routed_single', 'not_migrated'].includes(s?.migration_state) ? s.migration_state : s?.enforced === false || s?.wired === false ? 'not_migrated' : 'routed')
/** Qualification of models for one service: Map(code → { qualified, evidence, at, by }), or null when the service carries no qualification data. */
export function qualification(s) {
  const q = s?.qualification ?? s?.qualified_models ?? s?.qualified
  if (q == null) return null
  const out = new Map(), put = (code, v) => { if (code) out.set(code, typeof v === 'object' && v ? { qualified: v.qualified ?? (v.status ? v.status === 'qualified' : true), evidence: v.evidence ?? null, at: v.at ?? v.qualified_at ?? null, by: v.by ?? v.qualified_by ?? null } : { qualified: v !== false, evidence: null, at: null, by: null }) }
  if (Array.isArray(q)) for (const x of q) (typeof x === 'string' ? put(x, true) : put(x?.code ?? x?.model_code, x))
  else if (typeof q === 'object') for (const [code, v] of Object.entries(q)) put(code, v)
  return out
}
/** true or false when the service says; null when it carries no qualification data (the server then decides). */
export const isQualified = (s, code) => { const q = qualification(s); return q == null ? null : Boolean(q.get(code)?.qualified) }
/** The most recent call of a service, however the answer names it; null when it gives none (shown as Not measured). */
export function lastCall(s) {
  const l = s?.last_call ?? s?.last ?? null
  if (!l || typeof l !== 'object') return null
  return { at: l.at ?? l.called_at ?? null, model: l.model ?? l.model_identifier ?? null, outcome: l.outcome ?? l.status ?? null, error: l.error ?? l.error_message ?? null }
}
export const recoveryOf = s => s?.recovery_state ?? s?.recovery ?? null

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
    const tok = mine.map(r => (r.tokens != null ? Number(r.tokens) : r.tokens_in != null || r.tokens_out != null ? Number(r.tokens_in || 0) + Number(r.tokens_out || 0) : null)).filter(v => v != null)
    const evidence = mine.map(r => r.evidence_href ?? r.evidence_url ?? r.evidence ?? null).find(v => typeof v === 'string' && /^(#|https:\/\/)/.test(v)) || null
    return { key: k || '(none)', label, sub: by === 'model' && k && mLabel[k] ? k : '', usd: sum(mine, 'usd'), calls: sum(mine, 'calls'), tokens: tok.length ? tok.reduce((a, b) => a + b, 0) : null, failures: sum(mine, 'failures'), fallbacks: sum(mine, 'fallbacks'), evidence }
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
// A setting marked home = 'models_services' (pipeline.platform_toolset_settings.home; the settings reads return it) is shown and changed on
// Models & services only.
export const isAiHome = s => s?.home === 'models_services'

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
  [/not in a family the Platform Admin allows/i, 'This model is not in a family the Platform Admin allows (Qwen3, MiMo, Mistral Small, Kimi K2, Gemini, Llama, DeepSeek). Adding a family is a release.'],
  [/not qualified for this service: ?(.*)/i, (m) => `Not qualified for this service: ${m[1]}. Record its qualification first.`],
  [/Platform Admin required/i, 'Platform Admin is needed for this.'],
  [/status must be/i, 'A model is either allowed or not allowed.'],
  [/(PIM Operator|Pipeline Operator) role or above required/i, (m) => `${m[1]} role or above is needed for this.`],
]
export function refusal(e) {
  const text = String(e?.message || e || '')
  for (const [re, say] of REFUSALS) { const m = text.match(re); if (m) return typeof say === 'function' ? say(m) : say }
  return null
}
