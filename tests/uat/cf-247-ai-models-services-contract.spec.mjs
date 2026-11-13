// Guards: Platform Admin 13 Nov 2026 19:14 — one model list, service routes with cascade and caps, usage by model (AI spend control)
// CF-247 migration 20261113380000. "GPT 4.1 mini is too expensive it has exhausted the AI credit. use other cheaper model and define the usage per
// field in ui under Model and Services ... Model classified that can be used - Qwen3, Mimo, mistral small, Kimi K2, Gemini, LLama, deepseek and
// then Service based Model with cascading, Then Recent usage" and 19:15 "Keep prompt respective for each service as well"; 19:23 "stop the entry
// requirement or any other setting using GPT mini now. all settings corresponding to model using AI model/prompt or services should be defined
// in Model & services". The behaviour runs on isolated fixtures by tests/fixtures/ai-models-services/run.sh (scratch PostgreSQL 16; workflow
// ai-models-services-test.yml): this file checks the migration text, the fixture's claims and the page contract document.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const MIG = fs.readFileSync('supabase/migrations/20261113380000_cf247_ai_models_services.sql', 'utf8')
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
  for (const s of ['course_entry_requirements', 'entry_matrices', 'ops_diagnosis']) {   // the services that were on GPT-4.1 mini: qwen3-30b first, then a second allowed model
    const row = seed.slice(seed.indexOf(`('${s}'`)); expect(row.slice(0, row.indexOf('\n  (', 5) > 0 ? row.indexOf('\n  (', 5) : row.length), s).toContain("array['qwen3-30b', 'mistral-small-3.2']")
  }
  // caps are read from the existing settings, never written as a number
  expect(seed).not.toMatch(/array\[[^\]]+\], \d/)
  expect(seed).toContain("s.toolset_key = 'openrouter' and s.key = 'guard_entry_matrix'")
  expect(seed).toContain("s.toolset_key = 'pipeline' and s.key = 'ops.ai_diagnosis_usd_per_day'")
  // the course field reader is one route per field group, split by the item's field
  expect(seed).toContain(`'{"where": {"field": ["description"]}}'`)
  expect(seed).toContain(`'{"where": {"field": ["entry_requirements"]}}'`)
  expect(seed).toContain(`'{"where_not": {"field": ["description", "entry_requirements"]}}'`)
})

test('the route: allowed models in cascade order, held by the switch, the cascade, the daily ceiling and the caps, on the UTC day the guards count', () => {
  const r = fn('security.ai_route_v1')
  expect(r).toContain("join pipeline.ai_model_catalogue m on m.code = c.code and m.status = 'allowed'")
  expect(r).toContain('order by c.ord')
  expect(r).toContain("v_day timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';  -- fixed: the UTC day the AI guards count")
  expect(r).toContain("v_ceiling := security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14);")
  for (const reason of ['switched off (Models & services)', 'no allowed model in the cascade', 'daily ceiling: US$%s spent today (UTC) across all AI services', 'service cap: US$%s spent today (UTC), cap US$%s', 'service cap: %s calls today (UTC), cap %s'])
    expect(r, reason).toContain(reason)
  expect(r).not.toContain('platform_toolsets')   // held whatever the OpenRouter mode is (it was Observe only, so the ceiling stopped nothing)
  expect(r).toContain("'held_kind', case when v_reason is null then null when not r.enabled or jsonb_array_length(v_models) = 0 then 'off' else 'limit' end")
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
  expect(fn('security.ai_on_demand_providers_v1')).toContain("where r.state = 'open' and r.expires_at > now() and 'openrouter' = any (r.toolsets)")
  expect(body('public.svc_entry_matrix_next')).toContain("if v_model is null or v_route->>'held_kind' = 'off' or (coalesce((v_route->>'held')::boolean, true) and cardinality(v_od) = 0) then return '[]'::jsonb; end if;")
  expect(fixtures).toContain('an on-demand provider is not held by a limit, but is by a switch')
})

test('usage by service and model: two columns beside, filled by the one writer; a failure there never stops the cost being recorded', () => {
  expect(MIG).toContain('alter table pipeline.ai_spend_ledger add column if not exists service_code text;')
  expect(MIG).toContain('alter table pipeline.ai_spend_ledger add column if not exists model text;')
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
  expect(o).toContain("if auth.uid() is null or v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;")
  for (const w of [ms, rs]) {
    expect(w).toContain("if auth.uid() is null or security.current_role_rank() < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;")
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
  for (const s of ['admin_ai_overview_v1', 'admin_ai_model_set_v1', 'admin_ai_route_set_v1', "admin_toolsets_write('setting'", 'held_kind', 'model_in_effect', 'wired']) expect(doc, s).toContain(s)
})

test('settings that belong to Models & services are marked, not moved or hidden; GPT-4.1 mini leaves the scholarship chain', () => {
  expect(MIG).toContain('alter table pipeline.platform_toolset_settings add column if not exists home text;')
  expect(MIG).toContain('alter table pipeline.platform_toolset_settings add column if not exists home_group text;')
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
  expect(fixtures).toContain('central readers keep one model both ways')
  expect((fixtures.match(/raise notice 'ok \d /g) || []).length).toBe(7)
  expect(run).toContain('grep -c "NOTICE:  ok " <<<"$OUT")" = 7')
})
