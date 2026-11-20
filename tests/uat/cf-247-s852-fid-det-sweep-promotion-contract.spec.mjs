// Guards: S852 deterministic fee, intake and deadline sweep and promotion (Platform Admin 20 Nov 2026 15:11 AEDT, chat S1-Fees-Intakes): a catalogued job with no number in its command, settings for every size and window, admission only through the governed write after quote, page identity, completeness, no-overwrite and manual lock checks, Layer 4 for fees that need a person, no new public object and no model.
// CF-247 s852. Migration 20261120175100.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const SQL = fs.readFileSync(migrationPath('20261120175100_cf247_s851_s852_fid_det_reader_and_sweep.sql'), 'utf8')
const fn = (name) => { const i = SQL.indexOf(`create or replace function ${name}(`); return SQL.slice(i, SQL.indexOf('$function$;', i)) }

test('the job is catalogued before it is scheduled and its command has no number', () => {
  expect(SQL.indexOf("('fid-det-sweep', 'Fees and intakes'")).toBeLessThan(SQL.indexOf("select cron.schedule('fid-det-sweep'"))
  expect(SQL).toContain("select cron.schedule('fid-det-sweep', '* * * * *', 'select security.fid_det_tick_v1()')")
  for (const k of ['fid.sweep_on', 'fid.run_every_minutes', 'fid.batch_size', 'fid.items_per_call', 'fid.reply_wait_minutes', 'fid.layer4_per_run', 'fid.deadline_past_days', 'fid.deadline_ahead_days'])
    expect(SQL).toContain(`('pipeline', '${k}', `)
  expect(SQL).toMatch(/'fid\.batch_size'[\s\S]*?to_jsonb\(150\), 100, 250, 'courses'/)
})

test('no new public object, no model, no Firecrawl: the worker is called read-only and its reply is read back from pg_net', () => {
  expect(SQL).not.toMatch(/create (or replace )?(function|view|table)( if not exists)? public\./i)
  for (const f of ['security.fid_det_tick_v1', 'security.fid_det_batch_v1', 'security.fid_det_record_v1']) expect(fn(f).replace(/--[^\n]*/g, '')).not.toMatch(/openrouter|firecrawl|ai_route|cascade/i)
  expect(fn('security.fid_det_tick_v1')).toContain("pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'fid_det_read'")
  expect(fn('security.fid_det_tick_v1')).toContain('from net._http_response where id = r.request_id')
  expect(fn('security.fid_det_tick_v1')).toContain("if v_call->>'extractor' is distinct from v_ext then raise exception")
})

test('the batch is an indexed keyset of 100 to 250 courses with a gap, in the fee reader scope, published, on the bound stored page', () => {
  const b = fn('security.fid_det_batch_v1')
  expect(b).toContain('where g.course_id > v_cur and g.status = \'bound\'')
  expect(b).toContain("s.key = 'fees.countries'")
  expect(b).toContain('security.provider_hidden_v1')
  expect(b).toContain('order by g.course_id')
  expect(b).toContain('v_lim int := greatest(1, least(coalesce(p_limit, 150), 250));')
  expect(b).toContain('limit v_lim * 4  -- fixed: a scan window')
  expect(b).not.toMatch(/or not exists \(select 1 from catalogue\.course_intakes/)
  expect(SQL).toContain("if v_ms > 300 then raise exception 'post-check: the batch query took % ms (limit 300)'")
})

test('fees: no overwrite, no lock, bound page identity, country tuition rule, one yearly figure in the country currency, governed write', () => {
  const r = fn('security.fid_det_record_v1')
  expect(r).toContain("elsif v_held then v_outcome := 'held_value'")
  expect(r).toContain("l.field = 'tuition'")
  expect(r).toContain("c.bound_ev is distinct from (pg->>'evidence_id')::uuid then v_outcome := 'identity'")
  expect(r).toContain("security.coverage_identity_allowed(c.provider_id, c.identity_basis, 'tuition')")
  expect(r).toContain("cardinality(v_annual) = 1 and (v_annual[1]->>'currency') = v_cur")
  expect(r).toContain("'fee_basis', 'annual'")
  expect(r).toContain('security.coverage_apply_course_v1(c.id, v_src')
  expect(r).not.toMatch(/insert into catalogue\.course_fees/)
})

test('fees that need a person go to Layer 4 with a reason in words, one pending item per course, capped by a setting', () => {
  const r = fn('security.fid_det_record_v1')
  expect(r).toContain("'provider_current_tuition_validation'")
  expect(r).toContain("'Deterministic fee reader: ' || v_reason || '. Please confirm the yearly international fee from the quoted page.'")
  expect(r).toContain("security.pipeline_num_v1('fid.layer4_per_run', 20)")
  expect(r).toContain("and l.field_code = 'provider_current_tuition_validation' and l.status = 'pending'")
})

test('intakes fill only an empty course; deadlines fill only an empty deadline of one intake inside its window, with the date in the closing clause', () => {
  const r = fn('security.fid_det_record_v1')
  expect(r).toContain("v_outcome := 'held_value'; v_reason := 'intakes are already held (no overwrite)'")
  expect(r).toContain("l.field = 'intakes'")
  expect(r).toContain("security.coverage_identity_allowed(c.provider_id, c.identity_basis, 'intakes')")
  expect(r).toContain("'source_intake_key', 'fid-det:'")
  expect(r).toContain("security.course_deadline_in_quote_v1(v_date, rd->>'quote')")
  expect(r).toContain("security.course_deadline_intake_match_v1(i.intake_label, i.intake_year, rd->>'intake_hint')")
  expect(r).toContain('update catalogue.course_intakes set application_deadline = v_date where id = v_targets[1] and application_deadline is null;')
  expect(r).toContain("v_outcome := 'rolling'")
})

test('search documents follow: the source is approved for the domains it feeds and one refresh is requested', () => {
  const r = fn('security.fid_det_record_v1')
  expect(r).toContain("select 'courses', 'provider_current_tuition', v_src, 'approved'")
  expect(r).toContain("select 'courses', 'course_intake', v_src, 'approved'")
  expect(r).toContain("insert into search.refresh_requests(requested_by) select 'deterministic fee, intake and deadline reader'")
})
