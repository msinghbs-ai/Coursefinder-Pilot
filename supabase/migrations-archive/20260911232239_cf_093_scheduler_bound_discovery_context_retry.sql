begin;

-- CF-CHG-20260910-093 recovery correction for the deployed discovery worker.
-- The legacy helper treated any historical terminal/ambiguous discovery disposition as
-- permanently attempted, even when the current governed scope still had no selected URL.
-- For an active exact scheduler binding only, the explicit bound chunk is retryable and
-- prior candidate/Evidence history is retained append-only. Non-scheduler callers retain
-- the historical behaviour unchanged.
create or replace function public.layer2_discovery_context_scope(
  p_profile_id uuid,
  p_course_ids uuid[] default '{}'::uuid[],
  p_limit integer default 50
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','catalogue','public','security'
as $function$
declare
  v_ctx jsonb;
  v_provider uuid;
  v_courses jsonb;
  v_binding pipeline.scheduler_workflow_async_bindings%rowtype;
  v_bound boolean:=false;
  v_requested uuid[];
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select public.layer2_runtime_context(p_profile_id) into v_ctx;
  if v_ctx is null or v_ctx->>'domain'<>'course_facts' then raise exception 'course_facts profile required' using errcode='22023'; end if;
  select s.provider_id into v_provider from pipeline.sources s where s.id=(v_ctx->>'source_id')::uuid;
  if v_provider is null then raise exception 'profile source is not bound to a canonical provider' using errcode='22023'; end if;

  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_requested
  from unnest(coalesce(p_course_ids,'{}'::uuid[])) x;

  -- There can be at most one active scheduler binding per profile. Only that exact
  -- binding changes retry semantics; all other callers preserve the prior contract.
  select * into v_binding
  from pipeline.scheduler_workflow_async_bindings b
  where b.profile_id=p_profile_id
    and b.status='active'
    and b.execution_expires_at>now()
  order by b.activated_at desc
  limit 1;
  v_bound:=found;

  if v_bound then
    if nullif(v_ctx->>'version_id','')::uuid<>v_binding.profile_version_id then raise exception 'scheduler bound profile version changed' using errcode='22023'; end if;
    if cardinality(v_requested)=0 then raise exception 'scheduler bound discovery requires explicit course_ids' using errcode='22023'; end if;
    if not (v_binding.discovery_course_ids @> v_requested) then raise exception 'discovery chunk is outside active scheduler binding' using errcode='22023'; end if;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.canonical_title,x.id),'[]'::jsonb) into v_courses
    from (
      select c.id,c.canonical_title,c.display_title,c.course_code
      from catalogue.courses c
      where c.provider_id=v_provider
        and c.id=any(v_requested)
        -- A URL selected during this exact bound run is resolved and should not be retried.
        and not exists(
          select 1
          from pipeline.layer2_course_discovery_candidates dc
          where dc.course_id=c.id
            and dc.source_profile_version_id=v_binding.profile_version_id
            and dc.selected=true
            and nullif(dc.discovered_url,'') is not null
            and dc.created_at>=v_binding.activated_at
        )
      order by c.canonical_title,c.id
      limit least(greatest(coalesce(p_limit,50),1),50)
    ) x;

    return jsonb_build_object(
      'runtime',v_ctx,
      'canonical_provider_id',v_provider,
      'courses',v_courses,
      'scheduler_preview_token',v_binding.preview_token,
      'scheduler_bound_retry',true,
      'historical_dispositions_preserved',true
    );
  end if;

  -- Original legacy semantics retained exactly for non-scheduler discovery.
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
end
$function$;

revoke all on function public.layer2_discovery_context_scope(uuid,uuid[],integer) from public,anon,authenticated;
grant execute on function public.layer2_discovery_context_scope(uuid,uuid[],integer) to service_role;

commit;
