// Mocked public.admin_ai_overview_v1() for local admin UAT, in the shape of docs/platform/AI-MODELS-SERVICES-CONTRACT.md (round 4: rank 3 reads;
// the cap and the ceiling follow the mode (observe: reported through would_hold_*; stop: held); off, no model, no qualified model, a balance
// that is unknown or stale and the credit floor always hold; qualification, migration_state, previous_model, last_call, recovery_state,
// usage.by_model_24h and fallbacks_24h, prompt text_ref and sha256, and config on scholarship_extraction are as the contract names them). Models and services follow the migration's seed; a few rows are bent on purpose so the screen's hard cases are on show:
//   entry_matrices           its cascade names only GPT-4.1 mini (not allowed) → no allowed model, model_in_effect null
//   fee_reader               held at its own daily cap
//   entry_requirements_v2_shadow  switched off
//   course_matching          spend not measured (null)
//   mimo-v2.6-flash          price and context not checked (null)
//   migration_state         as the contract lists it: routed_single for provider_description, ops_diagnosis, adapter_builder and
//                           scholarship_eligibility; not_migrated for page_identity; entry_matrices is kept routed here so a cascade can be edited
//   The fixture's mode is stop (limits enforced) unless a test passes mode: 'observe'.
// aiState() answers the two writes the way the server does (same refusals, same recomputed fields). Nothing reaches a real backend.
const NOW = Date.now(), H = 3600e3, D = 86400e3
const iso = t => new Date(t).toISOString()
const hourStart = Math.floor(NOW / H) * H, dayStart = Math.floor(NOW / D) * D

const M = (code, family, label, model_identifier, i, o, ctx, status = 'allowed', note = '') => ({ code, family, label, model_identifier, input_usd_per_mtok: i, output_usd_per_mtok: o,
  price_checked_at: i == null ? null : iso(NOW - 2 * H), context_tokens: ctx, status, note, reason: status === 'allowed' ? 'seed 13 Nov 2026' : 'Platform Admin 13 Nov 2026 19:14', changed_at: iso(NOW - 2 * H), used_by: [] })
const SINGLE = ['ops_diagnosis', 'scholarship_eligibility', 'provider_description', 'adapter_builder']
const PROVISIONAL = ['fee_reader', 'calendar_reading', 'central_english_policy', 'scholarship_extraction', 'scholarship_eligibility', 'provider_description']
const QUALIFIED = ['qwen3-30b', 'mistral-small-3.2', 'deepseek-v3.2']
export const models = () => [
  M('qwen3-30b', 'qwen3', 'Qwen3 30B A3B Instruct (2507)', 'qwen/qwen3-30b-a3b-instruct-2507', 0.10, 0.30, 262144, 'allowed', 'In use: course fields, central pages, fees, scholarships, course-page matching, adapter proposals'),
  M('qwen3-235b', 'qwen3', 'Qwen3 235B A22B (2507)', 'qwen/qwen3-235b-a22b-2507', 0.14, 0.80, 262144),
  M('mimo-v2.6-pro', 'mimo', 'MiMo v2.6 Pro', 'xiaomi/mimo-v2.6-pro', 0.435, 0.87, 1050000),
  M('mimo-v2.6-flash', 'mimo', 'MiMo v2.6 Flash', 'xiaomi/mimo-v2.6-flash', null, null, null, 'allowed', 'Not used yet; not qualified on any platform prompt'),
  M('mistral-small-3.2', 'mistral_small', 'Mistral Small 3.2 24B', 'mistralai/mistral-small-3.2-24b-instruct', 0.10, 0.30, 256000, 'allowed', 'Second in the cascades that were on GPT-4.1 mini'),
  M('kimi-k2-0905', 'kimi_k2', 'Kimi K2 (0905)', 'moonshotai/kimi-k2-0905', 0.60, 2.50, 262144, 'allowed', 'Costs more than GPT-4.1 mini per token'),
  M('gemini-2.5-flash-lite', 'gemini', 'Gemini 2.5 Flash Lite', 'google/gemini-2.5-flash-lite', 0.10, 0.40, 1048576),
  M('gemini-2.5-flash', 'gemini', 'Gemini 2.5 Flash', 'google/gemini-2.5-flash', 0.30, 2.50, 1048576),
  M('llama-4-maverick', 'llama', 'Llama 4 Maverick', 'meta-llama/llama-4-maverick', 0.35, 1.00, 524288),
  M('llama-4-scout', 'llama', 'Llama 4 Scout', 'meta-llama/llama-4-scout', 0.10, 0.30, 1310720),
  M('deepseek-v3.2', 'deepseek', 'DeepSeek V3.2', 'deepseek/deepseek-v3.2', 0.26, 0.38, 163840),
  M('deepseek-v4-flash', 'deepseek', 'DeepSeek V4 Flash', 'deepseek/deepseek-v4-flash', 0.09, 0.18, 1048576),
  M('gpt-4.1-mini', 'other', 'GPT-4.1 mini', 'openai/gpt-4.1-mini', 0.40, 1.60, 1047576, 'not_allowed', 'Platform Admin 13 Nov 2026 19:14: too expensive, it exhausted the AI credit. Kept so history resolves'),
  M('gpt-4.1', 'other', 'GPT-4.1', 'openai/gpt-4.1', 2.00, 8.00, 1047576, 'not_allowed', 'Not in the families the Platform Admin allows. Kept so history resolves'),
  M('claude-haiku-4.5', 'other', 'Claude Haiku 4.5', 'anthropic/claude-haiku-4.5', 1.00, 5.00, 200000, 'not_allowed', 'Not in the families the Platform Admin allows. Kept so history resolves'),
]

const num = (toolset, key, label, value, min, max, unit, help = null) => ({ toolset, key, label, help, value, kind: 'number', min, max, unit })
const txt = (toolset, key, label, value, help = null, gone = false) => ({ toolset, key, label, help, value, kind: 'text', min: null, max: null, unit: null, not_read: gone, read_only: gone })
const S = (service_code, label, area, o = {}) => ({ service_code, label, area, field: null, lane: 'central_ai', ledger_match: null, cascade: ['qwen3-30b'], daily_usd_cap: 2, daily_calls_cap: null, enabled: true,
  spent_today: { usd: 0, calls: 0 }, resolver: 'route', prompt: { source: 'worker code', version: `${service_code}-v1`, text: null }, settings: [], note: null, reason: 'seed 13 Nov 2026 (Platform Admin 19:14)',
  changed_at: iso(NOW - 2 * H), changed_by: null, ...o })
export const services = () => [
  S('course_description', 'Course description', 'Courses', { field: 'course_description', lane: 'enrich_fields', spent_today: { usd: 1.1, calls: 2 }, prompt: { source: 'worker code', version: 'cdesc-source-grounded-v1', text: null },
    settings: [num('pipeline', 'enrich.course_text_items_per_day', 'Course descriptions: items a day', 400, 0, 5000, 'items'), num('pipeline', 'reading.answer_tokens.course_text', 'Course description: answer tokens', 900, 100, 4000, 'tokens')] }),
  S('course_entry_requirements', 'Course entry requirements', 'Courses', { field: 'course_entry_requirements', lane: 'enrich_fields', cascade: ['deepseek-v3.2', 'qwen3-30b'], daily_usd_cap: 3, daily_calls_cap: 500, spent_today: { usd: 0.301, calls: 2 },
    prompt: { source: 'worker code', version: 'course-entry-v1', text: null }, note: 'Was GPT-4.1 mini (setting entry.matrix_model). qwen3-30b has not been qualified on this prompt.', reason: 'fixture: cheaper first', changed_by: 'admin@example.test',
    settings: [num('pipeline', 'entry.course_page_chars', 'Course entry requirements: page characters', 100000, 1000, 400000, 'characters')] }),
  S('course_other_fields', 'Other course fields (deadline, intakes, duration, campus, delivery, English)', 'Courses', { field: 'course_other_fields', lane: 'enrich_fields', spent_today: { usd: 0.2, calls: 1 },
    prompt: { source: 'worker code', version: 'course-fields-v1 (deadline: course-text-v2)', text: null },
    settings: [num('pipeline', 'enrich.ai_calls_at_once', 'AI calls at once', 4, 1, 20, 'calls'), num('pipeline', 'enrich.ai_items_per_call', 'Items a call', 6, 1, 20, 'items')] }),
  S('entry_matrices', 'Entry requirement matrices (provider pages)', 'Entry requirements', { lane: 'entry_matrix', cascade: ['gpt-4.1-mini'], daily_usd_cap: 4, prompt: { source: 'worker code', version: 'entry-matrix-v0.1.4', text: null },
    note: 'Was GPT-4.1 mini (setting entry.matrix_model).', settings: [txt('pipeline', 'entry.matrix_model', 'Entry matrices: model', 'openai/gpt-4.1-mini', null, true), num('pipeline', 'entry.matrix_slice_chars', 'Entry matrices: slice characters', 24000, 2000, 100000, 'characters')] }),
  S('entry_requirements_v2_shadow', 'Entry requirements v2 (shadow trial)', 'Entry requirements', { lane: 'entry_matrix', cascade: ['qwen3-30b', 'mistral-small-3.2'], daily_usd_cap: 2, enabled: false, resolver: 'pipeline.aer_prompt_versions',
    prompt: { source: 'pipeline.aer_prompt_versions', version: 'aer-v2-course-v1', text: 'You read one course page and return its academic entry requirements by country of prior education. Quote the page for every fact.' },
    note: 'The model is pinned on the prompt version. The trial is switched off (aer.v2_shadow_on).' }),
  S('provider_description', 'Provider description', 'Providers', { lane: 'provider_description', cascade: ['qwen3-30b'], daily_usd_cap: 1, prompt: { source: 'pipeline.provider_description_prompts', version: '4', text: 'You write a provider description from its official About page. Every sentence is supported by a passage on the page.' }, reason: 'old card' }),
  S('calendar_reading', 'Intake calendars (central pages)', 'Providers', { cascade: ['qwen3-30b', 'mistral-small-3.2'], daily_usd_cap: 2, spent_today: { usd: 0.4, calls: 6 }, prompt: { source: 'worker code', version: 'calendar-v2.4', text: null },
    settings: [num('pipeline', 'reading.calendar_max_slices', 'Calendar: slices a page', 6, 1, 20, 'slices')] }),
  S('central_english_policy', 'English policy pages (central pages)', 'Providers', { cascade: ['qwen3-30b', 'mistral-small-3.2'], prompt: { source: 'worker code', version: 'provider-policy-v0.3.1', text: null } }),
  S('scholarship_extraction', 'Scholarship pages', 'Scholarships', { lane: 'scholarship_ai', cascade: ['qwen3-30b', 'mistral-small-3.2'], daily_usd_cap: 6, spent_today: { usd: 2.2, calls: 140 }, resolver: 'pipeline.scholarship_ai_extract_settings',
    prompt: { source: 'pipeline.scholarship_ai_prompts', version: '7', text: 'You read one scholarship page. Answer with the scholarship\'s facts; every fact quotes the page.' }, note: 'The cascade is the reading order: an unproven fact goes to the next model, then to a person.',
    config: { write: 'public.admin_scholarship_ai', ai_admission: false, prompts: [{ version: '7', text: 'You read one scholarship page. Answer with the scholarship\'s facts; every fact quotes the page.', sha256: 'a3f1c0de5b7e4d2f9a8b6c1d0e3f5a7b9c2d4e6f8a1b3c5d7e9f0a2b4c6d8e0f', current: true }, { version: '6', text: 'You read one scholarship page and list its facts.', sha256: 'b4e2d1cf6a8f5e3d0b9c7d2e1f4a6b8c0d3e5f7a9b2c4d6e8f1a3b5c7d9e1f20', current: false }] } }),
  S('scholarship_eligibility', 'Scholarship eligibility', 'Scholarships', { lane: 'scholarship_ai', prompt: { source: 'worker code', version: 'eligibility.ts', text: null }, note: 'Uses the first model of the scholarship chain.' }),
  S('fee_reader', 'Fees', 'Fees', { lane: 'fee_ai', cascade: ['qwen3-30b', 'mistral-small-3.2'], daily_usd_cap: 5, spent_today: { usd: 5.02, calls: 310 }, last_call: { at: iso(NOW - 50 * 60e3), model: 'mistralai/mistral-small-3.2-24b-instruct', outcome: 'failed', error: 'timeout', attempt_no: 2 }, prompt: { source: 'worker code', version: 'fees.ts', text: null } }),
  S('course_matching', 'Course-page matching', 'Matching and identity', { lane: 'course_match', daily_usd_cap: 2, spent_today: { usd: null, calls: null }, prompt: { source: 'worker code', version: 'ai-match-v0.10.0', text: null }, note: null }),
  S('page_identity', 'Page identity (qualification only)', 'Matching and identity', { lane: 'page_identity', daily_usd_cap: 1, prompt: { source: 'worker code', version: 'page-identity-v1', text: null }, note: 'No scheduled reader: used for qualification only.' }),
  S('adapter_builder', 'Adapter proposals', 'Operations', { lane: 'adapter_builder', prompt: { source: 'worker code', version: 'builder-v3', text: null }, note: 'First model only; a provider\'s own model is used only when the cascade names it.',
    settings: [txt('firecrawl', 'builder_model', 'Adapter proposals: model', 'qwen/qwen3-30b-a3b-instruct-2507', 'Kept with its value; replaced by the route.', true), num('firecrawl', 'builder_proposals_per_day', 'Adapter proposals a day', 40, 0, 500, 'proposals')] }),
  S('ops_diagnosis', 'Operations diagnosis', 'Operations', { lane: 'ops_diagnosis', cascade: ['qwen3-30b'], daily_usd_cap: 1, spent_today: { usd: 0.05, calls: 3 }, prompt: { source: 'worker code', version: 'ops-diagnosis-v1', text: null },
    settings: [txt('pipeline', 'har.ai_escalation_model', 'Health repair: escalation model', 'qwen/qwen3-235b-a22b-2507', 'The model asked when the first diagnosis is not sure.'), txt('pipeline', 'ops.ai_diagnosis_model', 'Operations diagnosis: model', 'openai/gpt-4.1-mini', null, true)] }),
]

const usage = () => {
  const row = (t, unit, service_code, lane, model, usd, calls) => ({ [unit]: unit === 'day' ? iso(t).slice(0, 10) : iso(t), service_code, lane, model, usd, calls })
  const Q = 'qwen/qwen3-30b-a3b-instruct-2507', G = 'openai/gpt-4.1-mini', DS = 'deepseek/deepseek-v3.2'
  const by_hour_24h = [], by_day_14d = []
  for (const [h, svc, lane, model, usd, calls] of [[0, 'scholarship_extraction', 'scholarship_ai', Q, 0.4, 26], [0, 'fee_reader', 'fee_ai', Q, 0.9, 55], [1, 'fee_reader', 'fee_ai', Q, 1.6, 98], [2, 'course_description', 'enrich_fields', Q, 0.9, 1],
    [2, 'course_entry_requirements', 'enrich_fields', DS, 0.301, 2], [3, 'scholarship_extraction', 'scholarship_ai', Q, 1.8, 114], [5, 'fee_reader', 'fee_ai', Q, 2.52, 157], [6, 'calendar_reading', 'central_ai', Q, 0.4, 6],
    [9, 'course_other_fields', 'enrich_fields', null, 0.2, 1], [14, 'entry_matrices', 'entry_matrix', G, 6.4, 22], [15, 'entry_matrices', 'entry_matrix', G, 9.1, 31], [20, 'ops_diagnosis', 'ops_diagnosis', Q, 0.05, 3]]) by_hour_24h.push(row(hourStart - h * H, 'hour', svc, lane, model, usd, calls))
  const days = [[0, 9.27, 471], [1, 21.4, 240], [2, 18.9, 205], [3, 16.2, 190], [4, 6.1, 320], [5, 5.4, 300], [7, 4.9, 280], [8, 3.2, 150], [10, 2.8, 140], [12, 1.9, 90]]
  for (const [d, usd, calls] of days) {
    by_day_14d.push(row(dayStart - d * D, 'day', 'fee_reader', 'fee_ai', d === 0 ? Q : null, +(usd * 0.5).toFixed(2), Math.round(calls * 0.6)))
    by_day_14d.push(row(dayStart - d * D, 'day', d >= 1 && d <= 3 ? 'entry_matrices' : 'scholarship_extraction', d >= 1 && d <= 3 ? 'entry_matrix' : 'scholarship_ai', d >= 1 && d <= 3 ? G : d === 0 ? Q : null, +(usd * 0.5).toFixed(2), Math.round(calls * 0.4)))
  }
  const M2 = 'mistralai/mistral-small-3.2-24b-instruct'
  const by_model_24h = [
    { service_code: 'fee_reader', model: Q, attempts: 310, answered: 304, failures: 6, fallbacks: 0, tokens_in: 1302000, tokens_out: 117800, usd: 4.9, evidence_href: null },
    { service_code: 'fee_reader', model: M2, attempts: 6, answered: 5, failures: 1, fallbacks: 6, tokens_in: 25200, tokens_out: 2280, usd: 0.12, evidence_href: null },
    { service_code: 'scholarship_extraction', model: Q, attempts: 140, answered: 140, failures: 0, fallbacks: 0, tokens_in: 588000, tokens_out: 53200, usd: 2.2, evidence_href: null },
    { service_code: 'course_description', model: Q, attempts: 2, answered: 2, failures: 0, fallbacks: 0, tokens_in: null, tokens_out: null, usd: 1.1, evidence_href: null },
  ]
  const fallbacks_24h = [{ at: iso(NOW - 50 * 60e3), service_code: 'fee_reader', model: M2, attempt_no: 2, failure_kind: 'timeout' }, { at: iso(NOW - 52 * 60e3), service_code: 'fee_reader', model: Q, attempt_no: 1, failure_kind: 'http' }]
  return { by_day_14d, by_hour_24h, by_model_24h, fallbacks_24h }
}

/** Recompute what the server derives: used_by, cascade_detail, models (allowed only), held, model_in_effect. */
export function derive(o) {
  const by = Object.fromEntries(o.models.map(m => [m.code, m]))
  for (const m of o.models) m.used_by = o.services.filter(s => s.cascade.includes(m.code)).map(s => s.service_code)
  const or = o.openrouter, ceiling = or.daily_ceiling_usd, atCeiling = ceiling > 0 && or.spent_today_usd >= ceiling
  o.mode = o.mode || or.mode || 'stop'; or.mode = o.mode
  const enforcing = o.mode === 'stop', ageMin = or.balance_observed_at ? (Date.now() - new Date(or.balance_observed_at).getTime()) / 60000 : null
  const balKind = or.balance_known === false || or.balance_usd == null ? 'balance_unknown' : ageMin != null && ageMin > or.balance_max_age_minutes ? 'balance_stale' : or.balance_usd <= or.floor_usd ? 'credit_floor' : null
  const REASON = { off: 'switched off', no_model: 'no allowed model in the cascade', no_qualified_model: 'no model in the cascade is qualified for this service', balance_unknown: 'there is no OpenRouter balance reading', balance_stale: 'the OpenRouter balance reading is older than 90 minutes', credit_floor: 'credit_floor', ceiling: 'the daily ceiling for all AI is reached', cap: 'its daily cap is reached' }
  for (const s of o.services) {
    s.migration_state = s.migration_state || (SINGLE.includes(s.service_code) ? 'routed_single' : s.service_code === 'page_identity' ? 'not_migrated' : 'routed')
    s.qualification = s.qualification || o.models.filter(m => QUALIFIED.includes(m.code) || s.cascade.includes(m.code)).map(m => ({ code: m.code, qualified: true, status: 'qualified', provisional: m.code === 'qwen3-30b' && PROVISIONAL.includes(s.service_code), prompt_version: s.prompt?.version || null, evidence: m.code === 'qwen3-30b' && PROVISIONAL.includes(s.service_code) ? 'Platform Admin 13 Nov 19:09: regression qualification pending' : 'qualification run on the sample', at: iso(NOW - 3 * H), by: null, note: null }))
    const q = c => s.qualification.find(x => x.code === c)?.status === 'qualified'
    s.cascade_detail = s.cascade.map(c => ({ code: c, label: by[c]?.label || c, model_identifier: by[c]?.model_identifier || null, status: by[c]?.status || 'not_allowed' }))
    s.skipped = s.cascade.filter(c => !by[c] || by[c].status !== 'allowed' || !q(c)).map(c => ({ code: c, why: !by[c] ? 'not in the list' : by[c].status !== 'allowed' ? 'not allowed' : 'not qualified for this service' }))
    const allowed = s.cascade_detail.filter(x => x.status === 'allowed')
    s.models = allowed.filter(x => q(x.code)).map(x => ({ code: x.code, model_identifier: x.model_identifier })).slice(0, s.migration_state === 'routed' ? 4 : 1)
    s.wired = true; s.enforced = true; s.enforcing = enforcing; s.resolver = 'route'; s.purpose_group = s.purpose_group || 'other'
    const overCap = Number(s.spent_today?.usd) >= s.daily_usd_cap || (s.daily_calls_cap != null && Number(s.spent_today?.calls) >= s.daily_calls_cap)
    const always = !s.enabled ? 'off' : !allowed.length ? 'no_model' : !s.models.length ? 'no_qualified_model' : balKind
    const limit = atCeiling ? 'ceiling' : overCap ? 'cap' : null
    const would = always || limit, kind = always || (enforcing ? limit : null)
    Object.assign(s, { held: Boolean(kind), held_kind: kind, held_reason: REASON[kind] || null, would_hold_now: Boolean(would), would_hold_kind: would, would_hold_reason: REASON[would] || null, on_demand_exempt: kind === 'cap' || kind === 'ceiling' })
    s.model = s.models[0]?.model_identifier || null; s.model_in_effect = s.model
    if (s.previous_model === undefined) s.previous_model = s.service_code === 'page_identity' ? null : ['course_description', 'course_other_fields', 'course_matching', 'adapter_builder'].includes(s.service_code) ? 'qwen/qwen3-30b-a3b-instruct-2507' : 'openai/gpt-4.1-mini'
    if (s.last_call === undefined) s.last_call = Number(s.spent_today?.calls) > 0 ? { at: iso(NOW - 20 * 60e3), model: s.model, outcome: 'answered', error: null, attempt_no: 1 } : null
    s.recovery_state = kind ? 'held' : !s.last_call ? 'no_calls' : s.last_call.outcome === 'failed' ? 'failing' : s.last_call.attempt_no > 1 ? 'fallback' : 'ok'
    if (s.prompt && s.prompt.text == null && !s.prompt.text_ref) Object.assign(s.prompt, { text_ref: `ai-prompts.json#${s.service_code}`, sha256: null })
    if (s.prompt && s.prompt.text != null && !s.prompt.sha256) s.prompt.sha256 = 'a3f1c0de5b7e4d2f9a8b6c1d0e3f5a7b9c2d4e6f8a1b3c5d7e9f0a2b4c6d8e0f'
  }
  o.ceiling_usd = ceiling; o.caps_total_usd = +o.services.filter(s => s.enabled).reduce((n, s) => n + Number(s.daily_usd_cap || 0), 0).toFixed(2); o.caps_exceed_ceiling = o.caps_total_usd > ceiling
  return o
}

export function aiOverview(over = {}) {
  const o = {
    can_control: true, can_admin: true, rank: 6, day_start: iso(dayStart),
    openrouter: { key_present: true, key_secret_name: 'OPENROUTER_API_KEY', key: { secret: 'OPENROUTER_API_KEY', profile_id: 'prof-1', profile_code: 'openrouter-shared', shared_by_profiles: 9 }, balance_known: true, balance_note: null, balance_max_age_minutes: 90, balance_usd: 53, balance_observed_at: iso(NOW - 9 * 60e3), total_credits_usd: 100, floor_usd: 0.5, low_warn_usd: 10, daily_ceiling_usd: 14, spent_today_usd: 9.27,
      settings: [num('openrouter', 'credit_floor_usd', 'Credit floor', 0.5, 0, 500, 'US$', 'AI stops when the balance is at or below this.'), num('openrouter', 'low_balance_warn_usd', 'Low-balance warning', 10, 0, 500, 'US$'),
        num('pipeline', 'budgets.ai_daily_ceiling_usd', 'Daily spend ceiling, all AI', 14, 0, 500, 'US$', 'Every service is held once the day\'s total reaches it.'), num('openrouter', 'balance_stale_minutes', 'Warn when the balance has not been read for', 30, 5, 1440, 'minutes')] },
    models: models(), services: services(),
    legacy_controls: { central_ai_settings: { enabled: true, calls_at_once: 3, model_code: 'qwen3-30b', model_identifier: 'qwen/qwen3-30b-a3b-instruct-2507', reason: 'copy of the intake calendar route (Models & services)', changed_at: iso(NOW - 2 * H), write: null, copy_of: 'route calendar_reading' },
      scholarship_chain: { chain: ['qwen3-30b', 'mistral-small-3.2'], reason: 'copy of the scholarship route (Models & services)', changed_at: iso(NOW - 2 * H), write: null, copy_of: 'route scholarship_extraction' } },
    legacy: { layer3: { note: 'Layer 3 was retired on 12 Oct 2026 and is not wired to the routes. A profile listed here is switched on in its own table.', last_call_at: '2026-10-11T21:55:27+00:00', jobs: [],
      profiles_switched_on: [{ code: 'openrouter-intake-l3c-qwen3-30b-a3b-2507-v1', model_identifier: 'qwen/qwen3-30b-a3b-instruct-2507', tasks: ['provider_intake_validation'], in_active_tier: true, catalogue_status: 'allowed' },
        { code: 'openrouter-intake-l3r-claude-haiku-4-5-v1', model_identifier: 'anthropic/claude-haiku-4.5', tasks: ['provider_intake_validation'], in_active_tier: false, catalogue_status: 'not_allowed' }] } },
    guard: 1,
    usage: usage(),
    events: [{ at: iso(NOW - 2 * H), action: 'route_set', target: 'course_entry_requirements', detail: { reason: 'fixture: cheaper first', before: { cascade: ['qwen3-30b', 'mistral-small-3.2'] }, after: { cascade: ['deepseek-v3.2', 'qwen3-30b'] } }, by: 'admin@example.test' },
      { at: iso(NOW - 3 * H), action: 'model_set', target: 'gpt-4.1-mini', detail: { reason: 'Platform Admin 13 Nov 2026 19:14' }, by: 'admin@example.test' }],
    ...over,
  }
  return derive(o)
}

/** A stateful stand-in for the three calls. write(name, body) answers { data } or { error } exactly as the contract words its refusals. */
export function aiState(over = {}, { rank = 6 } = {}) {
  let o = aiOverview(over); Object.assign(o, { rank, can_control: rank >= 5, can_admin: rank >= 6 })
  if (rank < 4) o.openrouter.key = { present: true }
  const need = { admin_ai_model_set_v1: 6, admin_ai_qualification_set_v1: 6, admin_ai_route_set_v1: 5 }
  const refuse = message => ({ error: { code: 'P0001', message } })
  return {
    get overview() { return o },
    write(name, b = {}) {
      if (name === 'admin_ai_overview_v1') return { data: o }
      if (rank < (need[name] || 5)) return { error: { code: '42501', message: need[name] === 6 ? 'Platform Admin required' : 'PIM Operator role or above required' } }
      if (String(b.p_reason || '').trim().length < 4) return refuse('give a reason (kept in the log)')
      if (name === 'admin_ai_model_set_v1') {
        const m = o.models.find(x => x.code === b.p_code)
        if (!m) return refuse(`model ${b.p_code} is not in the list`)
        if (!['allowed', 'not_allowed'].includes(b.p_status)) return refuse('status must be allowed or not_allowed')
        if (b.p_status === 'allowed' && m.family === 'other') return refuse('this model is not in a family the Platform Admin allows (Qwen3, MiMo, Mistral Small, Kimi K2, Gemini, Llama, DeepSeek); adding a family is a release')
        Object.assign(m, { status: b.p_status, reason: b.p_reason, changed_at: iso(Date.now()) })
        o.events = [{ at: iso(Date.now()), action: 'model_set', target: m.code, detail: { reason: b.p_reason }, by: 'admin@example.test' }, ...o.events]
      } else if (name === 'admin_ai_qualification_set_v1') {
        const s = o.services.find(x => x.service_code === b.p_service), q = s?.qualification.find(x => x.code === b.p_code)
        if (!s) return refuse(`service ${b.p_service} is not in the list`)
        if (!o.models.some(m => m.code === b.p_code)) return refuse(`model ${b.p_code} is not in the list`)
        if (!['qualified', 'unqualified', 'pending'].includes(b.p_status || 'qualified')) return refuse('status must be qualified, unqualified or pending')
        if ((b.p_status || 'qualified') === 'qualified' && String(b.p_evidence || '').trim().length < 10) return refuse('say what the qualification rests on (the evidence)')
        const entry = { code: b.p_code, qualified: (b.p_status || 'qualified') === 'qualified', status: b.p_status || 'qualified', provisional: false, prompt_version: s.prompt?.version || null, evidence: b.p_evidence, at: iso(Date.now()), by: 'u-admin', note: null }
        if (q) Object.assign(q, entry); else s.qualification.push(entry)
      } else if (name === 'admin_ai_route_set_v1') {
        const s = o.services.find(x => x.service_code === b.p_service), c = b.p_cascade || []
        if (!s) return refuse(`service ${b.p_service} is not in the list`)
        if (!c.length) return refuse('the cascade is empty: name at least one allowed model')
        if (c.length > 4) return refuse('a cascade holds 4 models at most')
        if (new Set(c).size !== c.length) return refuse('the cascade names a model twice')
        const unknown = c.filter(x => !o.models.some(m => m.code === x)), out = c.filter(x => o.models.find(m => m.code === x)?.status === 'not_allowed')
        if (unknown.length) return refuse(`unknown model in the cascade: ${unknown.join(', ')}`)
        if (out.length) return refuse(`not an allowed model: ${out.join(', ')} (Models & services › Models)`)
        if (s.migration_state !== 'routed' && c.length > 1) return refuse('this service uses one model: a fallback is not available for it yet')
        if (b.p_daily_usd_cap == null) return refuse('give a daily US$ cap (every service has one)')
        if (Number(b.p_daily_usd_cap) < 0 || Number(b.p_daily_calls_cap) < 0) return refuse('a cap cannot be negative (leave it empty for no cap)')
        s.cascade = [...c]
        Object.assign(s, { daily_usd_cap: Number(b.p_daily_usd_cap), daily_calls_cap: b.p_daily_calls_cap ?? null, enabled: b.p_enabled == null ? s.enabled : Boolean(b.p_enabled), reason: b.p_reason, changed_at: iso(Date.now()), changed_by: 'admin@example.test' })
        o.events = [{ at: iso(Date.now()), action: 'route_set', target: s.service_code, detail: { reason: b.p_reason }, by: 'admin@example.test' }, ...o.events]
      }
      o = derive(o)
      return { data: o }
    },
  }
}

/** Route the three calls on a page (after mockAdmin). Returns the state and the list of calls made. */
export async function mockAi(page, over = {}, opts = {}) {
  const state = aiState(over, opts), calls = []
  await page.route(/\/rest\/v1\/rpc\/admin_ai_(overview_v1|model_set_v1|route_set_v1|qualification_set_v1)$/, async route => {
    const name = new URL(route.request().url()).pathname.split('/').pop(), body = route.request().postDataJSON() || {}
    if (name !== 'admin_ai_overview_v1') calls.push({ name, ...body })
    const r = state.write(name, body)
    return r.error ? route.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify(r.error) }) : route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(r.data) })
  })
  return { state, calls }
}
