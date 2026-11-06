// Guards: Provider Description mandate §6/7/9: ordinary dispatch failures persist one recoverable governed task, never a synthetic success.
import assert from'node:assert/strict'
import fs from'node:fs'
import{sql,quote}from'./db.mjs'
const provider='10000000-0000-0000-0000-000000000013'
const before=sql(`select jsonb_build_object('provider',to_jsonb(p),'reads',(select count(*) from pipeline.provider_description_reads where provider_id=p.id)) from catalogue.providers p where p.id=${quote(provider)}::uuid;`,{role:'postgres',json:true})
const proof=sql(`begin;
 create or replace function pipeline.svc_pilot_submit_nonce(p_function text,p_body jsonb) returns bigint language plpgsql as $fault$begin raise exception 'Controlled isolated worker dispatch failure' using errcode='08006';end$fault$;
 create temp table dispatch_failure_proof(result jsonb);
 do $test$ declare preview jsonb; cohort jsonb; first_run jsonb; repeated jsonb; saved jsonb; task pipeline.admin_jobs%rowtype;
 begin
  preview:=public.admin_provider_description_run_v1('preview',jsonb_build_object('provider_id',${quote(provider)},'country','AU','size',1,'mode','stored'));
  cohort:=public.admin_provider_description_run_v1('prepare',jsonb_build_object('preview_token',preview->>'preview_token','reason','Controlled isolated failure preserves the fixed cohort and audit trail'));
  first_run:=public.admin_provider_description_run_v1('run',jsonb_build_object('cohort_id',cohort->>'cohort_id'));
  repeated:=public.admin_provider_description_run_v1('run',jsonb_build_object('cohort_id',cohort->>'cohort_id'));
  saved:=public.admin_provider_description_run_v1('saved',jsonb_build_object('cohort_id',cohort->>'cohort_id'));
  select * into task from pipeline.admin_jobs where id=(first_run->'runs'->0->>'run_id')::uuid;
  perform fixture.ok(task.state='failed' and task.outcome='failed_retryable','dispatch error uses actual registered failed_retryable outcome');
  perform fixture.ok(task.error like '%Controlled isolated worker dispatch failure%','actual dispatch error remains saved after refresh');
  perform fixture.ok(first_run->'runs'->0->>'run_id'=repeated->'runs'->0->>'run_id' and first_run->'runs'->0->>'run_id'=saved->'runs'->0->>'run_id','retry and refresh recover the identical persisted task');
  perform fixture.ok((select count(*) from pipeline.admin_jobs where args->>'cohort_id'=cohort->>'cohort_id')=1,'failed dispatch retry does not create a second governed task');
  perform fixture.ok((select count(*) from pipeline.provider_description_reads r join pipeline.provider_description_cohort_members m on m.read_id=r.id where m.cohort_id=(cohort->>'cohort_id')::uuid and r.state='queued')=1,'queued fixed provider remains available for the existing scheduled retry');
  insert into dispatch_failure_proof values(jsonb_build_object('state',task.state,'outcome',task.outcome,'saved_error',task.error,'same_task_on_retry',true,'same_task_after_refresh',true,'tasks',1,'queued_for_existing_scheduler',1));
 end $test$;
 select result from dispatch_failure_proof;rollback;`,{role:'postgres',json:true})
const after=sql(`select jsonb_build_object('provider',to_jsonb(p),'reads',(select count(*) from pipeline.provider_description_reads where provider_id=p.id)) from catalogue.providers p where p.id=${quote(provider)}::uuid;`,{role:'postgres',json:true})
assert.deepEqual(after,before,'rollback leaves Browser provider, description and read state unchanged')
fs.mkdirSync('docs/ui-evidence',{recursive:true});fs.writeFileSync('docs/ui-evidence/provider-description-dispatch-recovery.json',JSON.stringify({...proof,all_fault_rows_rolled_back:true,actual_vendor_calls:0},null,2)+'\n')
console.log('PASS actual dispatch fault persists one failed_retryable task; retry/refresh recover it; queued work retained; all fault rows rolled back')
