-- M2.4.4 A23 — reconcile the qualification continuation privilege boundary.
-- CF-CHG-20260830-048
-- Public PostgREST wrapper remains SECURITY INVOKER. Protected-table access is isolated
-- in a non-exposed security-schema implementation callable only by service_role.

create or replace function security.layer2_qualification_continue_impl(p_run_id uuid)
returns bigint
language plpgsql
security definer
set search_path to 'pg_catalog','security','pipeline','public'
as $function$
declare
  v_request_id bigint;
begin
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

revoke all on function security.layer2_qualification_continue_impl(uuid) from public,anon,authenticated;
grant execute on function security.layer2_qualification_continue_impl(uuid) to service_role;

create or replace function public.layer2_qualification_continue_service(p_run_id uuid)
returns bigint
language plpgsql
security invoker
set search_path to 'pg_catalog','security'
as $function$
begin
  return security.layer2_qualification_continue_impl(p_run_id);
end
$function$;

revoke all on function public.layer2_qualification_continue_service(uuid) from public,anon,authenticated;
grant execute on function public.layer2_qualification_continue_service(uuid) to service_role;

comment on function security.layer2_qualification_continue_impl(uuid) is
'A23 internal privileged implementation. It only continues an already-authorised running qualification wave with remaining qualifying items.';
comment on function public.layer2_qualification_continue_service(uuid) is
'A23 service-role-only SECURITY INVOKER PostgREST bridge to the non-exposed security implementation. No browser, canonical, Search or Publication authority.';
