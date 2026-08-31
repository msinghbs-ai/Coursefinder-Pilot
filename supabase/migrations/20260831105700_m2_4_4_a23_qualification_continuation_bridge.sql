-- M2.4.4 A23 — repair background qualification self-continuation without exposing pipeline schema.
-- CF-CHG-20260830-048

create or replace function public.layer2_qualification_continue_service(p_run_id uuid)
returns bigint
language plpgsql
security invoker
set search_path to 'pg_catalog','public','pipeline'
as $function$
declare
  v_request_id bigint;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  if p_run_id is null then
    raise exception 'run_id required' using errcode='22023';
  end if;

  if not exists(
    select 1
    from pipeline.layer2_scale_qualification_runs q
    where q.id=p_run_id
      and q.status='running'
      and coalesce((q.result_summary->>'background_scheduler_authorized')::boolean,false)
  ) then
    return null;
  end if;

  if not exists(
    select 1
    from pipeline.layer2_scale_qualification_items qi
    where qi.run_id=p_run_id
      and qi.status='qualifying'
  ) then
    return null;
  end if;

  v_request_id:=pipeline.svc_pilot_submit_nonce(
    'layer2-scale-qualify-scheduled',
    jsonb_build_object('run_id',p_run_id,'limit',2)
  );
  return v_request_id;
end
$function$;

revoke all on function public.layer2_qualification_continue_service(uuid) from public,anon,authenticated;
grant execute on function public.layer2_qualification_continue_service(uuid) to service_role;

comment on function public.layer2_qualification_continue_service(uuid) is
'A23 service-role-only bridge for self-continuing a bounded background qualification run. It preserves the non-exposed pipeline schema and does not authorise canonical, Search or Publication mutation.';
