// Guards: Provider Description mandate §6/8: current governed cohort caps apply again at dispatch, before any queued work.
import assert from'node:assert/strict'
import fs from'node:fs'
import{sql}from'./db.mjs'
const proof=sql(`begin;
 update pipeline.provider_description_reads set last_verified_at=now()-interval '181 days',updated_at=now()-interval '181 days'
 where provider_id in ('10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002') and state='admitted';
 create temp table cap_change_proof(result jsonb);
 do $test$ declare preview jsonb; cohort jsonb; result jsonb; before_reads int; members_before jsonb;
 begin
  preview:=public.admin_provider_description_run_v1('preview','{"country":"AU","provider_type":"university","filter":"stale","mode":"stored","size":2}'::jsonb);
  perform fixture.ok((preview->>'eligible')::int=2,'two stale approved readers form the controlled cap-change cohort');
  cohort:=public.admin_provider_description_run_v1('prepare',jsonb_build_object('preview_token',preview->>'preview_token','reason','Controlled policy-cap change must refuse an oversized previously fixed cohort'));
  select count(*) into before_reads from pipeline.provider_description_reads;
  select jsonb_agg(to_jsonb(m) order by pick) into members_before from pipeline.provider_description_cohort_members m where cohort_id=(cohort->>'cohort_id')::uuid;
  update pipeline.platform_toolset_settings set value='1'::jsonb where toolset_key='pipeline' and key='pdesc.queue_per_run';
  perform fixture.refuses(format('select public.admin_provider_description_run_v1(%L,%L::jsonb)','run',jsonb_build_object('cohort_id',cohort->>'cohort_id')::text),'22023','lowered current cohort cap refuses Run Now');
  result:=public.admin_provider_description_run_v1('saved',jsonb_build_object('cohort_id',cohort->>'cohort_id'));
  perform fixture.ok((result->>'can_run')::boolean=false and result->>'reason_code'='current_cap_changed','saved UI capability reports current_cap_changed');
  perform fixture.ok((select state='prepared' and run_id is null from pipeline.provider_description_cohorts where id=(cohort->>'cohort_id')::uuid),'refused cohort remains prepared with no run');
  perform fixture.ok((select count(*) from pipeline.admin_jobs where args->>'cohort_id'=cohort->>'cohort_id')=0,'refused oversized cohort creates no task');
  perform fixture.ok((select count(*) from pipeline.provider_description_reads)=before_reads,'refused oversized cohort creates no queued reader work');
  perform fixture.ok((select jsonb_agg(to_jsonb(m) order by pick) from pipeline.provider_description_cohort_members m where cohort_id=(cohort->>'cohort_id')::uuid)=members_before,'fixed membership and snapshots remain unchanged');
  insert into cap_change_proof values(jsonb_build_object('fixed_members',2,'current_cap',1,'refused_sqlstate','22023','reason_code',result->>'reason_code','new_tasks',0,'new_reads',0,'state',result->>'state','membership_unchanged',true));
 end $test$;
 select result from cap_change_proof;rollback;`,{role:'postgres',json:true})
assert.equal(proof.reason_code,'current_cap_changed')
fs.writeFileSync('docs/ui-evidence/provider-description-cap-change.json',JSON.stringify({...proof,all_fault_rows_rolled_back:true},null,2)+'\n')
console.log('PASS lowered current cohort cap refuses dispatch; no reader/task/start/membership changes; rollback preserves original settings')
