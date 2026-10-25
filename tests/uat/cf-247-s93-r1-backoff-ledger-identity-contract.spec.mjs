// Guards: CF-247 R1 (Platform Admin 24 Oct 2026 09:55 "R1, for real this time"): Q2 backoff cap and per-lane waiting tests, Q3 per-mode ledger, Q4 why-idle line and the companion…
// CF-247 R1 (Platform Admin 24 Oct 2026 09:55 "R1, for real this time"): Q2 backoff cap and per-lane waiting tests, Q3 per-mode
// ledger, Q4 why-idle line and the companion data-file fix, the apply-time identity check. Contracts on the migration, worker and screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261024004000_cf247_r1_backoff_ledger_identity.sql', 'utf8')
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const q = fs.readFileSync('src/QueueWatch.jsx', 'utf8')

test('Q2: the trial wait is capped by a setting and every paused-prone lane says when work waits (md5-guarded edits, no worker change)', () => {
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: /m); expect(m).not.toMatch(/^\s*(drop|truncate)\b/im)
  expect(m).toContain(`'tick.backoff_max_minutes', 'Idle lane: tried again within'`)
  expect(m).toContain(`'number', '15'::jsonb, '1', '60', 'minutes', 770, 'Waste rules', 'security.flag_jobs_v1'`)
  expect(m).toContain("select pg_temp.edit_n('security.flag_jobs_v1()', '48031e060996ce062287c52b433e8f0d', array[")
  expect(m).toContain("make_interval(mins => security.pipeline_num_v1('tick.backoff_max_minutes', 15)::int)));")
  expect(m).toContain("<> '92da330ef4d63c0127a4cba236caba6f' then")
  for (const mode of ['read', 'link_search', 'provider_facts', 'ai_match', 'reidentify', 'discover', 'find_site', 'central_find', 'contact_page', 'logo_find', 'companion_read', 'source_find', 'programme_read'])
    expect(m).toContain(`when '${mode}' then exists (`)
  expect(m).toContain('else false end')
})

test('Q3: the ledger table is commented, RLS on, written by a service-role report function, kept by a catalogued retention job; queue wait per lane', () => {
  expect(m).toContain('create table if not exists pipeline.mode_outcome_ledger (')
  expect(m).toContain('comment on table pipeline.mode_outcome_ledger is')
  expect(m).toContain('alter table pipeline.mode_outcome_ledger enable row level security;')
  expect(m).toContain('create or replace function public.svc_worker_report_v1(p_mode text, p_status int, p_ms int, p_body jsonb, p_worker text) returns bigint')
  expect(m).toContain("if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;")
  expect(m).toContain('grant execute on function public.svc_worker_report_v1(text, int, int, jsonb, text) to service_role;')
  expect(m).toContain(`'retention.mode_outcome_ledger_days', 'Worker ledger: kept for'`)
  expect(m.indexOf("insert into pipeline.automation_catalogue(jobname")).toBeLessThan(m.indexOf("select cron.schedule('ledger-retention'"))
  expect(m).toContain("select cron.schedule('ledger-retention', '37 3 * * *', $$select security.ledger_retention_v1()$$);")
  expect(m).toContain('create or replace function security.lane_queue_wait_v1(p_hours int default 24)')
  for (const lane of ['fee_reader', 'enrich_fields', 'course_page_read', 'ai_page_match', 'course_page_search', 'central_ai']) expect(m).toContain(`'${lane}'`)
})

test('Q4: why-idle line on every work queue; the Sydney companion data files get their attempts back (count-guarded)', () => {
  expect(m).toContain('alter table pipeline.queue_watch add column if not exists upstream_key text references pipeline.queue_watch(key);')
  expect(m).toContain('create or replace function security.lane_why_idle_v1(p_key text) returns text')
  expect(m).toContain("select pg_temp.edit_n('public.admin_queue_watch(text,jsonb)', 'e2e9b8c9186590363acee4248973bd91', array[")
  expect(m).toContain("'why_idle', security.lane_why_idle_v1(w.key))")
  expect(m).toContain("if n <> 219 then raise exception")
  expect(q).toContain('{q.why_idle&&<small className="qw-sub" data-why-idle>{q.why_idle}</small>}')
})

test('apply-time identity check: the common fee write quarantines a fee from a page whose proof the country refuses; manual exempt; floor row untouched', () => {
  expect(m).toContain("select pg_temp.edit_n('security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)', 'd6287accb0ee955048978427b59c1ca2', array[")
  expect(m).toContain("and p.identity_basis <> 'manual' and not security.coverage_identity_allowed(c.provider_id, p.identity_basis, 'tuition') limit 1;")
  expect(m).toContain("jsonb_build_object('source', 'identity_basis_reverify', 'state', 'quarantined', 'country', v_cc, 'identity_basis', v_ident, 'page', v_ident_url)")
  expect(m).toContain("'fee_quarantined_identity', v_ident is not null);")
  expect(m).toContain("if v_floor <> -1 and not exists (select 1 from pipeline.layer4_review_items l")
})

test('worker v0.46.0: every call reports to the ledger after the answer is built; a .json address answering with HTML is read as the page', () => {
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(4[6-9]|[5-9]\d)\.\d+";/) // v0.46.0 or later
  expect(w).toContain('const res = await handle(req);')
  expect(w).toContain('await cr.rpc("svc_worker_report_v1", { p_mode: modeOf, p_status: res.status, p_ms: Date.now() - tStart, p_body: body, p_worker: WORKER });')
  expect(w).toContain('async function handle(req: Request): Promise<Response> {')
  expect(w).toContain('if (r.ok && (isJson ? /json|html/i : /html/i).test(r.headers.get("content-type") || (isJson ? "json" : "html"))) html = await r.text(); else await r.body?.cancel();')
  expect(w.indexOf('const res = await handle(req);')).toBeLessThan(w.indexOf('await cr.rpc("svc_worker_report_v1"'))
})
