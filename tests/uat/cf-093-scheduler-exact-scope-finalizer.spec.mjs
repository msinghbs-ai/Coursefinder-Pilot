import{test,expect}from'@playwright/test'
import fs from'node:fs'

const sql=fs.readFileSync('supabase/migrations/20260911095142_cf_093_scheduler_exact_scope_codex_finalizer.sql','utf8')

test('CF-093 exact-scope finalizer preserves narrow authority and closes Codex runtime gaps',()=>{
 expect(sql).toContain('scheduler_workflow_scope_snapshot_v2')
 expect(sql).toContain("md5(string_agg(profile_id::text||':'||course_id::text||':'||coalesce(source_url,'<discover>')")
 expect(sql).toContain("'scope_fingerprint',counts.scope_fingerprint")
 expect(sql).toContain("Layer 2 scope changed while preview was being constructed; preview again")
 expect(sql).toContain("Layer 2 runnable scope changed after preview; preview again before dispatch")
 expect(sql).toContain("coalesce(j.result->>'scope_fingerprint','')=v_live_fingerprint")
 expect(sql).toContain("coalesce(j.result->'profile_ids','[]'::jsonb)=to_jsonb(v_live_profiles)")

 expect(sql).toContain("lower(coalesce(ap.provider_key,''))<>'parsebot'")
 expect(sql).toContain("lower(coalesce(ap.auth_scheme,'none'))='none' or ap.vault_secret_id is not null")
 expect(sql).toContain("target_url !~* '^https://")
 expect(sql).toContain("discovery_strategy,search_url_template")
 expect(sql).toContain("discovery_strategy,catalogue_url")

 expect(sql).toContain("from public.layer2_scope_courses(v_country,case when p_state_id is null then 'country' else 'state' end,p_state_id)")
 expect(sql).toContain("'scope_source','layer2_executable_provider_scope'")

 expect(sql).toContain("v_workflow <> 'course_facts_l2'")
 expect(sql).toContain("only AU Layer 2 Course Facts is currently authorised for this builder")
 expect(sql).toContain("v_mode <> 'acquisition_only'")
 expect(sql).toContain("Conditional Layer 3/L4 orchestration is not yet qualified")
 expect(sql).toContain("Country/state schedules are not advertised")
 expect(sql).toContain("scheduler_workflow_run_now_v2_browser_bridge")
 expect(sql).toContain("security.current_role_rank() < 4")
 expect(sql).not.toContain('automatic_governed_pipeline\',\'label\',\'Automatic governed pipeline\',\'enabled\',true')
 expect(sql).not.toContain('reprocess_governed_evidence\',\'label\',\'Reprocess governed Evidence\',\'enabled\',true')
})
