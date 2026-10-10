-- M2.4.2 — make immutable-profile discovery restart idempotent.
-- Terminal evaluated outcomes are not re-acquired on restart; provider/acquisition failures remain retryable.

begin;

create or replace function public.layer2_discovery_context(p_profile_id uuid, p_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','catalogue','public'
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
        select 1
        from pipeline.layer2_course_discovery_candidates dc
        where dc.course_id=c.id
          and dc.source_profile_version_id=(v_ctx->>'version_id')::uuid
          and dc.status in ('exact_match','likely_match','ambiguous','identity_mismatch','current_page_not_found')
      )
    order by c.canonical_title,c.id
    limit least(greatest(coalesce(p_limit,10),1),50)
  ) x;
  return jsonb_build_object('runtime',v_ctx,'canonical_provider_id',v_provider,'direct_provider_id',v_direct,'courses',v_courses);
end $$;

create or replace function public.layer2_discovery_context_scope(
  p_profile_id uuid,
  p_course_ids uuid[] default null::uuid[],
  p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','catalogue','public'
as $$
declare v_ctx jsonb; v_provider uuid; v_courses jsonb;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select public.layer2_runtime_context(p_profile_id) into v_ctx;
  if v_ctx is null or v_ctx->>'domain'<>'course_facts' then raise exception 'course_facts profile required' using errcode='22023'; end if;
  select s.provider_id into v_provider from pipeline.sources s where s.id=(v_ctx->>'source_id')::uuid;
  if v_provider is null then raise exception 'profile source is not bound to a canonical provider' using errcode='22023'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.canonical_title,x.id),'[]'::jsonb) into v_courses
  from (
    select c.id,c.canonical_title,c.display_title,c.course_code
    from catalogue.courses c
    where c.provider_id=v_provider
      and (p_course_ids is null or c.id=any(p_course_ids))
      and not exists(
        select 1
        from pipeline.layer2_course_discovery_candidates dc
        where dc.course_id=c.id
          and dc.source_profile_version_id=(v_ctx->>'version_id')::uuid
          and dc.status in ('exact_match','likely_match','ambiguous','identity_mismatch','current_page_not_found')
      )
    order by c.canonical_title,c.id
    limit least(greatest(coalesce(p_limit,50),1),50)
  ) x;
  return jsonb_build_object('runtime',v_ctx,'canonical_provider_id',v_provider,'courses',v_courses);
end $$;

revoke all on function public.layer2_discovery_context(uuid,integer) from public,anon,authenticated;
revoke all on function public.layer2_discovery_context_scope(uuid,uuid[],integer) from public,anon,authenticated;
grant execute on function public.layer2_discovery_context(uuid,integer) to service_role;
grant execute on function public.layer2_discovery_context_scope(uuid,uuid[],integer) to service_role;

commit;
