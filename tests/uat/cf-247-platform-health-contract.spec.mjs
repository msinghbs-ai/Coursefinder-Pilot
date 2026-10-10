import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'

// CF-247 platform health (Platform Admin direction, 29 Sep 2026): the platform reports its own errors and issues.
// Source contract only: the migration was applied live and verified by md5(prosrc) against these files.
const MIGRATION='supabase/migrations-archive/20260929235000_cf247_platform_health.sql'
const STAGGER='supabase/migrations-archive/20260929235100_cf247_platform_health_probe_stagger.sql'
const CONTRACT="{generated_at, overall:'ok'|'warning'|'critical', counts:{critical,warning,info}, issues:[{id,check_key,severity,area,title,detail,first_seen,last_seen,occurrences,acknowledged_at}], checks:[{key,area,label,status:'ok'|'warning'|'critical'|'skipped',detail,checked_at}], history:[{day,critical,warning}]}"

test.describe('CF-247 platform health contract',()=>{
  test('issue store is deduplicated, private and limited to the agreed areas',async()=>{
    const sql=await fs.readFile(MIGRATION,'utf8')
    expect(sql).toContain('create unique index if not exists platform_issues_open_uq on pipeline.platform_issues(check_key) where resolved_at is null')
    expect(sql).toContain("severity in ('critical','warning','info')")
    expect(sql).toContain("area in ('scheduled jobs','edge functions','coverage sweep','admission','Layer 3','scholarships','budgets','search/API','storage/DB')")
    for(const t of ['platform_issues','platform_health_checks','platform_health_runs','platform_edge_calls'])
      expect(sql).toContain(`alter table pipeline.${t} enable row level security;`)
    expect(sql).toMatch(/revoke all on pipeline\.platform_issues, pipeline\.platform_health_checks, pipeline\.platform_health_runs, pipeline\.platform_edge_calls from public, anon, authenticated;/)
    expect(sql).not.toMatch(/grant [^;]* on (table )?pipeline\.platform_/i)
  })

  test('admin read contract is documented verbatim and dispatched through admin_read with an md5 guard',async()=>{
    const sql=await fs.readFile(MIGRATION,'utf8')
    expect(sql).toContain(CONTRACT)
    for(const k of ["'generated_at'","'overall'","'counts'","'issues'","'checks'","'history'","'acknowledged_at'","'occurrences'","'checked_at'"])
      expect(sql).toContain(k)
    expect(sql).toContain("16623bea0f6efec5f1678510079f8cc2")
    expect(sql).toContain("if p_operation='platform_health' then return security.admin_platform_health_v1(p_args); end if;")
    // CF-221 keys stay for the existing dashboard panel
    expect(sql).toContain('security.admin_platform_health_cf221() || security.platform_health_state_v1(v_rank>=4)')
  })

  test('acknowledge is a governed admin write (rank >= 5) and clears when severity rises',async()=>{
    const sql=await fs.readFile(MIGRATION,'utf8')
    expect(sql).toContain('create or replace function admin_api.platform_issue_acknowledge(p_issue_id uuid, p_note text default null)')
    expect(sql).toContain("if security.current_role_rank()<5 then raise exception 'pim_admin role required'")
    expect(sql).toContain('create or replace function public.platform_issue_acknowledge(p_issue_id uuid, p_note text default null)')
    expect(sql).toMatch(/acknowledged_at=case when \(case excluded\.severity/)
  })

  test('health run covers every agreed check, runs every 10 minutes and auto-resolves',async()=>{
    const [sql,stagger]=await Promise.all([fs.readFile(MIGRATION,'utf8'),fs.readFile(STAGGER,'utf8')])
    for(const key of ['cron','edge_calls','edge_deployed','coverage_queues','scholarship_queues','layer_queues','admission','budgets','db_capacity','search_probe','consumer_snapshot','reference_bundle','scholarship_review'])
      expect(sql).toContain(`security.platform_health_due_v1('${key}',p_force)`)
    expect(sql).toContain("select cron.schedule('platform-health','8-59/10 * * * *','select security.platform_health_check_v1()');")
    expect(sql).toContain("public.website_edge_course_search_v1('{}'::jsonb,1,5)")
    expect(sql).toContain('elsif v_num>3000 then')
    expect(sql).toContain('security.consumer_api_snapshot_v1()')
    expect(sql).toContain('net._http_response')
    expect(sql).toContain('security.layer2_provider_budget_status(p.id,1)')
    expect(sql).toMatch(/update pipeline\.platform_issues i set resolved_at=now\(\)/)
    // the edge-call log never blocks an outbound call
    expect(sql).toContain('exception when others then null;  -- never block an outbound call because of the health log')
    // at most one slow check per run; the search probe waits when the snapshot ran
    expect(sql).toContain("(p_force or not v_slow_used) and security.platform_health_due_v1('consumer_snapshot',p_force)")
    expect(stagger).toContain("'6f2ddb7ca454745251c8c4d94375d290'")
    expect(stagger).toContain("(p_force or not ('consumer_snapshot'=any(v_ok)))")
    const due=await fs.readFile('supabase/migrations-archive/20260929235200_cf247_platform_health_due_tolerance.sql','utf8')
    expect(due).toContain("'1bb34684b80dc8b8993fa8bdca3f4272'")
    expect(due).toContain("least(interval '3 minutes', make_interval(mins=>c.cadence_minutes)*0.3)")
  })

  test('daily update summary is plain text plus issues',async()=>{
    const sql=await fs.readFile(MIGRATION,'utf8')
    expect(sql).toContain('create or replace function security.platform_health_summary_v1()')
    expect(sql).toContain("'text',array_to_string(v_lines,E'\\n')")
  })
})

test('health budget check aligned with Layer 3 route guards and credit floor', async () => {
  const fs = await import('node:fs')
  const sql = fs.readFileSync('supabase/migrations-archive/20260930010000_cf247_health_openrouter_budget_align.sql', 'utf8')
  expect(sql).toContain('ba7d0e94c18314afc6e3d8bf5f7becce')
  expect(sql).toContain('US$14 combined daily ceiling')
  expect(sql).toContain("budgets:openrouter_credit")
})
