import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const read=path=>fs.readFileSync(path,'utf8')

test.describe('CF-092 Scheduled Jobs configuration contract',()=>{
  test('native browser surface preserves governed reads and bounded mutation boundaries',async()=>{
    const [workspace,legacy,client]=['src/ScheduledJobsWorkspace.jsx','src/m2-3-intelligence-entry.jsx','src/lib/supabase.js'].map(read)
    expect(legacy).toContain("import ScheduledJobsWorkspace from'./ScheduledJobsWorkspace'")
    expect(legacy).toContain('export const Refresh=ScheduledJobsWorkspace')
    expect(workspace).toContain('api.jobs(50)')
    expect(workspace).toContain("supabase.rpc('scheduler_policy_control'")
    expect(workspace).not.toMatch(/supabase\.from\s*\(/)
    expect(client).toContain("adminRead('jobs'")
    for(const label of ['Scheduled Jobs & Run Control','Schedule Configuration','Scheduled Target','Freshness Policy','Cadence','Next Run','Schedule Status','Latest Refresh Queue','Recent Job Runs','Edit schedule','Run on demand'])expect(workspace).toContain(label)
    for(const route of ['#layer-1-operations','#layer-2-enrichment','#layer-3-ai-interpretation','#jobs','#evidence'])expect(workspace).toContain(route)
    expect(workspace).toContain('does not reset/replay a historical Job')
    expect(read('index.html')).not.toContain('scheduled-jobs-config-entry.js')
  })

  test('database control is role-gated, bounded and non-replay',async()=>{
    const sql=read('supabase/migrations/20260910131000_cf_092_scheduled_jobs_config_controls.sql')
    expect(sql).toContain("security.current_role_rank() < 4")
    expect(sql).toContain("p_action not in ('edit_schedule','queue_now')")
    expect(sql).toContain("p_layer not between 1 and 3")
    expect(sql).toContain("v_target_kind not in ('source','profile')")
    expect(sql).toContain("r.status in ('queued','running')")
    expect(sql).toContain("'manual_policy'")
    expect(sql).toContain('revoke all on function public.scheduler_policy_control')
    expect(sql).toContain('from public, anon')
    expect(sql).not.toMatch(/update\s+pipeline\.jobs/i)
    expect(sql).not.toMatch(/delete\s+from\s+pipeline\.jobs/i)
    expect(sql).not.toMatch(/truncate\s+(table\s+)?pipeline\.jobs/i)
  })
})