-- M2.4.2 A13 — bounded historical screenshot backfill for accepted Evidence.
-- Uses the existing one-time internal nonce bridge; helpers are service-only.
begin;

create or replace function public.layer2_screenshot_backfill_context(p_evidence_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','pipeline'
as $$
declare v jsonb;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select jsonb_build_object(
   'evidence_id',e.id,'source_id',e.source_id,'source_url',e.source_url,'job_id',e.job_id,
   'profile_version_id',e.source_profile_version_id,'attempt_id',pa.id,
   'existing_screenshot_evidence_id',pa.screenshot_evidence_id
 ) into v
 from pipeline.evidence_artifacts e
 join pipeline.layer2_provider_attempts pa
   on e.id in (pa.raw_evidence_id,pa.html_evidence_id)
   or pa.id::text=coalesce(e.metadata->>'attempt_id','')
 where e.id=p_evidence_id
 order by pa.completed_at desc nulls last
 limit 1;
 return coalesce(v,'{}'::jsonb);
end $$;

create or replace function public.layer2_screenshot_backfill_attach(p_attempt_id uuid,p_screenshot_evidence_id uuid,p_metrics jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path='pg_catalog','pipeline'
as $$
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 update pipeline.layer2_provider_attempts
 set screenshot_evidence_id=p_screenshot_evidence_id,
     metrics=coalesce(metrics,'{}'::jsonb)||coalesce(p_metrics,'{}'::jsonb)
 where id=p_attempt_id;
end $$;

revoke all on function public.layer2_screenshot_backfill_context(uuid) from public,anon,authenticated;
revoke all on function public.layer2_screenshot_backfill_attach(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_screenshot_backfill_context(uuid) to service_role;
grant execute on function public.layer2_screenshot_backfill_attach(uuid,uuid,jsonb) to service_role;

do $$
declare v_oid oid;v_def text;
begin
 select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='pipeline' and p.proname='svc_pilot_submit_nonce'
   and pg_get_function_identity_arguments(p.oid)='p_function text, p_body jsonb';
 if v_oid is null then raise exception 'nonce submit function not found'; end if;
 select pg_get_functiondef(v_oid) into v_def;
 if position('layer2-screenshot-backfill-scheduled' in v_def)=0 then
   v_def:=replace(v_def,'''layer3-source-pattern-benchmark''','''layer3-source-pattern-benchmark'',''layer2-screenshot-backfill-scheduled''');
   execute v_def;
 end if;
end $$;

commit;
