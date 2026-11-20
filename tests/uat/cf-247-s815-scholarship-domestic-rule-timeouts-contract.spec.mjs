// Guards: CF-247 s815 (Platform Admin 20 Nov 2026 09:55, chat S1-Build): domestic-only scholarships refused by rule ($0); the scholarship classifier
// (IQ-00239 / IQ-00241) and the full scholarship attribute sync (IQ-00613) finish within their run without time-outs
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261120112000_cf247_s815_scholarship_domestic_rule_and_timeouts.sql', 'utf8')
const body = (name) => { const a = MIG.indexOf(`create or replace function ${name}(`); expect(a).toBeGreaterThan(-1); return MIG.slice(a, MIG.indexOf('$f$;', a)) }

// the same three tests as security.scholarship_domestic_quote_v1, from the settings' default patterns (JS regex \b for \m and \M)
const toJs = (p) => new RegExp(p.replace(/\\m|\\M/g, '\\b'), 'i')
const list = (key) => JSON.parse(MIG.match(new RegExp(`'${key.replace('.', '\\.')}'[\\s\\S]*?'(\\[[^']*\\])'::jsonb`))[1].replace(/\\\\/g, '\\\\')).map(toJs)
const phrases = list('sch_dom.phrases'), intl = list('sch_dom.international_words'), notOnly = list('sch_dom.not_exclusive_words')
const domestic = (q) => !intl.some((r) => r.test(q)) && !notOnly.some((r) => r.test(q)) && phrases.some((r) => r.test(q))

test('the domestic-only patterns refuse domestic-only quotes and leave every international, preference or exclusion quote for a person', () => {
  for (const q of ['this scholarship is offered to commencing Indigenous Australian students of exceptional research potential',
    'Open to Aboriginal and Torres Strait Islander Students Only', 'be Australian citizens or have permanent Australian resident status',
    'Australian citizens and permanent residents only', 'domestic students only', 'you must be: a First Nations Australian citizen'])
    expect(domestic(q), q).toBe(true)
  for (const q of ['Preference will be given to Canadian Citizens.', 'Open to Canadian citizens. Open to foreign nationals holding Canadian study permits.',
    'For citizens of any South Pacific Nation (excluding New Zealander and Australian citizens)', 'Be a citizen of a country other than Australia or New Zealand.',
    'open to both domestic and international applicants', 'international students may apply', 'To be eligible applicants must be Female'])
    expect(domestic(q), q).toBe(false)
})

test('the rule refuses through the same decision as the Layer 4 choice, keeps the quote, records domestic_only and spends nothing', () => {
  const r = body('security.scholarship_domestic_rule_v1')
  expect(r).toContain("perform security.scholarship_ai_review_apply_v1(rw.id, 'refuse', rw.ext_id, left('Not for international students (rule sch-domestic-v1): the page says \"' || rw.q || '\"', 600), null);")
  expect(r).toContain("set admit_reasons = array['domestic_only']")
  expect(r).toContain("values ('scholarship_rule', 'domestic_refuse', 'held_scholarship:' || rw.id,")
  expect(r).toContain("coalesce(x.answer->>'audience', '') <> 'international' and coalesce(v.recheck->>'audience', '') <> 'international'")
  expect(r).not.toMatch(/net\.http|svc_pilot_submit|openrouter|firecrawl/i)
  expect(MIG).toContain("values ('scholarship-domestic-rule', null, 'select security.scholarship_domestic_rule_v1()', md5('select security.scholarship_domestic_rule_v1()'), '3-59/10 * * * *'")
})

test('the classifier: set-based universities and eligibility, the host list read once, a candidate budget, and the snapshot on its own target', () => {
  expect(MIG).toContain("$n$with univ as materialized (select u.id from security.scholarship_university_ids_v1() u(id)),  -- s815: worked out once$n$")
  expect(MIG).toContain('elig as materialized (select e.provider_id, e.eligible from security.fc_sch_eligible_ids_v1(array(select pop.id from pop)) e)')
  expect(MIG).toContain("$o$security.third_party_host_v1(coalesce(c.url, '')) dir$o$")
  expect(MIG).toContain("where z.n = 1 or z.cum <= security.pipeline_num_v1('sch_cov.classify_candidate_budget', 1500);")
  expect(MIG).toContain("values ('scholarship-coverage-snapshot', null, 'select security.scholarship_provider_coverage_refresh_v1()'")
  for (const s of ["raise exception 'post-check: the university test differs for % providers'", "raise exception 'post-check: eligibility differs for % providers'",
    "raise exception 'post-check: the classifier''s cases changed for the same 30 providers'", "if v_cms > 20000 then raise exception 'post-check: the classifier took % ms'"])
    expect(MIG).toContain(s)
})

test('the full attribute pass works in chunks within its time budget and keeps its place', () => {
  const a = MIG.indexOf('create or replace function security.scholarship_course_attribute_sync_v1(')
  const f = MIG.slice(a, MIG.indexOf('$function$;', a))
  expect(f).toContain("v_budget numeric := security.pipeline_num_v1('sch_attr.full_run_seconds', 60);")
  expect(f).toContain("while v_cur is not null and extract(epoch from clock_timestamp() - v_t0) < v_budget loop")
  expect(f).toContain('update pipeline.scholarship_attribute_sync set full_cursor = v_cur, full_done = full_done + v_fn')
  expect(MIG).toContain("if md5(replace(pg_get_functiondef('security.scholarship_course_attribute_sync_v1(boolean)'::regprocedure), chr(13), '')) <> 'b01031c801e770fd1c30e691ab06fb01' then")
})
