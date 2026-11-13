// Guards: Platform Admin 13 Nov 2026 19:14 — one model list, service routes with cascade and caps, usage by model (AI spend control)
// CF-247 migration 20261113380000. "GPT 4.1 mini is too expensive it has exhausted the AI credit. use other cheaper model and define the usage per
// field in ui under Model and Services ... Model classified that can be used - Qwen3, Mimo, mistral small, Kimi K2, Gemini, LLama, deepseek and
// then Service based Model with cascading, Then Recent usage" and 19:15 "Keep prompt respective for each service as well"; 19:23 "stop the entry
// requirement or any other setting using GPT mini now. all settings corresponding to model using AI model/prompt or services should be defined
// in Model & services". Phase 2 (migration 20261113390000): the route is the only place a model is chosen. The behaviour runs on isolated
// fixtures by tests/fixtures/ai-models-services/run.sh (scratch PostgreSQL 16, run locally): this file checks the migration text, the fixture's
// claims, the worker's cascade rule and the page contract document.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const MIG = fs.readFileSync('supabase/migrations/20261113380000_cf247_ai_models_services.sql', 'utf8')
const MIG2 = fs.readFileSync('supabase/migrations/20261113390000_cf247_ai_routes_only.sql', 'utf8')
const COLS = ['20261113377000_cf247_ai_ledger_columns', '20261113378000_cf247_ai_settings_home_columns', '20261113379000_cf247_ai_item_model_column'].map((f) => fs.readFileSync(`supabase/migrations/${f}.sql`, 'utf8'))
const WORKER_DIR = 'supabase/functions/coverage-sweep'
const worker = fs.readFileSync(`${WORKER_DIR}/index.ts`, 'utf8')
const FX = 'tests/fixtures/ai-models-services'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const doc = fs.readFileSync('docs/platform/AI-MODELS-SERVICES-CONTRACT.md', 'utf8')
const md5 = (s) => crypto.createHash('md5').update(s).digest('hex')
const body = (name) => MIG.match(new RegExp(`CREATE OR REPLACE FUNCTION ${name.replace('.', '\\.')}\\([\\s\\S]*?\\$function\\$;`))?.[0] ?? ''
const fn = (name) => MIG.match(new RegExp(`create or replace function ${name.replace('.', '\\.')}\\([\\s\\S]*?\\$function\\$;`))?.[0] ?? ''

test('the instruction is quoted, and four live definitions are edited md5-guarded both ways from the live text the fixture loads', () => {
  expect(MIG).toContain('GPT 4.1 mini is too expensive it has exhausted the AI credit. use other cheaper model and define the')
  expect(MIG).toContain('"Keep prompt respective for each service as well"')
  expect(MIG).toContain('stop the entry requirement or any other setting using GPT mini now')
  const edits = [['public.svc_enrich_ai_next(integer)', 'svc_enrich_ai_next'], ['public.svc_entry_matrix_next(integer)', 'svc_entry_matrix_next'],
    ['public.svc_ops_diagnosis_next(integer)', 'svc_ops_diagnosis_next'], ['security.ai_spend_capture_v1()', 'ai_spend_capture_v1']]
  for (const [sig, file] of edits) {
    const before = md5(fs.readFileSync(`${FX}/live/${file}.sql`, 'utf8'))
    const line = MIG.split('\n').find((l) => l.startsWith(`--   ${sig} `))
    expect(line, sig).toMatch(new RegExp(`${before} -> [0-9a-f]{32}$`))
    const after = line.slice(-32)
    expect(after).not.toBe(before)
    expect(MIG).toContain(`('${sig}', '${before}', '${after}')`)   // the guard accepts the live text or the text this change leaves, nothing else
    expect(run).toContain(`["${sig}"]=${before}`)
  }
  expect(MIG).toContain("raise exception 'live % differs from the definition this change replaces (md5 %)'")
  expect(run).toContain('drifted live body: refused, nothing left')
  expect(run).toContain('a second run changes nothing')
})

test('one model list: the seven families the Platform Admin named, anything else stored as other; OpenAI and Claude models listed as not allowed', () => {
  expect(MIG).toContain("check (family in ('qwen3', 'mimo', 'mistral_small', 'kimi_k2', 'gemini', 'llama', 'deepseek', 'other'))")
  expect(fn('security.ai_model_family_trg')).toContain("then new.family := 'other'; end if;")
  expect(MIG).toContain("status text not null default 'not_allowed' check (status in ('allowed', 'not_allowed'))")
  const seed = MIG.slice(MIG.indexOf('insert into pipeline.ai_model_catalogue'), MIG.indexOf('on conflict (code) do nothing;'))
  const models = [...seed.matchAll(/\('([a-z0-9.-]+)', '([a-z_0-9]+)', '[^']+', '([a-z-]+\/[A-Za-z0-9.:-]+)', [\d.]+, [\d.]+, now\(\), \d+, '(allowed|not_allowed)'/g)].map((m) => ({ code: m[1], family: m[2], id: m[3], status: m[4] }))
  expect(models).toHaveLength(17)
  for (const f of ['qwen3', 'mimo', 'mistral_small', 'kimi_k2', 'gemini', 'llama', 'deepseek']) expect(models.filter((m) => m.family === f && m.status === 'allowed').length, f).toBeGreaterThanOrEqual(1)
  for (const m of models.filter((x) => /^(openai|anthropic)\//.test(x.id))) expect(m.status, m.id).toBe('not_allowed')
  expect(models.filter((m) => /^(openai|anthropic)\//.test(m.id)).map((m) => m.code).sort()).toEqual(['claude-haiku-4.5', 'claude-sonnet-4.6', 'gpt-4.1', 'gpt-4.1-mini', 'gpt-4.1-nano'])
  expect(models.filter((m) => m.status === 'not_allowed').every((m) => /^(openai|anthropic)\//.test(m.id))).toBe(true)
  // the post-check refuses a seed whose cascade names a model that is not allowed, or an OpenAI or Anthropic model
  expect(MIG).toContain("raise exception 'post-check: a seeded cascade names a model that is not allowed: %', v;")
  expect(MIG).toContain("where m.model_identifier ~ '^(openai|anthropic)/';")
})

test('one route per service: every spend lane is covered, a cascade holds 1 to 4 models, no seeded cascade names GPT-4.1 mini', () => {
  expect(MIG).toContain('cascade text[] not null check (cardinality(cascade) between 1 and 4)')
  const seed = MIG.slice(MIG.indexOf('insert into pipeline.ai_service_routes'), MIG.indexOf('on conflict (service_code) do nothing;'))
  const services = [...seed.matchAll(/^  \('([a-z0-9_]+)', '/gm)].map((m) => m[1])
  expect(services).toEqual(['course_description', 'course_entry_requirements', 'course_other_fields', 'entry_matrices', 'entry_requirements_v2_shadow', 'scholarship_extraction',
    'scholarship_eligibility', 'provider_description', 'calendar_reading', 'central_english_policy', 'fee_reader', 'course_matching', 'adapter_builder', 'ops_diagnosis'])
  for (const lane of ['enrich_fields', 'scholarship_ai', 'entry_matrix', 'course_match', 'central_ai', 'fee_ai', 'provider_description', 'adapter_builder', 'ops_diagnose']) expect(seed, lane).toContain(`'${lane}'`)
  expect(seed).not.toMatch(/gpt-4|claude/)
  // the services that were on GPT-4.1 mini start on qwen3-30b; a second model only where the call honours a cascade (entry matrices and the
  // operations diagnosis use the first model only, so they are seeded with one)
  const rowOf = (s) => { const row = seed.slice(seed.indexOf(`('${s}'`)); return row.slice(0, row.indexOf('\n  (', 5) > 0 ? row.indexOf('\n  (', 5) : row.length) }
  expect(rowOf('course_entry_requirements')).toContain("array['qwen3-30b', 'mistral-small-3.2']")
  for (const s of ['entry_matrices', 'ops_diagnosis']) { expect(rowOf(s), s).toContain("array['qwen3-30b'], "); expect(rowOf(s), s).not.toContain('mistral') }
  // caps are read from the existing settings; the five services with no setting of their own carry the integrator's seeds, stated as such
  expect([...seed.matchAll(/array\[[^\]]+\], (\d+)(?:::numeric)?, null/g)].map((m) => Number(m[1]))).toEqual([5, 5, 2, 2, 2])
  expect(MIG).toContain("their caps are seeds chosen by the integrator, pending the Platform Admin's own values on the page: course_description 5,")
  expect(MIG).toContain('daily_usd_cap numeric not null check (daily_usd_cap >= 0),')
  expect(MIG).toContain("purpose_group text not null default 'other',")
  expect(seed).toContain("s.toolset_key = 'openrouter' and s.key = 'guard_entry_matrix'")
  expect(seed).toContain("s.toolset_key = 'pipeline' and s.key = 'ops.ai_diagnosis_usd_per_day'")
  // the course field reader is one route per field group, split by the item's field
  expect(seed).toContain(`'{"where": {"field": ["description"]}}'`)
  expect(seed).toContain(`'{"where": {"field": ["entry_requirements"]}}'`)
  expect(seed).toContain(`'{"where_not": {"field": ["description", "entry_requirements"]}}'`)
})

test('the route: allowed models in cascade order, held by the switch, the cascade, the daily ceiling and the caps, on the UTC day the guards count', () => {
  const r = fn('security.ai_route_v1')
  expect(r).toContain("order by c.ord) filter (where m.status = 'allowed' and q.status = 'qualified')")   // round 4: allowed AND qualified for the service
  expect(r).toContain("v_day timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';  -- fixed: the UTC day the AI guards count")
  expect(r).toContain("v_ceiling := security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14);")
  for (const reason of ['switched off (Models & services)', 'no allowed model in the cascade', "v_kind := 'credit_floor'; v_detail := 'credit_floor';", 'daily ceiling: US$%s spent today (UTC) across all AI services', 'service cap: US$%s spent today (UTC), cap US$%s', 'service cap: %s calls today (UTC), cap %s'])
    expect(r, reason).toContain(reason)
  // round 4 (Platform Admin review 13 Nov 2026 22:10). Fail closed on the balance: no reading, or one older than the setting, holds everything,
  // on-demand included, in both modes; so does the credit floor, a switched-off route and a cascade with no allowed or no qualified model
  expect(r).toContain("elsif jsonb_array_length(v_models) = 0 then v_kind := 'no_qualified_model';")
  expect(r).toContain("elsif v_bal is null then v_kind := 'balance_unknown';")
  expect(r).toContain("elsif v_at < now() - make_interval(mins => v_age) then v_kind := 'balance_stale';")
  expect(r).toContain("v_age int := coalesce((security.toolset_setting('openrouter', 'balance_max_age_minutes'))::text::numeric, 90)::int;")
  expect(MIG).toMatch(/\('openrouter', 'balance_max_age_minutes',[^;]*?'number', to_jsonb\(90\), 15, 1440, 'minutes'/)
  // the ceiling and the caps follow the EXISTING OpenRouter mode: reported in Observe only (would_hold), enforced in Stop at limits
  expect(r).toContain("v_stop boolean := security.toolset_enforced('openrouter');")
  expect(r).toContain("'held', v_kind is not null or (v_stop and v_lk is not null),")
  expect(r).toContain("'on_demand_exempt', v_kind is null and v_stop and v_lk is not null,")
  expect(r).toContain("'would_hold', v_kind is not null or v_lk is not null, 'would_hold_kind', coalesce(v_kind, v_lk), 'would_hold_reason', coalesce(v_detail, v_ld),")
  expect(r).toContain("'enforcing', v_stop, 'mode', case when v_stop then 'stop' else 'observe' end,")
  // a service whose call uses one model is handed one model
  expect(r).toContain("if r.migration_state <> 'routed' and jsonb_array_length(v_models) > 1 then v_models := jsonb_build_array(v_models->0); end if;")
  // the migrations change neither the mode nor the ceiling nor a live cap
  for (const m of [MIG, MIG2, ...COLS]) {
    expect(m).not.toMatch(/update pipeline\.platform_toolsets\b|insert into pipeline\.platform_toolsets\b/)
    expect(m).not.toMatch(/update pipeline\.platform_toolset_settings[^;]*budgets\.ai_daily_ceiling_usd/)
  }
})

test('the three readers ask the route; the keys the deployed worker reads stay; the old model settings are no longer read', () => {
  const e = body('public.svc_enrich_ai_next'), m = body('public.svc_entry_matrix_next'), o = body('public.svc_ops_diagnosis_next')
  for (const b of [e, m, o]) { expect(b.length).toBeGreaterThan(1000); expect(b).not.toMatch(/gpt-4|matrix_model|ai_diagnosis_model|central_ai_settings/) }
  expect(e).toContain('v_r := security.ai_enrich_routes_v1();')
  expect(e).toContain("select jsonb_build_object('model', coalesce(v_top->>'model', ''), 'model_code', coalesce(v_top#>>'{models,0,code}', ''),")
  expect(e).toContain("'models', coalesce(v_top->'models', '[]'::jsonb), 'routes', v_r->'routes', 'held', v_r->'held',")
  expect(e).toContain("'entry', jsonb_build_object('model', coalesce(v_r#>>'{routes,course_entry_requirements,model}', ''), 'models',")
  expect(e.match(/and not \(e\.field = any\(v_off\)\) and not \(v_off_rest and not \(e\.field = any\(v_not\)\)\)/g)).toHaveLength(2)   // the first pick and the same-course pick
  expect(e.match(/and \(e\.provider_id = any\(v_od\) or \(not \(e\.field = any\(v_capf\)\) and not \(v_cap_rest and not \(e\.field = any\(v_not\)\)\)\)\)/g)).toHaveLength(2)
  expect(m).toContain("v_route jsonb := security.ai_route_v1('entry_matrices'); v_model text := v_route->>'model';")
  expect(m).toContain("'model', v_model, 'model_code', split_part(v_model, '/', 2), 'models', v_route->'models',")
  expect(m).toContain("if security.pipeline_num_v1('entry.matrix_enabled', 0) < 1 or not security.ai_use_allowed_v1('entry_matrix') then return '[]'::jsonb; end if;")   // its switch is untouched
  expect(o).toContain("v_route jsonb := security.ai_route_v1('ops_diagnosis');")
  expect(o).toContain("model = v_route->>'model'")
  expect(o).toContain("if security.pipeline_num_v1('ops.ai_diagnosis_on', 0) < 1 then return jsonb_build_object('items', '[]'::jsonb, 'held', 'ops.ai_diagnosis_on is 0'); end if;")
  // the fixture compares the readers on the same rows before and after: every old key keeps its name and type
  for (const c of ['cmp_reader "svc_enrich_ai_next"', 'cmp_reader "svc_entry_matrix_next"', 'cmp_reader "svc_ops_diagnosis_next"']) expect(run).toContain(c)
  expect(run).toContain('a key the worker reads changed')
  // no switch is turned on or off by the migration; the two old settings keep their rows and values
  expect(MIG).not.toMatch(/update pipeline\.platform_toolset_settings[^;]*set value/)
  expect(MIG).toContain("'not read since migration 20261113380000 (13 Nov 2026): the model is chosen on Models & services (pipeline.ai_service_routes, service '")
  expect(MIG).not.toContain('supabase/functions')
})

test('on-demand work is not held by a cap or the ceiling; a switched-off route holds it too (operating model 3.3.2)', () => {
  // waived by purpose group only (as security.on_demand_request_for_v2 reads a request's scope), never for every service
  const od = fn('security.ai_on_demand_providers_v1')
  expect(od).toContain("r.state = 'open' and r.expires_at > now() and 'openrouter' = any (r.toolsets)")
  expect(od).toContain('and (r.purpose_groups is null or s.purpose_group = any (r.purpose_groups))')
  expect(MIG).not.toContain('security.ai_on_demand_providers_v1()')
  expect(body('public.svc_entry_matrix_next')).toContain("if v_model is null or (coalesce((v_route->>'held')::boolean, true) and not (coalesce((v_route->>'on_demand_exempt')::boolean, false) and cardinality(v_od) > 0)) then return '[]'::jsonb; end if;")
  expect(fixtures).toContain('on-demand is waived by purpose group only and stops at the credit floor')
  expect(fixtures).toContain('an on-demand provider is not held by a limit, but is by a switch')
})

test('usage by service and model: two columns beside, filled by the one writer; a failure there never stops the cost being recorded', () => {
  // the columns come from their own one-table migrations (QA B2): a short lock that fails fast, and no later migration alters a hot table
  expect(COLS[0]).toContain('alter table pipeline.ai_spend_ledger add column if not exists service_code text;')
  expect(COLS[0]).toContain('alter table pipeline.ai_spend_ledger add column if not exists model text;')
  for (const c of COLS) { expect(c).toContain("set local lock_timeout = '3s';"); expect(new Set([...c.matchAll(/^alter table (pipeline\.[a-z_]+)/gm)].map((m) => m[1])).size).toBe(1); expect(c).toMatch(/^-- Replaces: nothing\./m) }
  for (const m of [MIG, MIG2]) expect(m).not.toMatch(/^\s*alter table pipeline\.(ai_spend_ledger|platform_toolset_settings|field_enrich_items)\b|create index[^;]* on pipeline\.ai_spend_ledger/im)
  expect(MIG).toContain("raise exception 'migrations 20261113377000 and 20261113378000 (the columns) must be applied before this change';")
  expect(MIG).toContain('-- Locks this migration takes on tables that exist before it (no ACCESS EXCLUSIVE on any of them; it adds no column):')
  expect(MIG2).toContain('-- Locks this migration takes on tables that exist before it (no ACCESS EXCLUSIVE; it adds no column):')
  expect(fs.readFileSync(`${FX}/concurrent.sh`, 'utf8')).toContain('concurrent writers: no deadlock, no lock time-out, no wait of 3 seconds')
  const c = body('security.ai_spend_capture_v1')
  expect(c).toContain("v_svc := security.ai_ledger_service_v1(tg_argv[0], tg_table_name, v_new);")
  expect(c).toContain("v_model := coalesce(nullif(v_new->>'model', ''), nullif(v_new->>'model_identifier', ''), nullif(v_new->>'model_code', ''), security.ai_service_model_v1(v_svc));")
  expect(c).toContain('exception when others then v_svc := null; v_model := null;')
  expect(c).toContain("insert into pipeline.ai_spend_ledger(lane, source, source_id, cost_usd, service_code, model) values (tg_argv[0], tg_table_name, v_new->>'id', v_add, v_svc, v_model);")
  // rows already there get their service (today's spend counts at once), never a model
  const backfill = MIG.slice(MIG.indexOf('update pipeline.ai_spend_ledger l'), MIG.indexOf('-- 9c the settings'))
  expect(backfill).toContain('where l.service_code is null;')
  expect(backfill).not.toMatch(/\bmodel\s*=/)
})

test('the page: one read and two writes, role-checked as the Services tab is, every change with a reason in the log; refusals', () => {
  const o = fn('public.admin_ai_overview_v1'), ms = fn('public.admin_ai_model_set_v1'), rs = fn('public.admin_ai_route_set_v1')
  // round 4 roles: the read is open to rank 3; routes, caps and switches are rank 5; the allow-list (and qualification, phase 2) is rank 6
  expect(o).toContain("if auth.uid() is null or v_rank < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;")
  expect(rs).toContain("if auth.uid() is null or security.current_role_rank() < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;")
  expect(ms).toContain("if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;")
  for (const w of [ms, rs]) {
    expect(w).toContain("if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;")
    expect(w).toContain('insert into pipeline.admin_control_events(area, action, target, detail, actor)')
  }
  for (const refusal of ['the cascade is empty: name at least one allowed model', 'unknown model in the cascade: %', 'not an allowed model: % (Models & services › Models)', 'a cascade holds 4 models at most', 'the cascade names a model twice'])
    expect(rs, refusal).toContain(refusal)
  for (const k of ["'openrouter'", "'key_present'", "'balance_usd'", "'balance_observed_at'", "'floor_usd'", "'low_warn_usd'", "'daily_ceiling_usd'", "'spent_today_usd'", "'models'", "'used_by'", "'services'", "'spent_today'", "'held'", "'prompt'", "'usage'", "'by_day_14d'", "'by_hour_24h'", "'settings'"])
    expect(o, k).toContain(k)
  expect(o).not.toMatch(/vault|decrypted|secret_value/i)   // the key itself is never read
  expect(MIG).toContain('grant execute on function public.admin_ai_overview_v1(), public.admin_ai_model_set_v1(text, text, text), public.admin_ai_route_set_v1(text, text[], numeric, integer, boolean, text) to authenticated, service_role;')
  expect(MIG).toContain('alter table pipeline.ai_model_catalogue enable row level security;')
  expect(MIG).toContain('alter table pipeline.ai_service_routes enable row level security;')
  // the contract the page is built from names the three calls and the existing audited setting write
  for (const s of ['admin_ai_overview_v1', 'admin_ai_model_set_v1', 'admin_ai_route_set_v1', "admin_toolsets_write('setting'", 'held_kind', 'enforced', 'legacy']) expect(doc, s).toContain(s)
})

test('settings that belong to Models & services are marked, not moved or hidden; GPT-4.1 mini leaves the scholarship chain', () => {
  expect(COLS[1]).toContain('alter table pipeline.platform_toolset_settings add column if not exists home text;')
  expect(COLS[1]).toContain('alter table pipeline.platform_toolset_settings add column if not exists home_group text;')
  expect(MIG).toContain("update pipeline.platform_toolset_settings s set home = 'models_services', home_group = m.grp")
  for (const p of ["('openrouter', '.', 'openrouter')", "'^budgets\\.ai_', 'openrouter'", "'^(ops|har)\\.ai_', 'ops_diagnosis'", "'^enrich\\.course_entry_', 'course_entry_requirements'"]) expect(MIG, p).toContain(p)
  expect(MIG).toContain("update pipeline.scholarship_ai_extract_settings s set chain = array_remove(s.chain, 'gpt-4.1-mini')")
  expect(MIG).toContain("and cardinality(array_remove(s.chain, 'gpt-4.1-mini')) >= 1")   // a chain is never left empty
  const inv = fs.readFileSync('docs/platform/SETTINGS-INVENTORY-2026-11-13.md', 'utf8')
  expect(inv).toContain('Nothing is deleted, hidden or marked retiring')
  expect(inv).toContain('## 2. Not read anywhere (retire candidates)')
})

test('the central readers keep one model with their routes, both ways, and cannot be set to a model that is not allowed', () => {
  expect(fn('security.ai_route_central_trg')).toContain("if pg_trigger_depth() > 1 or new.resolver <> 'pipeline.central_ai_settings' then return null; end if;")
  expect(fn('security.ai_central_settings_trg')).toContain("raise exception 'model % is not an allowed model (Models & services › Models)', new.model_identifier using errcode = '23514';")
  // phase 2 ends the shared model: each central service has its own cascade and the old copy cannot be set
  expect(fixtures).toContain('each central service has its own cascade and the old copy cannot be set')
  expect((fixtures.match(/raise notice 'ok \d+ /g) || []).length).toBe(13)
  expect(run).toContain('grep -c "NOTICE:  ok " <<<"$OUT")" = 13')
})

// ---- phase 2 (migration 20261113390000): the route is the only place a model is chosen ----
const body2 = (name) => MIG2.match(new RegExp(`CREATE OR REPLACE FUNCTION ${name.replace('.', '\\.')}\\([\\s\\S]*?\\$function\\$;`))?.[0] ?? ''
const fn2 = (name) => MIG2.match(new RegExp(`create or replace function ${name.replace('.', '\\.')}\\([\\s\\S]*?\\$function\\$;`))?.[0] ?? ''

test('phase 2: twenty-three live definitions are replaced, each md5-guarded both ways from the live text the fixture loads; phase 1 must be applied first', () => {
  const rows = [...MIG2.matchAll(/^      \('((?:public|security)\.[a-z0-9_]+\([a-z0-9_ ,\[\]]*\))', '([0-9a-f]{32})', '([0-9a-f]{32})'\),?$/gm)].map((m) => ({ sig: m[1], before: m[2], after: m[3] }))
  expect(rows).toHaveLength(23)
  for (const r of rows) {
    const file = r.sig.replace(/^(public|security)\./, '').replace(/\(.*/, '')
    expect(md5(fs.readFileSync(`${FX}/live2/${file}.sql`, 'utf8')), r.sig).toBe(r.before)
    expect(r.after).not.toBe(r.before)
    expect(MIG2, r.sig).toContain(`--   ${r.sig}  ${r.before} -> ${r.after}`)
    expect(run).toContain(`["${r.sig}"]=${r.before}`)
  }
  expect(MIG2).toContain("raise exception 'migration 20261113380000 (AI models and services, phase 1) must be applied before this change'")
  expect(run).toContain('phase 2: refused without phase 1 and over a drifted live body, nothing left')
  expect(run).toContain('a second run changes nothing')
  expect(MIG2).toMatch(/^-- Replaces: .+/m); expect(MIG2).toMatch(/^-- Retires: .+/m)
})

test('phase 2: every reader takes its model from its route and is held by it; no reader reads a model from the old places', () => {
  const readers = { 'public.svc_fee_ai_next': 'fee_reader', 'public.svc_provider_description_next': 'provider_description', 'public.svc_provider_description_reserve_v1': 'provider_description',
    'security.provider_description_selection_v1': 'provider_description', 'public.svc_scholarship_ai_next': 'scholarship_extraction', 'public.svc_scholarship_eligibility_next': 'scholarship_eligibility',
    'public.svc_scholarship_recheck_next': 'scholarship_extraction', 'security.aer_v2_shadow_hold_v1': 'entry_requirements_v2_shadow', 'public.svc_aer_v2_shadow_record': 'entry_requirements_v2_shadow',
    'public.svc_coverage_ai_match_next': 'course_matching', 'security.scholarship_ai_active_v1': 'scholarship_extraction', 'security.scholarship_ai_next_model_v1': 'scholarship_extraction',
    'security.adapter_builder_model_for_v1': 'adapter_builder', 'security.adapter_builder_models_v1': 'adapter_builder', 'security.adapter_builder_budget': 'adapter_builder' }
  for (const [name, service] of Object.entries(readers)) {
    const b = body2(name); expect(b.length, name).toBeGreaterThan(200)
    expect(b, name).toMatch(new RegExp(`security\\.ai_route_(gate_)?v1\\('${service}'\\)`))
    expect(b, name).not.toMatch(/central_ai_settings c? ?where|model_identifier from pipeline\.central_ai_settings|s\.chain\[|scholarship_ai_models|x\.model into v_model from pipeline\.aer_prompt_versions|firecrawl_setting\('builder_model'\)|gpt-4|claude/)
  }
  const central = body2('public.svc_central_ai_next')
  expect(central).toContain("v_cal jsonb := security.ai_route_gate_v1('calendar_reading'); v_pol jsonb := security.ai_route_gate_v1('central_english_policy');")
  expect(central).toContain("and security.ai_route_open_v1(case when q.kind = 'intake_calendar' then v_cal else v_pol end, q.provider_id)")
  // the keys the worker reads keep their names; `models` is new beside them
  expect(body2('public.svc_fee_ai_next')).toContain("'model', v_rt->>'model', 'model_code', v_rt#>>'{models,0,code}', 'models', v_rt->'models',")
  expect(body2('public.svc_coverage_ai_match_next')).toContain("'candidates', u.candidates, 'model', v_rt->>'model', 'models', v_rt->'models')), '[]'::jsonb)")
  expect(body2('security.aer_v2_shadow_hold_v1')).toContain("'version', v.version, 'system_text', v.system_text, 'system_sha256', v.system_sha256,")   // the prompt version keeps its text and sha
  expect(body2('security.aer_v2_shadow_hold_v1')).toContain("'model', v_rt->>'model', 'models', v_rt->'models', 'quote_max_chars', v.quote_max_chars) end,")
  // held as phase 1 holds: the gate; a cap or the ceiling does not hold an on-demand provider, a switch does
  expect(fn2('security.ai_route_open_v1')).toContain("select not coalesce((p_route->>'held')::boolean, true)\n      or (coalesce((p_route->>'on_demand_exempt')::boolean, false) and p_provider is not null and coalesce(p_route->'on_demand_providers' ? p_provider::text, false))")
  expect(fn2('security.ai_route_gate_v1')).toContain('security.ai_on_demand_providers_v1(p_service)')
  for (const name of ['public.svc_fee_ai_next', 'public.svc_scholarship_ai_next', 'public.svc_scholarship_eligibility_next', 'public.svc_scholarship_recheck_next', 'public.svc_coverage_ai_match_next'])
    expect(body2(name), name).toContain('security.ai_route_open_v1(v_rt, ')
  // the scholarship chain: unproven goes to the next model of the cascade, then a person (the record function is unchanged but for the model lookup)
  expect(body2('public.svc_scholarship_ai_record')).toContain('v_next := case when v_why is not null then security.scholarship_ai_next_model_v1(q.model_code) end;')
  expect(body2('security.ai_model_pinned_ok_v1')).toContain("and exists (select 1 from pipeline.ai_model_catalogue m where m.model_identifier = p_model and m.status = 'allowed')")
  expect(MIG2).toContain("update pipeline.ai_service_routes r set resolver = 'route',")
  expect(MIG2).toContain("raise exception 'post-check: a service is not resolved by its route: %', v;")
})

test('phase 2: every route has a cap (integrator seeds, stated as such); the old copies cannot be set; the page read says enforced', () => {
  expect(MIG2).not.toMatch(/alter table pipeline\.ai_service_routes/)   // the cap is required by the table since phase 1; phase 2 alters nothing
  expect(fn2('public.admin_ai_route_set_v1')).toContain("if p_daily_usd_cap is null then raise exception 'give a daily US$ cap (every service has one)'; end if;")
  expect(fn2('security.ai_central_settings_trg')).toContain("raise exception 'the model is chosen on Models & services (each service has its own route); it can no longer be set here' using errcode = '23514';")
  expect(MIG2).toContain('create trigger ai_scholarship_chain_copy before update of chain on pipeline.scholarship_ai_extract_settings')
  const o = fn2('public.admin_ai_overview_v1')
  expect(o).toContain("'enforced', r.resolver = 'route', 'model', rt.j->>'model',")
  expect(o).toContain("'legacy', jsonb_build_object('layer3', jsonb_build_object(")
  expect(o).toContain("from pipeline.layer3_model_profiles p where p.enabled and not p.paused and p.retired_at is null")
  expect(MIG2).not.toMatch(/layer3_route_tiers set|update pipeline\.layer3_model_profiles/)   // Layer 3 is reported, not wired or changed
  // nothing is dropped or deleted by the migration itself; the daily retention job's own function (security.ledger_retention_v1, live text plus
  // one line for old model call attempts) is the only body with a delete, and it runs under its retention settings
  expect(MIG2.replace(body2('security.ledger_retention_v1'), '')).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(body2('security.ledger_retention_v1')).toContain("delete from pipeline.ai_invocations where at < now() - make_interval(days => security.pipeline_num_v1('retention.ai_invocations_days', 90)::int);")
  for (const s of ['enforced', 'legacy', 'layer3', 'page_identity', 'Platform Admin (rank 6)', 'accepts text settings', 'Changes for the UI (round 3)', 'caps_total_usd', 'caps_exceed_ceiling', 'would_hold_now', 'credit_floor', 'not_read', 'profile_id', 'purpose_group', 'Matching and identity']) expect(doc, s).toContain(s)
  for (const k of ["'ceiling_usd'", "'caps_total_usd'", "'caps_exceed_ceiling'", "'would_hold_now'", "'balance_known'", "'profile_id'", "'not_read'", "'read_only'"]) expect(o, k).toContain(k)
  expect(o).toContain('limit 20) e  -- fixed: the page shows the last 20 changes')
})

test('phase 2: the guard lists what names a model outside the routes; no model is named in worker or app code outside the allow-list', () => {
  const g = fn2('security.ai_route_guard_v1')
  for (const k of ["'functions'", "'settings'", "'cascades'", "'not_allowed_named'"]) expect(g, k).toContain(k)
  expect(g).toContain("where s.kind = 'text'")
  expect(fixtures).toContain('"function": "public.fx_pins_a_model", "model": "openai/gpt-4.1-mini", "status": "not_allowed"')
  const allow = JSON.parse(fs.readFileSync('tests/uat/support/ai-model-literals-allowlist.json', 'utf8')).allowed
  const notAllowed = [...MIG.matchAll(/'([a-z-]+\/[A-Za-z0-9.:-]+)', [\d.]+, [\d.]+, now\(\), \d+, 'not_allowed'/g)].map((m) => m[1])
  expect(notAllowed.sort()).toEqual(['anthropic/claude-haiku-4.5', 'anthropic/claude-sonnet-4.6', 'openai/gpt-4.1', 'openai/gpt-4.1-mini', 'openai/gpt-4.1-nano'])
  for (const a of allow) expect(notAllowed, `${a.file}: ${a.model}`).not.toContain(a.model)
  const LIT = /['"`]((?:openai|anthropic|qwen|xiaomi|mistralai|moonshotai|google|meta-llama|deepseek|x-ai|cohere|amazon|microsoft|nvidia|perplexity)\/[A-Za-z0-9][A-Za-z0-9._:-]*)['"`]/g
  const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => e.name === 'node_modules' ? [] : e.isDirectory() ? walk(`${d}/${e.name}`) : /\.(ts|tsx|js|jsx|mjs|json)$/.test(e.name) ? [`${d}/${e.name}`] : [])
  const found = []
  for (const f of [...walk('supabase/functions'), ...walk('src')]) for (const m of fs.readFileSync(f, 'utf8').matchAll(LIT)) if (!allow.some((a) => a.file === f && a.model === m[1])) found.push(`${f}: ${m[1]}`)
  expect(found, 'a model identifier is written in code: choose models in pipeline.ai_service_routes (Models & services)').toEqual([])
  expect(worker).not.toMatch(/const (AI_MATCH_MODEL|PAGE_ID_MODELS)\b/)
})

test('phase 2 worker: models come from the readers; the cascade moves on only on a technical failure; the model that answered is recorded; prompts unchanged', async () => {
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.85\.0"; \/\/ v0\.85\.0 \(13 Nov 2026, CF-247 AI spend control|\/\/ was v0\.85\.0 \/\/ v0\.85\.0 \(13 Nov 2026, CF-247 AI spend control/)
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.86\.0"; \/\/ v0\.86\.0 \(13 Nov 2026, CF-247 Platform Admin review 22:10\): every model call attempt is kept|\/\/ was v0\.86\.0 \/\/ v0\.86\.0 \(13 Nov 2026, CF-247 Platform Admin review 22:10\)/)
  expect(worker).toContain('// was v0.84.0 // v0.84.0 (13 Nov 2026, CF-247 operating model 3.3.2')
  expect(worker).toContain('const model = String(routes.course_other_fields?.model || w?.model || ""), descModel = String(routes.course_description?.model || w?.model || "")')
  expect(worker).toContain('await askText(cdescRequest(descModel, cdescUser(')
  expect(worker).toContain('model: String(it.model || ""), temperature: 0, max_tokens: maxTokens, usage: { include: true }, provider: { require_parameters: true },')
  // round 4 (v0.86.0): every model call goes through cascade.ts so that each attempt is kept. Nine calls carry the route's cascade; six name their
  // service only (one model, the call as it was), each for a stated reason (the database chain, a reserved price, a pinned record): scholarship pages
  // and eligibility, provider descriptions, adapter proposals, operations diagnosis, entry matrices
  expect((worker.match(/await cascadeFetch\(/g) || []).length).toBe(15)
  expect((worker.match(/await cascadeFetch\((ors\.)?fetch, \{ models: /g) || []).length).toBe(9)
  expect([...worker.matchAll(/await cascadeFetch\((?:ors\.)?fetch, \{ service: "([a-z_0-9]+)" \}, /g)].map((m) => m[1]).sort())
    .toEqual(['adapter_builder', 'entry_matrices', 'ops_diagnosis', 'provider_description', 'scholarship_eligibility', 'scholarship_extraction'])
  expect((worker.match(/await (ors\.)?fetch\("https:\/\/openrouter\.ai\/api\/v1\/chat\/completions"/g) || []).length).toBe(0)
  for (const l of worker.split('\n').filter((x) => x.includes('await cascadeFetch('))) expect(l, l.slice(0, 120)).toMatch(/\bservice[:, }]/)   // every call names its service
  // the attempts are sent once, after the call is answered; a failure to send them never fails the call
  expect(worker).toContain('await ct.rpc("svc_ai_model_answered_v1", { p_source: null, p_source_id: null, p_model: null, p_attempts: attempts, p_worker: WORKER });')
  expect(worker).toContain('} catch { /* the trace never fails a call */ }')
  expect(worker).toContain('rpc("svc_ai_model_answered_v1", { p_source: "central_ai_queue", p_source_id: String(it.queue_id), p_model: usedModel })')
  expect(worker).toContain('p_prompt_version: version, p_model: String((out as any).model || model), p_evidence_id')
  expect(worker).toContain('model: used.size ? [...used].join("+") : em, worker')
  // prompt versions are byte-identical to the versions before this change
  for (const [f, c] of [['course-entry.ts', 'export const COURSE_ENTRY_PROMPT_VERSION = "course-entry-v1";'], ['course-text.ts', 'export const COURSE_TEXT_PROMPT_VERSION = "course-text-v2";'],
    ['course-text.ts', 'export const CDESC_PROMPT_VERSION = "cdesc-source-grounded-v1";'], ['entry.ts', 'export const ENTRY_PROMPT_VERSION = "entry-matrix-v0.1.4";'], ['calendar.ts', 'export const CALENDAR_READER = "calendar-v2.4";']])
    expect(fs.readFileSync(`${WORKER_DIR}/${f}`, 'utf8'), c).toContain(c)
  // the rule itself, run: cascade.ts with a scripted fetch
  const { transformSync } = await import('esbuild')
  const out = `test-results/cascade-${process.pid}.mjs`
  fs.mkdirSync('test-results', { recursive: true }); fs.writeFileSync(out, transformSync(fs.readFileSync(`${WORKER_DIR}/cascade.ts`, 'utf8'), { loader: 'ts', format: 'esm' }).code)
  const { cascadeFetch, cascadeModels, technicalFailure, sentModel, takeAiTrace, failureKind } = await import(`${process.cwd()}/${out}`)
  const ans = (model, content, extra = {}) => new Response(JSON.stringify({ model, usage: { cost: 0.01 }, choices: [{ finish_reason: 'stop', message: { content } }], ...extra }), { status: 200 })
  const models = [{ code: 'a', model_identifier: 'v/a' }, { code: 'b', model_identifier: 'v/b' }, { code: 'c', model_identifier: 'v/c' }]
  const init = { method: 'POST', body: JSON.stringify({ model: 'v/a', response_format: { type: 'json_schema' }, messages: [] }) }
  let calls = []
  const scripted = (script) => async (_url, i) => { const m = JSON.parse(i.body).model; calls.push(m); const r = script[m]; if (r instanceof Error) throw r; return r() }
  expect(cascadeModels('v/b', models)).toEqual(['v/b', 'v/c']); expect(cascadeModels('x/y', models)).toEqual(['x/y'])
  // the first model answered "not stated": that is the answer, no other model is asked
  let d = await (await cascadeFetch(scripted({ 'v/a': () => ans('v/a', '{"value":null,"stated":false}') }), { models }, 'u', init)).json()
  expect(calls).toEqual(['v/a']); expect(sentModel(d, 'v/a')).toBe('v/a'); expect(d.usage.cost).toBe(0.01)
  // an HTTP error: the next model is asked; the answer names it and carries both costs
  calls = []; d = await (await cascadeFetch(scripted({ 'v/a': () => new Response(JSON.stringify({ error: { message: 'down' }, usage: { cost: 0.002 } }), { status: 503 }), 'v/b': () => ans('v/b', '{"ok":1}') }), { models }, 'u', init)).json()
  expect(calls).toEqual(['v/a', 'v/b']); expect(d.cf_model_sent).toBe('v/b'); expect(d.usage.cost).toBeCloseTo(0.012, 9); expect(d.cf_cascade_tried).toEqual([{ model: 'v/a', why: 'HTTP 503' }])
  // a time-out, then a cut answer, then an answer
  calls = []; d = await (await cascadeFetch(scripted({ 'v/a': Object.assign(Error('timed out'), { name: 'TimeoutError' }), 'v/b': () => ans('v/b', '{"a":', { choices: [{ finish_reason: 'length', message: { content: '{"a":' } }] }), 'v/c': () => ans('v/c', '{"ok":1}') }), { models }, 'u', init)).json()
  expect(calls).toEqual(['v/a', 'v/b', 'v/c']); expect(d.cf_model_sent).toBe('v/c')
  // malformed JSON moves on; every model failing returns the last failure as it came
  calls = []; await cascadeFetch(scripted({ 'v/a': () => ans('v/a', 'not json'), 'v/b': () => ans('v/b', '{}') }), { models }, 'u', init); expect(calls).toEqual(['v/a', 'v/b'])
  calls = []; const r = await cascadeFetch(scripted({ 'v/a': () => new Response('{}', { status: 500 }), 'v/b': () => new Response('{}', { status: 429 }), 'v/c': () => new Response('{}', { status: 502 }) }), { models }, 'u', init)
  expect(r.status).toBe(502); expect(calls).toHaveLength(3)
  // one model: the call exactly as it was
  let seen = null; await cascadeFetch(async (_u, i) => { seen = i; return ans('v/a', '{}') }, null, 'u', init); expect(seen).toBe(init)
  // the caller's time budget: with too little time left no later model is asked and the failure is returned as it came
  calls = []; const late = await cascadeFetch(scripted({ 'v/a': () => new Response('{}', { status: 503 }), 'v/b': () => ans('v/b', '{}') }), { models, deadline: Date.now() + 5000 }, 'u', init)
  expect(calls).toEqual(['v/a']); expect(late.status).toBe(503)
  expect(worker.match(/deadline: t0 \+ BUDGET_MS - 25000, service[^}]*\}, "https:\/\/openrouter/g)).toHaveLength(9)
  // no model handed out: the item is left alone (not recorded as an error)
  expect(worker).toContain('if (!(it as any).model) { tally.no_model = (tally.no_model || 0) + 1; return }')
  expect(worker).not.toContain('no model handed out by the route course_matching')
  expect(technicalFailure(200, { choices: [{ finish_reason: 'stop', message: { content: '{"stated":false}' } }] }, true)).toBeNull()
  fs.rmSync(out, { force: true })
})

test('round 3 (independent QA and the page): scholarship models follow the catalogue; settings reads say where a setting belongs; the old write path is retiring', () => {
  // B1: scholarship_ai_queue.model_code refers to scholarship_ai_models, so every allowed model has a row there; the first of the route is active
  const sync = fn2('security.ai_central_sync_v1')
  expect(sync).toContain("insert into pipeline.scholarship_ai_models (code, label, model_identifier, status, sort)")
  expect(sync).toContain("where c.status = 'allowed' and not exists (select 1 from pipeline.scholarship_ai_models x where x.code = c.code);")
  expect(sync).toContain("update pipeline.scholarship_ai_models x set status = 'active', activated_at = now(), reason = 'first model of the scholarship route (Models & services)'")
  expect(MIG2).toContain('create trigger ai_model_added after insert on pipeline.ai_model_catalogue for each row execute function security.ai_model_status_trg();')
  expect(MIG2).toContain("raise exception 'post-check: an allowed model has no row in pipeline.scholarship_ai_models: %', v;")
  expect(fixtures).toContain("the queue foreign key holds")
  expect(fs.readFileSync(`${FX}/stubs2.sql`, 'utf8')).toContain('foreign key (model_code) references pipeline.scholarship_ai_models(code)')
  // queued reads naming a model that is not allowed are re-pointed (an update, counted; nothing deleted)
  expect(MIG2).toContain("raise notice 'scholarship queue: % queued read(s) naming a model that is not allowed re-pointed to %', n, v_first;")
  // a model outside the Platform Admin's families cannot be allowed from the page; the seed stores those families as other
  expect(fn('public.admin_ai_model_set_v1')).toContain("raise exception 'this model is not in a family the Platform Admin allows (Qwen3, MiMo, Mistral Small, Kimi K2, Gemini, Llama, DeepSeek); adding a family is a release';")
  expect(MIG).not.toMatch(/'(openai|anthropic)', '(GPT|Claude)/)
  // the two settings reads return home and home_group (additive)
  expect(body2('public.admin_settings_register_read')).toContain("'unit', s.unit, 'home', s.home, 'home_group', s.home_group, 'used_by', s.used_by,")
  expect(body2('public.admin_toolsets_read')).toContain("'unit', s.unit, 'home', s.home, 'home_group', s.home_group, 'section', s.section,")
  expect(fn2('security.ai_settings_not_read_v1')).toContain("values ('pipeline', 'entry.matrix_model', 'routes entry_matrices and course_entry_requirements'), ('pipeline', 'ops.ai_diagnosis_model', 'route ops_diagnosis'),")
  // areas as the page names them
  const areas = new Set([...MIG.slice(MIG.indexOf('insert into pipeline.ai_service_routes'), MIG.indexOf('on conflict (service_code) do nothing;')).matchAll(/^  \('[a-z0-9_]+', '[^']+', '([A-Za-z ]+)', /gm)].map((m) => m[1])); areas.add('Matching and identity')
  expect([...areas].sort()).toEqual(['Courses', 'Entry requirements', 'Fees', 'Matching and identity', 'Operations', 'Providers', 'Scholarships'])
  // the old model write path is marked retiring; N1: a provider's own model must be switched on
  expect(MIG2).toContain("values ('function', 'public.admin_ai_config(text,jsonb)', 'Platform', 'Models & services', 'Old AI configuration card: central model and switch', 'retiring', '{}',")
  expect(MIG2).toContain("current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int)")
  expect(body2('security.adapter_builder_model_for_v1')).toContain('where a.provider_id = p_provider_id and m.enabled and not m.paused and m.retired_at is null')
})

// ---- round 4 (Platform Admin review 13 Nov 2026 22:10) --------------------------------------------------------------------------------------------

test('round 4: only a qualified model is handed out; the seeds cite their evidence; qualifying is a Platform Admin act that switches nothing on', () => {
  expect(MIG).toContain('create table if not exists pipeline.ai_route_qualifications (')
  expect(MIG).toMatch(/comment on table pipeline\.ai_route_qualifications is '/)
  const seed = MIG.slice(MIG.indexOf('insert into pipeline.ai_route_qualifications'), MIG.indexOf(') v(service_code, model_code, prompt_version, status, provisional, evidence, note)'))
  const rows = [...seed.matchAll(/^  \('([a-z_0-9]+)', '([a-z0-9.-]+)', (?:'[^']*'|null), '(qualified|unqualified)', (true|false),\s*(?:\n\s*)?('(?:[^']|'')*'|null)/gm)].map((m) => ({ svc: m[1], model: m[2], status: m[3], provisional: m[4] === 'true', evidence: m[5] }))
  const q = rows.filter((r) => r.status === 'qualified')
  expect(q.map((r) => r.svc).sort()).toEqual(['adapter_builder', 'calendar_reading', 'central_english_policy', 'course_description', 'course_matching', 'course_other_fields', 'fee_reader', 'provider_description', 'scholarship_eligibility', 'scholarship_extraction'])
  for (const r of q) { expect(r.model, r.svc).toBe('qwen3-30b'); expect(r.evidence, r.svc).not.toBe('null'); expect(r.evidence.length, r.svc).toBeGreaterThan(40) }
  // the central services run on the Platform Admin's own decision of 19:09 and say that their regression qualification is pending
  for (const r of q.filter((x) => x.provisional)) expect(r.evidence).toBe("'Platform Admin decision 13 Nov 2026 19:09 (central model set to Qwen3 30B); regression qualification pending'")
  expect(q.filter((x) => x.provisional).map((r) => r.svc).sort()).toEqual(['calendar_reading', 'central_english_policy', 'course_description', 'course_other_fields', 'fee_reader', 'provider_description'])
  // the entry readers and the operations diagnosis ran on GPT-4.1 mini: no model is qualified for them, so they stay held
  expect(rows.filter((r) => r.status === 'unqualified').map((r) => r.svc).filter((v, i, a) => a.indexOf(v) === i).sort()).toEqual(['course_entry_requirements', 'entry_matrices', 'entry_requirements_v2_shadow', 'ops_diagnosis'])
  const qf = fn2('public.admin_ai_qualification_set_v1')
  expect(qf).toContain("if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;")
  expect(qf).toContain("create or replace function public.admin_ai_qualification_set_v1(p_service text, p_code text, p_evidence text, p_reason text, p_status text default 'qualified') returns jsonb")
  expect(qf).toContain("if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;")
  expect(qf).toContain('insert into pipeline.admin_control_events(area, action, target, detail, actor)')
  expect(qf).not.toMatch(/update pipeline\.ai_service_routes|enabled\s*=/)   // a passing qualification never switches anything on by itself
  expect(MIG2).toContain('grant execute on function public.admin_ai_qualification_set_v1(text, text, text, text, text) to authenticated, service_role;')
  // a service whose call uses one model refuses a second one
  expect(fn2('public.admin_ai_route_set_v1')).toContain("'this service uses one model: a fallback is not available for it yet'")
  expect(MIG).toMatch(/migration_state text not null default 'not_migrated' check \(migration_state in \('routed', 'routed_single', 'not_migrated'\)\)/)
  expect(fs.readFileSync(`${FX}/seeded.sql`, 'utf8').match(/raise notice 'ok [ABC] /g)).toHaveLength(3)
  expect(run).toContain('seeded.sql')
})

test('round 4: every model call attempt is kept with tokens and cost; the page read counts them and the fallbacks; the attempts go with the retention job', async () => {
  expect(MIG).toContain('create table if not exists pipeline.ai_invocations (')
  expect(MIG).toMatch(/comment on table pipeline\.ai_invocations is '/)
  const a = fn2('public.svc_ai_model_answered_v1')
  expect(a).toContain('create or replace function public.svc_ai_model_answered_v1(p_source text, p_source_id text, p_model text, p_attempts jsonb default null, p_worker text default null) returns integer')
  expect(a).toContain("if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;")
  expect(a).toContain('insert into pipeline.ai_invocations (service_code, model, attempt_no, outcome, failure_kind, input_tokens, output_tokens, cost_usd, source, source_id, worker)')
  const o = fn2('public.admin_ai_overview_v1')
  for (const k of ["'by_model_24h'", "'fallbacks_24h'", "count(*) filter (where i.outcome = 'failed') failures", 'count(*) filter (where i.attempt_no > 1) fallbacks, coalesce(sum(i.input_tokens), 0) tokens_in, coalesce(sum(i.output_tokens), 0) tokens_out', 'null::text evidence_href']) expect(o, k).toContain(k)
  // the worker side, run: one failed attempt then an answer gives two rows; a single-model call gives one and is returned as it came
  const { transformSync } = await import('esbuild')
  const out = `test-results/cascade-trace-${process.pid}.mjs`
  fs.mkdirSync('test-results', { recursive: true }); fs.writeFileSync(out, transformSync(fs.readFileSync(`${WORKER_DIR}/cascade.ts`, 'utf8'), { loader: 'ts', format: 'esm' }).code)
  const { cascadeFetch, takeAiTrace, failureKind } = await import(`${process.cwd()}/${out}`)
  const ok = { choices: [{ message: { content: '{"a":1}' }, finish_reason: 'stop' }], usage: { prompt_tokens: 10, completion_tokens: 5, cost: 0.001 } }
  const seq = (list) => { let i = 0; return async () => { const x = list[i++]; if (x.name) throw Object.assign(new Error('x'), { name: x.name }); return new Response(JSON.stringify(x.body), { status: x.status || 200 }) } }
  const init = { method: 'POST', body: JSON.stringify({ model: 'v/a', response_format: { type: 'json_object' } }) }
  takeAiTrace()
  let r = await cascadeFetch(seq([{ status: 503, body: {} }, { body: ok }]), { models: ['v/a', 'v/b'], service: 'fee_reader', source_id: 7 }, 'u', init)
  expect((await r.json()).cf_model_sent).toBe('v/b')
  expect(takeAiTrace()).toEqual([
    { service: 'fee_reader', model: 'v/a', attempt_no: 1, outcome: 'failed', failure_kind: 'http', input_tokens: null, output_tokens: null, cost: null, source: null, source_id: '7' },
    { service: 'fee_reader', model: 'v/b', attempt_no: 2, outcome: 'answered', failure_kind: null, input_tokens: 10, output_tokens: 5, cost: 0.001, source: null, source_id: '7' }])
  r = await cascadeFetch(seq([{ body: ok }]), { service: 'ops_diagnosis' }, 'u', init)
  expect(await r.json()).toEqual(ok)   // one model: the answer as it came
  expect(takeAiTrace()).toEqual([{ service: 'ops_diagnosis', model: 'v/a', attempt_no: 1, outcome: 'answered', failure_kind: null, input_tokens: 10, output_tokens: 5, cost: 0.001, source: null, source_id: null }])
  await expect(cascadeFetch(seq([{ name: 'TimeoutError' }]), { service: 'entry_matrices' }, 'u', init)).rejects.toThrow()
  expect(takeAiTrace().map((t) => `${t.outcome}:${t.failure_kind}`)).toEqual(['failed:timeout'])
  expect(['HTTP 500', 'cut answer', 'answer is not JSON', 'error: refused', 'empty answer', 'no choices'].map(failureKind)).toEqual(['http', 'cut', 'non_json', 'refused', 'empty', 'empty'])
  fs.rmSync(out, { force: true })
  expect(fixtures).toContain('ok 13 every model call attempt is kept with tokens and cost')
})

test('round 4: the prompt file is generated from the worker source and is not stale; the page read points to it and gives database prompts whole', async () => {
  const { build } = await import(`${process.cwd()}/scripts/ai-prompts-export.mjs`)
  const want = JSON.stringify(await build(), null, 2) + '\n'
  expect(fs.readFileSync('docs/platform/ai-prompts.json', 'utf8'), 'run: node scripts/ai-prompts-export.mjs').toBe(want)
  const j = JSON.parse(want)
  // every service whose prompt is written in the worker (or in the diagnosis function) has its full text with a sha256
  const routes = [...MIG.slice(MIG.indexOf('insert into pipeline.ai_service_routes'), MIG.indexOf('on conflict (service_code) do nothing;')).matchAll(/^  \('([a-z0-9_]+)', /gm)].map((m) => m[1])
  for (const svc of routes) expect(j.services, svc).toHaveProperty(svc)
  for (const [svc, v] of Object.entries(j.services)) for (const x of v.prompts) {
    expect(x.text.length, `${svc}/${x.name}`).toBeGreaterThan(100)
    expect(x.sha256, `${svc}/${x.name}`).toBe(crypto.createHash('sha256').update(x.text, 'utf8').digest('hex'))
  }
  expect(j.services.entry_requirements_v2_shadow.prompts).toEqual([])   // held in the database, given whole by the page read
  const o = fn2('public.admin_ai_overview_v1')
  expect(o).toContain("'text_ref', 'ai-prompts.json#' || r.service_code, 'sha256', null) end,")
  for (const t of ["'text', p.system_prompt, 'text_ref', null, 'sha256', encode(sha256(convert_to(p.system_prompt, 'UTF8')), 'hex')", "'text', p.text, 'text_ref', null, 'sha256', encode(sha256(convert_to(p.text, 'UTF8')), 'hex')",
    "'text', p.system_text, 'text_ref', null, 'sha256', encode(sha256(convert_to(p.system_text, 'UTF8')), 'hex')"]) expect(o, t).toContain(t)
  expect(o).not.toMatch(/left\(p\.(system_prompt|text|system_text), /)   // whole, not the first characters
  // the scholarship configuration is read here; its one write path stays public.admin_scholarship_ai
  expect(o).toContain("'write', 'public.admin_scholarship_ai'")
  expect(MIG2).not.toMatch(/create or replace function public\.admin_scholarship_ai\(/i)
})

test('round 4: roles, the mode on the page, and the documents (call paths, settings inventory, contract)', () => {
  const o = fn2('public.admin_ai_overview_v1')
  expect(o).toContain("if auth.uid() is null or v_rank < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;  -- rank 3 reads (no key details)")
  expect(o).toContain("'key', case when v_rank < 4 then jsonb_build_object('present', v_bal.observed_at is not null) else")
  for (const k of ["'can_admin'", "'mode'", "'enforcing'", "'would_hold_now'", "'would_hold_kind'", "'would_hold_reason'", "'migration_state'", "'qualification'", "'previous_model'", "'last_call'", "'recovery_state'", "'skipped'", "'config'", "'balance_max_age_minutes'"]) expect(o, k).toContain(k)
  // no reader of the two old model settings is left: the provider description run screen asks the route too
  const pd = body2('public.admin_provider_description_run_v1')
  expect(pd).not.toContain('ops.ai_diagnosis_model')
  expect((pd.match(/nullif\(security\.ai_route_v1\('ops_diagnosis'\)->>'model',''\)/g) || []).length).toBe(2)
  for (const m of [MIG, MIG2]) for (const b of [...m.matchAll(/(?:CREATE OR REPLACE FUNCTION|create or replace function) ((?:public|security)\.[a-z0-9_]+)\([\s\S]*?\$function\$;/g)])
    if (b[1] !== 'security.ai_settings_not_read_v1') expect(b[0].replace(/^\s*--.*$/gm, ''), b[1]).not.toMatch(/'(entry\.matrix_model|ops\.ai_diagnosis_model)'/)
  const paths = fs.readFileSync('docs/platform/AI-CALL-PATHS-2026-11-13.md', 'utf8')
  const lines = worker.split('\n')
  const sites = lines.map((l, i) => (l.includes('await cascadeFetch(') ? i + 1 : 0)).filter(Boolean)
  expect(sites).toHaveLength(15)
  for (const n of sites) expect(paths, `index.ts:${n}`).toContain(`index.ts:${n}`)   // every call the worker makes is listed at its line
  for (const t of ['admin_provider_description_run_v1', 'svc_entry_matrix_next', 'svc_ops_diagnosis_next', 'svc_enrich_ai_next', 'Layer 3', 'routed_single', 'not_migrated']) expect(paths, t).toContain(t)
  // only the worker calls OpenRouter
  const callers = fs.readdirSync('supabase/functions', { recursive: true }).map(String).filter((f) => f.endsWith('.ts') && fs.readFileSync(`supabase/functions/${f}`, 'utf8').includes('openrouter.ai/api'))
  expect(callers.map((f) => f.split(/[\\/]/)[0]).filter((v, i, a) => a.indexOf(v) === i)).toEqual(['coverage-sweep'])
  expect(doc.indexOf('## Changes for the UI (round 4)')).toBeGreaterThan(0)
  expect(doc.indexOf('## Changes for the UI (round 4)')).toBeLessThan(doc.indexOf('## Changes for the UI (round 3)'))
  for (const t of ['balance_unknown', 'balance_stale', 'no_qualified_model', 'would_hold_kind', 'enforcing', 'migration_state', 'routed_single', 'admin_ai_qualification_set_v1', 'by_model_24h', 'fallbacks_24h', 'ai-prompts.json', 'Who can do what']) expect(doc, t).toContain(t)
  const inv = fs.readFileSync('docs/platform/SETTINGS-INVENTORY-2026-11-13.md', 'utf8')
  for (const t of ['direct read', 'dynamic read', 'display only', 'none found', 'operator', 'models_services', 'engineering_default', 'retire_review', 'control_class']) expect(inv, t).toContain(t)
  expect((inv.match(/^\| `[a-z_0-9-]+` \| [^|]+ \| \d+ \| /gm) || []).length).toBe(78)   // one row per (toolset, section)
})

