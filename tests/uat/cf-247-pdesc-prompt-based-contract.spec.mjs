// Guards: F-PDESC prompt-based provider descriptions (Platform Admin 11 Nov 2026 14:51 "prompt based ... easily modified rather than stringent rules" and 14:57 "simple button for operators, the Platform Admin maintains the prompt in the settings, on demand has no applicable limits, the regular scan honours the Firecrawl and AI limits, a description written by hand is never replaced")
// Source contract for migration 20261112010000, worker coverage-sweep v0.69.0 and the screens, plus the worker's passage check run on a real page
// text. The migration's guarded replacements were dry-run against the live bodies (every anchor once, every function compiled, all rolled back)
// before merge; the live result is the release controller's check after deploy. Nothing here claims to have exercised the live database.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { promptSentences, promptRequest, PROMPT_SCHEMA } from '../../supabase/functions/coverage-sweep/description.ts'

const MIG = fs.readFileSync('supabase/migrations/20261112010000_cf247_pdesc_prompt_based.sql', 'utf8')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const read = (f) => fs.readFileSync(f, 'utf8')

test('the prompt is kept in the database, versioned, one active, and edited only as a new version by the Platform Admin with a reason', () => {
  expect(MIG).toContain('create table if not exists pipeline.provider_description_prompts (')
  expect(MIG).toContain('comment on table pipeline.provider_description_prompts is')
  expect(MIG).toContain("create unique index if not exists provider_description_prompts_one_active on pipeline.provider_description_prompts ((true)) where status = 'active';")
  expect(MIG).toContain("if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required'")
  expect(MIG).toContain("if length(v_reason) < 4 then raise exception 'a reason is required'; end if;")
  expect(MIG).toContain("update pipeline.provider_description_prompts set status = 'retired' where status = 'active';")  // a save is a new version, never an edit in place
  expect(MIG).toContain("'pdesc.prompt_on'")  // one switch back to the built-in prompt v2
  expect(MIG).toContain("'version', 'provider-description-p' || p.version")
})

test('every edited function is guarded by its reviewed live md5 and each replacement must find its anchor exactly once', () => {
  for (const [fn, md5] of [['security.provider_description_validate_v1', 'd4a4d31a8786a84fe18c28022f68a398'], ['public.svc_provider_description_next', '82bfe2daae5c95059ada6aa6305e0dde'],
    ['public.svc_provider_description_reserve_v1', 'bcd9bec36a7dcf106d0976a1a7ec896b'], ['public.svc_fc_spend', 'ee400f93352eef2be4158d4edacdc716'],
    ['security.fc_purpose_group_v1', '8041bf166d40460f8b255ed0bcbc8312'], ['security.provider_description_self_heal_v1', 'aaca6407c251641c164a10352abcfcfd'],
    ['security.provider_description_fire_v1', 'c6a9ed0a39d68ee2e88500e771e047c8']]) {
    expect(MIG, fn).toContain(md5)
    expect(MIG, fn).toContain(fn)
  }
  expect(MIG).toContain("if (length(d) - length(replace(d, p_old, ''))) / length(p_old) <> 1 then raise exception")
})

test('on demand: the operator Fill is not held by the lane AI ceiling, the lane daily guard, the Firecrawl allowance or share, or the failed-page memory', () => {
  expect(MIG).toContain('create or replace function public.admin_provider_description_fill_v1(p_provider_ids uuid[])')
  expect(MIG).toContain("if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'An operator is required'")
  expect(MIG).toContain("jsonb_build_object('on_demand', jsonb_build_object('by', auth.uid(), 'at', now()))")
  expect(MIG).toContain("perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_description'")  // the read starts at once
  expect(MIG).toContain("and not v_od then return jsonb_build_object('idle', true, 'reason', 'ai_ceiling'")
  expect(MIG).toContain("if v_spent+v_reserved+p_max_cost>v_cap and not security.pdesc_on_demand_live_v1(r.checks) then")
  expect(MIG).toContain("if v_today+v_reserved+p_max_cost>v_daily and not security.pdesc_on_demand_live_v1(r.checks) then")
  // the lane's own daily guard is not applied to on demand; the platform-wide rule (credit floor, platform daily ceiling) is
  expect(MIG).toContain("security.ai_use_allowed_v1(case when security.pdesc_on_demand_live_v1(r.checks) then 'provider_description_on_demand' else 'provider_description' end)")
  expect(MIG).toContain("security.ai_use_allowed_v1(case when security.pdesc_on_demand_due_v1() then 'provider_description_on_demand' else 'provider_description' end)")
  expect(MIG).toContain("elsif p_purpose = 'provider_description_on_demand' then")
  expect(MIG.indexOf("elsif security.fc_month_refusal_v1(p_units) is not null")).toBe(-1)  // the monthly plan limit stays first in svc_fc_spend (not edited)
  expect(MIG).toContain("if not security.pdesc_on_demand_live_v1(r.checks) and not coalesce((security.ops_learning_retry_check_v1(")
  expect(MIG).not.toContain('credit_floor')  // the platform-wide rule itself (security.ai_use_refusal_v1) is not edited
  // on demand never stalls the regular scan: its priority lasts pdesc.on_demand_minutes, and a provider that cannot be read is told so, not queued
  expect(MIG).toContain("make_interval(mins => security.pipeline_num_v1('pdesc.on_demand_minutes', 15)::int)")
  // a mark counts only within the window (QA 11 Nov 2026 B1): every exemption asks security.pdesc_on_demand_live_v1, never the bare mark
  expect(MIG).toContain('create or replace function security.pdesc_on_demand_live_v1(p_checks jsonb) returns boolean')
  expect(MIG.match(/checks \? 'on_demand'/g)).toHaveLength(1)  // only inside the helper itself
  expect(MIG).toContain("and x.tries < security.pipeline_num_v1('pdesc.tries', 3)")
  expect(MIG).toContain("then v_word := 'identity';")
  expect(MIG).toContain("then v_word := 'not_live';")
  expect(MIG).toContain('-- a new read: earlier reads stay as they are (the admission ledger refers to them)')
})

test('a description written by hand is never replaced: Fill skips a manual lock, and the lease and record keep their existing lock checks', () => {
  expect(MIG).toContain("l.field in ('description', 'p_description', 'all')) then v_word := 'manual';")
  expect(MIG).not.toContain('delete from pipeline.manual_locks')
  expect(MIG).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('the prompt profile keeps the checks a machine applies reliably and leaves the wording to the prompt; prompt off is exactly as before', () => {
  expect(MIG).toContain("v_light boolean := security.pipeline_num_v1('pdesc.prompt_on', 0) >= 1;")
  expect(MIG).toContain("'rule', 'refused_topic'")
  expect(MIG).toContain("'rule', 'first_sentence_no_name'")
  expect(MIG).toContain("security.pipeline_num_v1('pdesc.prompt_support_min_share', 0.5)")
  for (const kept of ["if not v_light and exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.superlatives')",
    "if not v_light and exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.claim_words')",
    "if not v_light and exists(select 1 from generate_series(", "if not v_light and coalesce(s->>'quote','')~* "]) expect(MIG).toContain(kept)
  expect(MIG).toContain("section = 'Provider descriptions › built-in prompt only'")
})

test('a new prompt is new knowledge: the lease stamps the active version and self-heal reads failed answers again once', () => {
  expect(MIG).toContain("prompt_version = coalesce(v_pv, r.prompt_version)")
  expect(MIG).toContain("coalesce(v_pv,c.prompt_version,'provider-description-v2')")
  expect(MIG).toContain("reason = 'put back: a new provider-description prompt (' || v_pv || ')'")
  expect(MIG).toContain("'pdesc.prompt_reoffer_rules'")
})

test('worker v0.69.0 uses the prompt the lease hands over, stamps its version and spends on-demand Firecrawl under its own purpose', () => {
  expect(IX).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(69|[7-9]\d)\.\d+";/)
  expect(IX).toContain('prompt_version: prompt ? prompt.version : DESCRIPTION_PROMPT_VERSION')
  expect(IX).toContain('const buildRequest = (it: any, rec: any, page: string) => prompt ? promptRequest(model, prompt.system,')
  expect(IX).toContain('answer: promptSentences(ans.a, page, minQuote)')
  expect(IX).toContain('const g = await useFcWhy("provider_description_on_demand", it.provider_id, url, true);')
  expect(IX).toContain('const g = await useFcWhy("provider_description", it.provider_id, url, true);')  // the regular scan keeps its Firecrawl budget
  const req = promptRequest('openai/gpt-4.1-mini', 'x'.repeat(200), 'Example University', 'https://example.edu/about', 'page', 1500)
  expect(req.provider).toEqual({ require_parameters: true })  // pinned: one model, never a router
  expect(req.response_format.json_schema.schema).toEqual(PROMPT_SCHEMA)
})

test('a sentence counts as on the page only when every supporting passage is on the page', () => {
  const page = 'The University of Sydney was founded in 1850 on the land of the Gadigal people. It has campuses in Camperdown, Darlington and Westmead. Celebrating 175 years.'
  const a = { sentences: [
    { text: 'The University of Sydney is a university founded in 1850 on Gadigal land.', sources: ['The University of Sydney was founded in 1850 on the land of the Gadigal people.'] },
    { text: 'It has campuses in Camperdown and Westmead.', sources: ['It has campuses in Camperdown, Darlington and Westmead.', 'Celebrating 175 years.'] },
    { text: 'It ranks in the top 20.', sources: ['It ranks 18th in the world.'] }], reason: '' }
  const out = promptSentences(a, page, 10)
  expect(out.about_page).toBe(true)
  expect(out.sentences.map((s) => s.on_page)).toEqual([true, true, false])
  expect(out.sentences[1].quote).toBe('It has campuses in Camperdown, Darlington and Westmead. … Celebrating 175 years.')
  expect(promptSentences({ sentences: [], reason: 'a login page' }, page).about_page).toBe(false)
})

test('the screens: the prompt card on Models & services › AI, Fill description in the panel, and Run & Validate retired from Enrich fields', () => {
  const card = read('src/ProviderDescriptionPrompt.jsx'), cov = read('src/FieldCoverage.jsx'), panel = read('src/ProviderFillFields.jsx'), main = read('src/mature-main.jsx')
  expect(main).toContain('{rank>=4&&<ProviderDescriptionPrompt onError={err}/>}')
  expect(card).toContain("supabase.rpc('admin_provider_description_prompt_v1', { p_action: 'save', p_args: { system_prompt: text, reason } })")
  expect(card).toContain("reason.trim().length < 4")
  expect(card).toContain('data-pdesc-status')  // AI spend, Firecrawl use, controls and progress (Platform Admin 11 Nov 2026 06:11)
  expect(cov).not.toContain('ProviderDescriptionRunValidate')
  expect(cov).toContain('<ProviderDescriptionStatus state={st}/>')
  expect(panel).toContain('data-fill-now')
  expect(panel).toContain('const data = await fillClient.fill(fillable.map(c => c.p.provider_id))')
  expect(panel).not.toMatch(/supabase\.(rpc|from)\(/)  // the panel reaches the database through its service module only
  expect(MIG).toContain("('screen', 'ProviderDescriptionRunValidate', 'Layer 2', 'Provider descriptions', 'Run & Validate card (cohort preview, prepare, run)', 'retiring'")
})
