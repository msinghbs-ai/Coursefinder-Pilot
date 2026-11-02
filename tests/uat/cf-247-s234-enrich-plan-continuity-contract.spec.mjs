// Guards: Platform Admin direction 3 Nov 2026 09:32 (platform-led enrichment): work creation continues between plan cycles; manual and automatic runs share one mechanism
// Acceptance report 3 Nov 2026, engineering plan items 3 and 6 (controls audit defects 3, 4, 7, 8, 9, 10). Automatic plans can re-plan a
// university whose gaps grew (setting, ships off); the standing gap queue's cross-check reads each course once (60 s -> 25.6 s, measured);
// manual Enrich fields tasks follow the standing queue's in-flight and published rules; cancelling a plan cancels its tasks; retry and export
// in Enrich fields and Enrichment plan; spend estimates before Start and before Find scholarships now; Layer 2 Run on demand retired with a
// paste file. Run now never changes a recurring schedule. Behaviour runs on isolated fixtures by tests/fixtures/enrich-plan-continuity/run.sh
// (scratch PostgreSQL; seven live definitions checked against their live md5, the defect reproduced, the migration applied twice, the cases,
// and the paste file and rollback rehearsed on the measured ids).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261103120000_cf247_enrich_plan_continuity.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/enrich-plan-continuity'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const PASTE = fs.readFileSync('docs/paste/PASTE-20261103-layer2-refresh-requests-close.sql', 'utf8')
const ROLLBACK = fs.readFileSync('docs/paste/PASTE-20261103-layer2-refresh-requests-close-rollback.sql', 'utf8')
const read = (p) => fs.readFileSync(p, 'utf8')

test('each edited definition changes only from its live md5 and is checked after; the fixtures load the live text and check it first', () => {
  for (const [sig, before, after] of [
    ['security.field_crosscheck_v1()', '1023e1373007f09773d2d529d489e9ba', 'b8a5b2de244c277aa4b9e47547017dd7'],
    ['public.admin_enrich_fields(text,jsonb)', '184f74ae316051ec0cb4dd62c22b190d', '349584fc0e9b605e1067cbbd488e435a'],
    ['public.admin_enrich_plan(text,jsonb)', 'bd460fcd0e5b4e1dfd41ec1065c2a60c', '0c9d3ec1b7d043e2d9f3ac83f9d99e1d'],
  ]) { expect(m).toContain(`select pg_temp.edit_once('${sig}', '${before}', '${after}'`); expect(run).toContain(before); expect(run).toContain(after) }
  expect(m).toContain("select pg_temp.replace_once('security.enrich_plan_auto_v1()', 'f9409768bf82bbb29f17ce514c8f9b11', '2d8944d7624b90cbbefb9925d602c92b'")
  for (const f of ['public.admin_enrich_fields', 'public.admin_enrich_plan', 'security.enrich_plan_auto_v1', 'security.field_crosscheck_v1', 'security.enrich_plan_priority_v1',
    'security.enrich_plan_start_step_v1', 'security.enrich_unit_costs_v1']) expect(fs.existsSync(`${FX}/live/${f}.sql`)).toBe(true)
  expect(run).toContain("grep -c 'already applied' | grep -qx 4")
  // the defect, as live: a flat redo window, and a cancel that leaves the tasks
  expect(read(`${FX}/live/security.enrich_plan_auto_v1.sql`)).toContain("(r.mode = 'auto' and r.created_at > now() - make_interval(days => security.pipeline_num_v1('plans.redo_days', 14)::int))")
  expect(read(`${FX}/live/public.admin_enrich_plan.sql`)).toContain("return jsonb_build_object('cancelled', found);")
})

test('automatic plans re-plan a university whose gaps grew: capped an hour, after the due ones, never too soon; ships off', () => {
  expect(m).toMatch(/\('pipeline', 'plans\.replan_per_hour', [^\n]*\n[^\n]*\n\s*'number', '0'::jsonb, '0', '100', 'plans an hour'/)
  expect(m).toContain("v_re_max int := security.pipeline_num_v1('plans.replan_per_hour', 0)::int;")
  expect(m).toContain("or (v_re_max > 0 and l.created_at <= now() - make_interval(days => v_re_days) and x.missing >= l.missing_then + v_re_rise))")
  expect(m).toContain("continue when v_is_re and v_re_used + v_re >= v_re_max;")
  expect(m).toContain("order by (l.id is null or l.created_at <= now() - make_interval(days => v_redo)) desc,")
  for (const c of ['ok A1 shipped off', 'ok A2 on at 1 an hour', 'ok A3 the second run in the same hour re-plans nothing', 'ok A4 the next hour', 'ok A5 the automatic switch']) expect(fixtures).toContain(c)
})

test('the standing gap queue: the cross-check computes each course\'s readings and each parse once (the measured time-out)', () => {
  for (const s of ["where c.lifecycle_status = 'active' offset 0) x", "'')) d offset 0) p,", "'')) l offset 0) p", 'x.provider_id) m offset 0) p']) expect(m).toContain(s)
  expect(fixtures).toContain('ok H1 the edited cross-check finds exactly what the live one found')
})

test('manual and automatic work share the rules: in-flight items and unpublished providers are left out at Start and on retry', () => {
  expect(m).toContain("and not security.enrich_item_in_flight_v1(c.provider_id, c.id, f.x)")
  expect(m).toContain("and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)")
  expect(m).toContain("(select e.state in ('queued', 'waiting', 'ai', 'leased', 'review') from pipeline.field_enrich_items e")
  for (const c of ['ok C1 Start skips C1', 'ok C2 a chosen unpublished university', 'ok E1-E3 retry', 'ok E4 a second retry']) expect(fixtures).toContain(c)
})

test('cancel safely: the plan\'s running steps\' tasks are cancelled through their own controls, as the person behind the run', () => {
  expect(m).toContain("return jsonb_build_object('cancelled', true) || security.enrich_plan_cancel_steps_v1(v_id, coalesce(nullif(v_reason, ''), 'by a person'));")
  expect(m).toContain("perform public.admin_jobs('cancel', jsonb_build_object('id', s->'ref'->>'id', 'reason', 'Enrichment plan cancelled: ' || p_reason));")
  expect(m).toContain("perform public.admin_provider_onboarding('stop',")
  expect(m).toContain("perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);")
  expect(read(`${FX}/fixtures-before.sql`)).toContain("before (defect reproduced): the live cancel leaves the run''s task")
  for (const c of ['ok B1 cancel', 'ok B2', 'ok B3']) expect(fixtures).toContain(c)
})

test('retry, export and estimates reuse the existing RPCs and settings; the screens offer them at the screen\'s role', () => {
  for (const a of ["elsif p_action = 'retry' then", "elsif p_action = 'export' then", "elsif p_action = 'unit_costs' then"]) expect(m).toContain(a)
  expect(m).toContain("return public.admin_enrich_plan('run', jsonb_build_object('provider', v_pid, 'steps', v_steps,")
  expect(m).toContain("|| security.enrich_fields_estimate_v1(v_cc, v_pids, v_fields, coalesce((p_args->>'ai')::boolean, true), coalesce((p_args->>'scraper')::boolean, false));")
  for (const k of ['enrich.export_page_rows', 'enrich.retry_items_max', 'plans.export_days', 'plans.export_runs_per_page']) expect(m).toContain(`security.pipeline_num_v1('${k}'`)
  const ef = read('src/EnrichFields.jsx'), ep = read('src/EnrichPlan.jsx'), sa = read('src/ScholarshipActions.jsx')
  expect(ef).toContain("call('retry',{job_id:j.id,reason:reason.trim()})"); expect(ef).toContain("call('export',{job_id:j.id,after})"); expect(ef).toContain('data-enrich-estimate')
  expect(ef).toContain('{canRetry&&finished&&failed>0&&<Button')
  expect(ep).toContain("call('retry',{run_id:id,reason:reason.trim()})"); expect(ep).toContain("call('export',{provider:provider||'',offset})"); expect(ep).toContain('{p.can_run&&!open&&')
  expect(sa).toContain("supabase.rpc('admin_enrich_plan',{p_action:'unit_costs',p_args:{}})")
  for (const c of ['ok D1 preview estimate', 'ok D2', 'ok F1 export', 'ok G1 plan retry', 'ok G2', 'ok G3 plan export', 'ok G4-G5']) expect(fixtures).toContain(c)
})

test('Run now never changes a recurring schedule (mandate §6): plan Run now and retry, Automations Run now, Refresh schedules Run on demand', () => {
  // Enrichment plan: run and retry insert a manual run and start it; they never touch the automatic switch or a cron job
  const plan = m.slice(m.indexOf("select pg_temp.edit_once('public.admin_enrich_plan(text,jsonb)'"), m.indexOf('-- 9. housekeeping'))
  expect(plan).not.toMatch(/enrich_plan_control|cron\./)
  const live = read(`${FX}/live/public.admin_enrich_plan.sql`), runBlock = live.slice(live.indexOf("elsif p_action = 'run' then"), live.indexOf("elsif p_action = 'cancel' then"))
  expect(runBlock).not.toMatch(/enrich_plan_control|cron\./)
  expect(fixtures).toContain("if (select row(auto_enabled, owner, reason) from pipeline.enrich_plan_control) is distinct from v_ctl then raise exception 'G1: a Run now changed the automatic plans'")
  // Scheduled jobs › Automations › Run now: runs the job's command once; only set_every alters the cron schedule
  const autoMig = fs.readdirSync('supabase/migrations').filter((f) => f.endsWith('.sql')).sort().reverse()
    .map((f) => read(`supabase/migrations/${f}`)).find((s) => s.includes("p_action='run_now' then") && s.includes('admin_automation_control_v1'))
  const block = autoMig.slice(autoMig.indexOf("p_action='run_now' then"), autoMig.indexOf('elsif', autoMig.indexOf("p_action='run_now' then")))
  expect(block.replace(/\s+/g, ' ').trim()).toBe("p_action='run_now' then execute j.command;")
  // Refresh schedules › Run on demand: Layer 1 only now; the request it writes leaves the schedule as it was
  const ws = read('src/ScheduledJobsWorkspace.jsx')
  expect(ws).toContain('const runEligible=policy=>Number(policy?.layer)<=2&&!layer2Retiring(policy)&&Boolean(policy?.enabled)')
  expect(ws).toContain('does not change its recurring cadence or next-run time')
})

test('Layer 2 refresh schedules retire: marked retiring with replaced_by and retire_after; the paste closes the measured requests and switches the schedules off; nothing deleted', () => {
  expect(m).toContain("('screen', 'Scheduled jobs › Refresh schedules › Run on demand (Layer 2)'")
  expect(m).toContain("(now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date")
  expect(PASTE).toContain("if n_r <> 205 or m_r is distinct from 'af2e4ea5b84921f67b4ee7bdbbaf0382' then")
  expect(PASTE).toContain("if n_p <> 9 or m_p is distinct from 'de1f728ba4f8e6ca04420ea1e5ac2f42' then")
  expect(PASTE).toContain("set status = 'cancelled', completed_at = now(),")
  expect(PASTE).toContain("and trigger_type <> 'important_date'")
  for (const s of [PASTE, ROLLBACK]) expect(s).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
  expect(ROLLBACK).toContain("refused: already rolled back")
  expect(run).toContain('"206 c3a6579ae9eb22e751d0c5be11ea8cb6"')
  expect(run).toContain('ok paste rehearsal')
})
