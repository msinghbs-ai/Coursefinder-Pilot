// Guards: CF-247 s840 to s842 (session S1-ELR, Platform Admin 20 Nov 2026 15:10 and 15:21 AEDT): the English plan asks the course-group match only when a binding exists (same answer, md5-guarded live text); the English requirement sweep promotes a reading only through every gate (page identity, verbatim quote, agreement, completeness, no-overwrite insert, manual locks, audit sample), sends conflicts, shared pages and the audit sample to Layer 4, holds the rest with a reason, and keeps G1, G2 and G3 with $0 spend
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261120170000_cf247_s840_elr_det_reader_promotion.sql', 'utf8')
const fn = (name) => { const a = MIG.indexOf(`create or replace function ${name}(`); return MIG.slice(a, MIG.indexOf('$f$;', a)) }

test('housekeeping: replaces and retires lines, no drop, delete or truncate at top level, a comment on every new table', () => {
  expect(MIG).toMatch(/^-- Replaces: .+\.$/m)
  expect(MIG).toMatch(/^-- Retires: nothing\./m)
  expect(MIG).not.toMatch(/^(drop|delete|truncate)\b/im)
  for (const t of ['elr_det_state', 'elr_det_pages', 'elr_det_readings', 'elr_det_requests']) {
    expect(MIG).toContain(`create table if not exists pipeline.${t} (`)
    expect(MIG).toContain(`comment on table pipeline.${t} is 'CF-247 s842:`)
    expect(MIG).toContain(`revoke all on pipeline.${t} from public, anon, authenticated;`)
  }
})

test('s840: the plan function is replaced only over its md5-checked live text and answers the same plans', () => {
  expect(MIG).toContain("md5(pg_get_functiondef('security.provider_english_plan_v1(uuid)'::regprocedure)) <> '6fec9e6515a347438b7ed07215cbd748'")
  expect(MIG).toContain("case when c.grp in ('undergraduate', 'postgraduate') and v_has_bindings then security.english_group_match_v1(")
  expect(MIG).toContain("(case when v_other_bindings and m.grp in ('undergraduate', 'postgraduate') then exists (")
  expect(MIG).toContain("if v_h <> r.h then raise exception 'post-check: the English plan of proposal % changed'")
  expect(MIG).toContain("raise exception 'post-check: the written-out title key differs from security.english_title_key'")
})

test('s842: no new public object; every function is security definer with an empty search path and revoked from public', () => {
  expect(MIG).not.toMatch(/create (or replace )?(function|view|table)( if not exists)? public\./i)
  for (const f of ['security.elr_det_claim_v1', 'security.elr_det_record_v1', 'security.elr_det_sweep_tick_v1', 'security.elr_det_status_v1']) {
    expect(fn(f)).toMatch(/security definer set search_path to ''/)
    expect(MIG).toMatch(new RegExp(`revoke all on function ${f.replace('.', '\\.')}\\(`))
  }
})

test('s842: the writer promotes by insert only (no overwrite) and only after every gate', () => {
  const w = fn('security.elr_det_record_v1')
  expect(w).toContain('on conflict (course_id, english_test_id) do nothing;')
  expect(w).not.toMatch(/update catalogue\./i)
  for (const gate of ["security.coverage_identity_allowed(g.provider_id, g.ib, 'english')", 'security.page_refused_v1(v_course, g.url)',
    "security.layer4_entity_or_parent_blocked('course', v_course, 'operational')", "e.status = 'active') then 'course already holds an English requirement (no overwrite)'",
    "l.field in ('english', 'english_requirements', 'course_english')", "i.field_code = 'course_english' and i.status = 'pending'",
    'security.elr_det_quote_ok_v1(x.test_key, x.value, x.quote)', "bool_and(x.strength = 'stated_minimum')", 'count(distinct x.value) nv',
    "s.evidence_id = v_ev and s.status = 'bound') > 1", "abs(hashtext(v_course::text)) % 100 < v_audit"]) expect(w).toContain(gate)
  expect(w).toContain("insert into pipeline.layer4_review_items (entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, escalation_reason, change_control_ref)")
  expect(w).toContain('search.refresh_course_enrichment_scoped_v1(v_done, true)')
  expect(w).toContain("'pathway' = any (x.flags)")
})

test('s842: the sweep reads its answers back from pg_net, sends bounded calls to the read-only worker mode, and its job and settings follow G1 and G2', () => {
  const t = fn('security.elr_det_sweep_tick_v1')
  expect(t).toContain('join net._http_response h on h.id = r.id')
  expect(t).toContain("pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'elr_det_read', 'items', v_items))")
  expect(t).toContain("security.pipeline_num_v1('elr_det.in_flight_max', 8)")
  expect(t).toContain("security.pipeline_num_v1('batch.elr_det_sweep', 200)")
  expect(MIG).toContain("select cron.schedule('elr-det-sweep', '2-59/5 * * * *', 'select security.elr_det_sweep_tick_v1()')")
  expect(MIG).toContain("insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values\n ('elr-det-sweep'")
  for (const k of ['batch.elr_det_sweep', 'elr_det.pages_per_call', 'elr_det.in_flight_max', 'elr_det.audit_pct', 'elr_det.promote_on', 'elr_det.sweep_on', 'elr_det.request_lost_minutes'])
    expect(MIG).toContain(`('pipeline', '${k}', `)
})

test('G3 and safety: the consumer API is checked before and after, manual locks are compared, no model or Firecrawl call', () => {
  expect((MIG.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect((MIG.match(/<> 75/g) || []).length).toBe(2)
  expect((MIG.match(/<> 48/g) || []).length).toBe(2)
  expect(MIG).toContain("raise exception 'post-check: the manual locks changed")
  expect(MIG).not.toMatch(/openrouter|firecrawl_|fc_run|enrich_ai/i)
})
