import{test,expect}from'@playwright/test'
import fs from'node:fs'

const migration=fs.readFileSync('supabase/migrations/20260913064500_cf_093_bound_handoff_queueable_provenance_reconcile.sql','utf8')

test('CF-093 exact Preview provenance is limited to the discovery subset at handoff',()=>{
 expect(migration).toContain('v_bound and c.id=any(v_binding.discovery_course_ids)')
 expect(migration).toContain("j.payload->>'scheduler_preview_token'=v_binding.preview_token::text")
})

test('CF-093 preserves pre-existing queueable selected candidate URLs outside the discovery subset',()=>{
 expect(migration).toContain('when v_bound then coalesce((')
 expect(migration).toContain('d.source_profile_version_id=v_binding.profile_version_id')
 expect(migration).toContain("d.selected=true and nullif(d.discovered_url,'') is not null")
 expect(migration).not.toContain('update pipeline.layer2_course_discovery_candidates')
})

test('CF-093 keeps authority and ACL boundaries on the forward handoff replacement',()=>{
 expect(migration).toContain("current_user not in ('service_role','postgres')")
 expect(migration).toContain("raise exception 'scheduler async bound profile/course identity changed before deterministic handoff'")
 expect(migration).toContain('revoke all on function public.layer2_scope_profile_batch_service(uuid,uuid,uuid[]) from public,anon,authenticated')
 expect(migration).toContain('grant execute on function public.layer2_scope_profile_batch_service(uuid,uuid,uuid[]) to service_role')
})
