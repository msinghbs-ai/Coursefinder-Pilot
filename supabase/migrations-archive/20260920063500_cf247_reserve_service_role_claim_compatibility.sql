-- CF-247 forward-only compatibility fix: PostgREST may expose JWT role via request.jwt.claims.
-- Preserve service-role/postgres-only reservation authority.
create or replace function public.layer3_reserve_work_service(p_worker text, p_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline'
as $$
declare v_result jsonb; v_caller text;
begin
  v_caller:=coalesce(
    nullif(current_setting('request.jwt.claim.role',true),''),
    nullif(current_setting('request.jwt.role',true),''),
    nullif((nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role'),''),
    session_user
  );
  if v_caller not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if nullif(trim(p_worker),'') is null then raise exception 'worker required'; end if;
  update pipeline.layer3_work_items set status=case when attempt_count>=5 and corrective_retry_authorized_at is null then 'parked' else 'pending' end,available_at=case when attempt_count>=5 and corrective_retry_authorized_at is null then available_at else now() end,completed_at=case when attempt_count>=5 and corrective_retry_authorized_at is null then now() else null end,last_error=case when attempt_count>=5 and corrective_retry_authorized_at is null then 'reservation lease expired after maximum attempts' else 'reservation lease expired; requeued' end,reserved_at=null,reserved_by=null,updated_at=now() where status='reserved' and reserved_at < now()-interval '15 minutes';
  with picked as (select w.id from pipeline.layer3_work_items w left join pipeline.layer3_model_profiles p on p.id=w.profile_id where w.status in ('pending','failed') and w.available_at<=now() and (w.attempt_count<5 or (w.corrective_retry_count=1 and w.corrective_retry_authorized_at is not null)) and (w.profile_id is null or (p.enabled and not p.paused and coalesce((p.quality_benchmark->>'pass')::boolean,false))) order by w.created_at,w.id for update of w skip locked limit least(greatest(coalesce(p_limit,10),1),50)), reserved as (update pipeline.layer3_work_items w set status='reserved',reserved_at=now(),reserved_by=trim(p_worker),attempt_count=w.attempt_count+1,corrective_retry_authorized_at=null,updated_at=now() from picked where w.id=picked.id returning w.*) select coalesce(jsonb_agg(jsonb_build_object('id',id,'layer2_run_item_id',layer2_run_item_id,'evidence_id',evidence_id,'entity_type',entity_type,'entity_id',entity_id,'task_class',task_class,'profile_id',profile_id,'attempt_count',attempt_count,'reason',reason,'policy_version',policy_version,'corrective_retry_count',corrective_retry_count,'corrective_retry_reason',corrective_retry_reason) order by created_at,id),'[]'::jsonb) into v_result from reserved;
  return v_result;
end $$;
