import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const read=path=>fs.readFileSync(path,'utf8')

test.describe('CF-092 Scheduled Tasks configuration contract',()=>{
  test('native browser surface preserves governed reads, primary navigation and bounded mutation boundaries',()=>{
    const [workspace,legacy,client,shell]=['src/ScheduledJobsWorkspace.jsx','src/m2-3-intelligence-entry.jsx','src/lib/supabase.js','src/mature-main.jsx'].map(read)
    expect(legacy).toContain("import ScheduledJobsWorkspace from'./ScheduledJobsWorkspace'")
    expect(legacy).toContain('export const Refresh=ScheduledJobsWorkspace')
    expect(workspace).toContain('api.jobs(50)')
    expect(workspace).toContain("supabase.rpc('refresh_policy_upsert_v2'")
    expect(workspace).toContain('p_id:policy.id')
    expect(workspace).toContain('new Date().toISOString()')
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

    for(const label of ['Scheduled Jobs & Run Control','Schedule Configuration','Scheduled Target','Freshness Policy','Cadence','Next Run','Schedule Status','Latest Refresh Queue','Recent Job Runs','Edit schedule','Run on demand'])expect(workspace).toContain(label)
    for(const route of ['#layer-1-operations','#layer-2-enrichment','#layer-3-ai-interpretation','#jobs','#evidence'])expect(workspace).toContain(route)
    expect(workspace).toContain('Historical Jobs are never reset or replayed')
    expect(read('index.html')).not.toContain('scheduled-jobs-config-entry.js')
  })

  test('existing refresh policy bridge remains authenticated, invoker-facing and no new scheduler RPC is introduced',()=>{
    const bridge=read('supabase/migrations/20260825204118_m2_3_non_exposed_browser_bridge_hardening.sql')
    expect(bridge).toContain('security.refresh_policy_upsert_v2_browser_bridge')
    expect(bridge).toContain('security.refresh_policy_upsert_v2_impl')
    expect(bridge).toContain('language sql security definer')
    expect(bridge).toContain('create or replace function public.refresh_policy_upsert_v2')
    expect(bridge).toContain('security invoker')
    expect(bridge).toContain('revoke all on function public.refresh_policy_upsert_v2')
    expect(bridge).toContain('from public,anon')
    expect(bridge).toContain('to authenticated,service_role')

    const migrations=fs.readdirSync('supabase/migrations').filter(x=>x.endsWith('.sql')).map(x=>read(`supabase/migrations/${x}`)).join('\n')
    expect(migrations).not.toContain('create or replace function public.scheduler_policy_control')
    expect(migrations).not.toMatch(/update\s+pipeline\.jobs\s+set/i)
    expect(migrations).not.toMatch(/delete\s+from\s+pipeline\.jobs/i)
    expect(migrations).not.toMatch(/truncate\s+(table\s+)?pipeline\.jobs/i)
  })
})
