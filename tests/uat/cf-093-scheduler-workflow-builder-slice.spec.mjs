import{test,expect}from'@playwright/test'
import fs from'node:fs'

const read=p=>fs.readFileSync(p,'utf8')

test('CF-093 target builder exposes only server-authorised AU Layer 2 Course Facts slice',()=>{
 const index=read('index.html')
 const ui=read('src/scheduler-workflow-builder-entry.jsx')
 const migration=read('supabase/migrations/20260911021144_cf_093_scheduler_workflow_builder_slice.sql')
 const aclFix=read('supabase/migrations/20260911021847_cf_093_scheduler_workflow_bridge_acl_fix.sql')

 expect(index).toContain('/src/scheduler-workflow-builder-entry.jsx')
 expect(ui).toContain("const WORKFLOW_KEY='course_facts_l2'")
 expect(ui).toContain("const AU='AU'")
 expect(ui).toContain("scheduler_workflow_scope_options_v1")
 expect(ui).toContain("scheduler_workflow_preview_v1")
 expect(ui).toContain("scheduler_workflow_run_now_v1")
 expect(ui).toContain("Preview governed scope")
 expect(ui).toContain("Run acquisition + deterministic Layer 2")
 expect(ui).toContain("Automatic L2 → conditional L3/L4 and Evidence reprocessing remain disabled here")
 expect(ui).not.toContain("refresh_policy_upsert_v2")

 expect(migration).toContain("security.current_role_rank() < 4")
 expect(migration).toContain("only AU Layer 2 Course Facts is currently authorised for this builder")
 expect(migration).toContain("v_mode <> 'acquisition_only'")
 expect(migration).toContain("Conditional Layer 3/L4 orchestration is not yet qualified")
 expect(migration).toContain("Country/state schedules are not advertised")
 expect(migration).toContain("language sql\nsecurity invoker")
 expect(migration).toContain("grant execute on function public.scheduler_workflow_run_now_v1")

 // SECURITY INVOKER wrappers must have a callable private bridge, while the bridge
 // independently enforces auth.uid + rank. This is the governed CF-239 prevention rule.
 expect(aclFix).toContain("grant execute on function security.scheduler_workflow_scope_options_v1_browser_bridge")
 expect(aclFix).toContain("grant execute on function security.scheduler_workflow_preview_v1_browser_bridge")
 expect(aclFix).toContain("grant execute on function security.scheduler_workflow_run_now_v1_browser_bridge")
 expect(aclFix).toContain("to authenticated")
 expect(aclFix).toContain("from anon")
 expect(aclFix).not.toContain("to anon")
})

test('CF-093 builder preserves explicit preview-before-dispatch and follow-through semantics',()=>{
 const ui=read('src/scheduler-workflow-builder-entry.jsx')
 const migration=read('supabase/migrations/20260911021144_cf_093_scheduler_workflow_builder_slice.sql')
 expect(ui).toContain("if(!preview){setError('Preview the governed scope before running it.')")
 expect(ui).toContain("governance reason of at least 5 characters")
 expect(ui).toContain("location.hash='#jobs'")
 expect(ui).toContain("location.hash='#evidence'")
 expect(migration).toContain("'scheduler_workflow_run','course_facts','completed'")
 expect(migration).toContain("'change_control_ref','CF-CHG-20260910-093'")
 expect(migration).toContain("public.layer2_operator_scope_service(v_actor,'start'")
})
