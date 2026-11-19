-- CF-CHG-20260827-044
-- Bounded service-only discovery orchestration over the accepted Layer 2 profile/version model.

create index if not exists layer2_course_discovery_version_selected_idx
  on pipeline.layer2_course_discovery_candidates(source_profile_version_id,selected,course_id)
  where selected=true;

create or replace function public.layer2_discovery_context(p_profile_id uuid,p_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline','catalogue','public'
as $$
declare v_ctx jsonb; v_provider uuid; v_direct uuid; v_courses jsonb;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select public.layer2_runtime_context(p_profile_id) into v_ctx;
  if v_ctx is null or v_ctx->>'domain'<>'course_facts' then raise exception 'course_facts profile required' using errcode='22023'; end if;
  select s.provider_id into v_provider from pipeline.sources s where s.id=(v_ctx->>'source_id')::uuid;
  if v_provider is null then raise exception 'profile source is not bound to a canonical provider' using errcode='22023'; end if;
  select id into v_direct from pipeline.layer2_acquisition_providers where provider_key='direct-http' and enabled=true;
  if v_direct is null then raise exception 'direct-http acquisition provider unavailable'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.canonical_title,x.id),'[]'::jsonb) into v_courses
  from (
    select c.id,c.canonical_title,c.display_title,c.course_code
    from catalogue.courses c
    where c.provider_id=v_provider
      and not exists(
        select 1 from pipeline.layer2_course_discovery_candidates dc
        where dc.course_id=c.id and dc.source_profile_version_id=(v_ctx->>'version_id')::uuid and dc.selected=true
      )
    order by c.canonical_title,c.id
    limit least(greatest(coalesce(p_limit,10),1),50)
  ) x;
  return jsonb_build_object('runtime',v_ctx,'canonical_provider_id',v_provider,'direct_provider_id',v_direct,'courses',v_courses);
end $$;
revoke all on function public.layer2_discovery_context(uuid,integer) from public,anon,authenticated;
grant execute on function public.layer2_discovery_context(uuid,integer) to service_role;

create or replace function pipeline.svc_pilot_submit_nonce(p_function text,p_body jsonb default '{}'::jsonb)
returns bigint
language plpgsql
security definer
set search_path='pipeline','net','public','extensions'
as $$
declare v_nonce uuid:=extensions.gen_random_uuid(); v_id bigint;
begin
  if p_function not in (
    'layer1-ca-niagara-catalogue','qilt-au-etl','prisms-au-etl','layer1-au-depth','layer1-au-completeness',
    'coursefacts-au-rmit','coursefacts-au-uq','coursefacts-au-qut','layer1-au-cricos-facts','layer1-operations-scheduled',
    'layer2-scope-discover-scheduled'
  ) then raise exception 'one-time Pilot Edge function is not allowlisted'; end if;
  insert into pipeline.pilot_edge_nonces(id,function_name,expires_at) values(v_nonce,p_function,now()+interval '2 minutes');
  select net.http_post(
    url:='https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1/'||p_function,
    headers:=jsonb_build_object('content-type','application/json','x-cf-run-nonce',v_nonce::text),
    body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=120000
  ) into v_id;
  return v_id;
end $$;

create or replace function security.layer2_discovery_dispatch(p_profile_id uuid,p_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline','security'
as $$
declare v_req bigint;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if not exists(select 1 from pipeline.layer2_source_profiles where id=p_profile_id and domain='course_facts' and enabled and not paused) then raise exception 'enabled course_facts profile required' using errcode='22023'; end if;
  v_req:=pipeline.svc_pilot_submit_nonce('layer2-scope-discover-scheduled',jsonb_build_object('profile_id',p_profile_id,'limit',least(greatest(coalesce(p_limit,10),1),50)));
  return jsonb_build_object('ok',true,'profile_id',p_profile_id,'request_id',v_req,'limit',least(greatest(coalesce(p_limit,10),1),50));
end $$;
revoke all on function security.layer2_discovery_dispatch(uuid,integer) from public,anon,authenticated;
grant execute on function security.layer2_discovery_dispatch(uuid,integer) to service_role;
