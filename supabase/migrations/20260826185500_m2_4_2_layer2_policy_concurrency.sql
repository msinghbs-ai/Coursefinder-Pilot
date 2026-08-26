-- CF-CHG-20260827-044
create or replace function public.layer2_ops_policy_update(p_actor uuid,p_profile_id uuid,p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','security','pipeline'
as $$
declare v_rank integer:=0; v_row pipeline.layer2_execution_policies%rowtype;
begin
  if p_actor is null or p_actor<>auth.uid() then raise exception 'actor mismatch' using errcode='42501'; end if;
  select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank<5 then raise exception 'pim_admin role required' using errcode='42501'; end if;
  if not exists(select 1 from pipeline.layer2_source_profiles where id=p_profile_id and domain in ('course_facts','scholarship')) then raise exception 'layer2 enrichment profile required' using errcode='22023'; end if;
  insert into pipeline.layer2_execution_policies(profile_id) values(p_profile_id) on conflict(profile_id) do nothing;
  update pipeline.layer2_execution_policies set
    schedule_mode=coalesce(nullif(p_patch->>'schedule_mode',''),schedule_mode),
    scheduled_hour_utc=case when p_patch ? 'scheduled_hour_utc' then nullif(p_patch->>'scheduled_hour_utc','')::smallint else scheduled_hour_utc end,
    batch_size=case when p_patch ? 'batch_size' then (p_patch->>'batch_size')::integer else batch_size end,
    routing_strategy=coalesce(nullif(p_patch->>'routing_strategy',''),routing_strategy),
    max_paid_attempts_per_entity=case when p_patch ? 'max_paid_attempts_per_entity' then (p_patch->>'max_paid_attempts_per_entity')::smallint else max_paid_attempts_per_entity end,
    max_vendor_units_per_entity=case when p_patch ? 'max_vendor_units_per_entity' then nullif(p_patch->>'max_vendor_units_per_entity','')::numeric else max_vendor_units_per_entity end,
    max_cost_usd_per_entity=case when p_patch ? 'max_cost_usd_per_entity' then nullif(p_patch->>'max_cost_usd_per_entity','')::numeric else max_cost_usd_per_entity end,
    max_concurrency=case when p_patch ? 'max_concurrency' then (p_patch->>'max_concurrency')::smallint else max_concurrency end,
    stale_after_minutes=case when p_patch ? 'stale_after_minutes' then (p_patch->>'stale_after_minutes')::integer else stale_after_minutes end,
    auto_handoff_layer3=case when p_patch ? 'auto_handoff_layer3' then (p_patch->>'auto_handoff_layer3')::boolean else auto_handoff_layer3 end,
    stop_on_identity_mismatch=case when p_patch ? 'stop_on_identity_mismatch' then (p_patch->>'stop_on_identity_mismatch')::boolean else stop_on_identity_mismatch end,
    updated_by=p_actor,updated_at=now()
  where profile_id=p_profile_id returning * into v_row;
  return jsonb_build_object('ok',true,'policy',to_jsonb(v_row));
end $$;
revoke all on function public.layer2_ops_policy_update(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_ops_policy_update(uuid,uuid,jsonb) to service_role;