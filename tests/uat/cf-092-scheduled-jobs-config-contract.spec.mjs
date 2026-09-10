import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const read=path=>fs.readFileSync(path,'utf8')

test.describe('CF-092 Scheduled Tasks configuration contract',()=>{
  test('native browser surface preserves governed reads, primary navigation and bounded action boundaries',()=>{
    const [workspace,legacy,client,shell,navUat]=['src/ScheduledJobsWorkspace.jsx','src/m2-3-intelligence-entry.jsx','src/lib/supabase.js','src/mature-main.jsx','tests/uat/admin-navigation-deployed.spec.mjs'].map(read)
    expect(legacy).toContain("import ScheduledJobsWorkspace from'./ScheduledJobsWorkspace'")
    expect(legacy).toContain('export const Refresh=ScheduledJobsWorkspace')
    expect(workspace).toContain('api.jobs(50)')
    expect(workspace).toContain("supabase.rpc('scheduler_policy_edit_v1'")
    expect(workspace).toContain("supabase.rpc('scheduler_policy_run_now_v1'")
    expect(workspace).toContain('localDateTime')
    expect(workspace).toContain('168:00:00')===false
    expect(workspace).toContain("Data Operations · Scheduled Tasks")
    expect(workspace).not.toContain("supabase.rpc('refresh_policy_upsert_v2'")
    expect(workspace).not.toContain('scheduler_policy_control')
    expect(workspace).not.toMatch(/supabase\.from\s*\(/)
    expect(client).toContain("adminRead('jobs'")

    const dataOps=shell.match(/\['Data Operations',\[(.*?)\]\],/s)?.[1]||''
    expect(dataOps).toContain("item('Scheduled Tasks',Clock3,4)")
    expect(dataOps.indexOf("item('Scheduled Tasks',Clock3,4)")).toBeLessThan(dataOps.indexOf("item('Evidence',BookOpen,3)"))
    expect(shell).toContain("if(page==='Scheduled Tasks'&&rank>=4)")
    expect(shell).not.toContain("{key:'scheduling',label:'Scheduling'")
    expect(shell).not.toContain("tool==='scheduling'")
    expect(shell).not.toContain("item('Refresh & Scheduling'")
    expect(navUat).toContain("clickPrimaryNav(page,'Scheduled Tasks')")
    expect(navUat).not.toContain("getByRole('tab',{name:'Scheduling',exact:true}).click()")

    for(const label of ['Scheduled Jobs & Run Control','Schedule Configuration','Scheduled Target','Freshness Policy','Cadence','Next Run','Schedule Status','Latest Refresh Queue','Recent Job Runs','Edit schedule','Run on demand'])expect(workspace).toContain(label)
    for(const route of ['#layer-1-operations','#layer-2-enrichment','#layer-3-ai-interpretation','#jobs','#evidence'])expect(workspace).toContain(route)
    expect(workspace).toContain('Historical Jobs are never reset or replayed')
    expect(workspace).toContain('does not change its recurring cadence or next-run time')
    expect(read('index.html')).not.toContain('scheduled-jobs-config-entry.js')
  })

  test('scheduler mutation migration persists audit and keeps public wrappers invoker-only',()=>{
    const m=read('supabase/migrations/20260910202500_cf_092_scheduler_governed_actions.sql')
    expect(m).toContain('pipeline.refresh_policy_action_events')
    expect(m).toContain("action in ('edit_schedule','run_on_demand')")
    expect(m).toContain('actor_id uuid not null')
    expect(m).toContain("change_control_ref text not null default 'CF-CHG-20260910-092'")
    expect(m).toContain('alter table pipeline.refresh_policy_action_events enable row level security')
    expect(m).toContain('refresh_policy_action_events_deny_authenticated')
    expect(m).toContain('security.scheduler_policy_edit_v1_browser_bridge')
    expect(m).toContain('security.scheduler_policy_run_now_v1_browser_bridge')
    expect(m).toContain('security definer')
    expect(m).toContain("set search_path=''")
    expect(m).toContain('auth.uid()')
    expect(m).toContain('security.current_role_rank() < 4')
    expect(m).toContain("raise exception 'bounded target required'")
    expect(m).toContain("'manual_governed','queued',v_actor,'CF-CHG-20260910-092'")
    expect(m).toContain("'run_on_demand',trim(p_reason),v_actor")
    expect(m).toContain("jsonb_build_object('policy_unchanged',true,'request_id',v_request_id)")
    expect(m).toContain('create or replace function public.scheduler_policy_edit_v1')
    expect(m).toContain('create or replace function public.scheduler_policy_run_now_v1')
    expect(m).toContain('security invoker')
    expect(m).toContain('from public,anon')
    expect(m).toContain('to authenticated,service_role')

    const runNow=m.slice(m.indexOf('create or replace function security.scheduler_policy_run_now_v1_browser_bridge'),m.indexOf('revoke all on function security.scheduler_policy_edit_v1_browser_bridge'))
    expect(runNow).not.toMatch(/update\s+pipeline\.refresh_policies/i)
    expect(runNow).not.toMatch(/delete\s+from\s+pipeline\.jobs/i)
    expect(runNow).not.toMatch(/update\s+pipeline\.jobs/i)
    expect(runNow).not.toMatch(/truncate\s+(table\s+)?pipeline\.jobs/i)
  })
})
