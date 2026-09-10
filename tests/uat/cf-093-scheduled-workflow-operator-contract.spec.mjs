import{test,expect}from'@playwright/test'
import fs from'node:fs/promises'

const read=path=>fs.readFile(path,'utf8')

test.describe('CF-093 Scheduled Tasks operator contract',()=>{
 test('task-first search, attribution and personal columns stay additive to CF-092',async()=>{
  const workspace=await read('src/ScheduledJobsWorkspace.jsx')
  const migration=await read('supabase/migrations/20260911052000_cf_093_scheduler_operator_attribution.sql')
  const reviewFix=await read('supabase/migrations/20260911053600_cf_093_codex_review_fixes.sql')
  const css=await read('src/scheduled-jobs-config.css')

  for(const text of ['Task / Dataset','Search scheduled tasks','Created By','Owner','Columns','Reset view','Scheduled Target','Cadence','Next Run','Schedule Status','Actions'])expect(workspace).toContain(text)
  for(const text of ['technicalTarget','targetLabel','created_by_display','created_by_state','owner_display','localStorage','cf:scheduler:view:v1'])expect(workspace).toContain(text)
  expect(workspace).toContain("supabase.rpc('scheduler_policy_run_now_v1'")
  expect(workspace).toContain("supabase.rpc('scheduler_policy_edit_v1'")
  expect(workspace).toContain("supabase.rpc('scheduler_policies_list_v1'")
  expect(workspace).toContain('p_query:search.trim()')
  expect(workspace).toContain("technicalTarget(x)!=='UNBOUNDED'?technicalTarget(x):'Scheduled task'")
  expect(workspace).toContain('does not change its recurring cadence or next-run time')
  expect(workspace).toContain('Layer 3 remains Evidence/profile/model-qualified')
  expect(workspace).toContain('useRef')
  expect(workspace).toContain('const loadGeneration=useRef(0)')
  expect(workspace).toContain('const generation=++loadGeneration.current')
  expect(workspace).toContain('if(generation!==loadGeneration.current)return')
  expect(workspace).toContain('if(generation===loadGeneration.current)setBusy(false)')

  for(const text of ['created_by_display_snapshot','created_by_email_snapshot','actor_display_snapshot','actor_email_snapshot','System / legacy','System / automation','former_user','security invoker','curator role required'])expect(migration.toLowerCase()).toContain(text.toLowerCase())
  expect(migration).not.toContain('created_by_email_snapshot as created_by_email')
  expect(migration).not.toContain('actor_email_snapshot as actor_email')

  expect(reviewFix).toContain('p_query text default')
  expect(reviewFix).toContain("v_query text:=lower(trim(coalesce(p_query,'')))")
  expect(reviewFix).toContain('limit v_limit offset v_offset')
  expect(reviewFix).toContain('au.deleted_at is null')
  expect(reviewFix).toContain('au.banned_until is null or au.banned_until <= now()')
  expect(reviewFix).toContain('drop function if exists public.scheduler_policies_list_v1(integer,integer)')
  expect(reviewFix).toContain('security invoker')
  expect(reviewFix).toContain('curator role required')
  expect(reviewFix).toContain('revoke all on function public.scheduler_policies_list_v1(integer,integer,text) from public,anon')
  expect(css).toContain('cf-scheduler-v2__sticky-actions')
 })
})
