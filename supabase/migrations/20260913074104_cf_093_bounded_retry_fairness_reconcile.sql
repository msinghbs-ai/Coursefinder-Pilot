begin;

-- CF-CHG-20260910-093 forward-only recovery reconciliation.
-- Honour the already-governed profile retry.max_attempts contract for Preview-bound
-- discovery and prioritise never-attempted courses before retries. Exhausted transient
-- failures are omitted from further continuations but are NOT promoted to terminal
-- Evidence or queueable URLs; the existing exact-token handoff therefore remains
-- fail-closed if any discovery course never reached a governed terminal outcome.

create or replace function public.layer2_discovery_context_scope_bound_v1(
  p_preview_token uuid,
  p_actor uuid,
  p_profile_id uuid,
  p_course_ids uuid[] default '{}'::uuid[],
  p_limit integer default 50
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','catalogue','public','security'
as $$
declare
  v_ctx jsonb;
  v_provider uuid;
  v_courses jsonb;
  v_binding pipeline.scheduler_workflow_async_bindings%rowtype;
  v_requested uuid[];
  v_snapshot jsonb;
  v_retry_max integer:=3;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_preview_token is null or p_actor is null or p_profile_id is null then raise exception 'preview token, actor and profile required' using errcode='22023'; end if;
  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_requested from unnest(coalesce(p_course_ids,'{}'::uuid[])) x;
  if cardinality(v_requested)=0 then raise exception 'scheduler bound discovery requires explicit course_ids' using errcode='22023'; end if;

  select * into v_binding
  from pipeline.scheduler_workflow_async_bindings b
  where b.preview_token=p_preview_token and b.actor_id=p_actor and b.profile_id=p_profile_id
  for update;
  if not found then raise exception 'exact scheduler async binding not found' using errcode='22023'; end if;
  if v_binding.status<>'active' then raise exception 'scheduler async binding is not active' using errcode='22023'; end if;
  if v_binding.execution_expires_at is null or v_binding.execution_expires_at<=now() then raise exception 'scheduler async execution binding expired' using errcode='22023'; end if;
  if not (v_binding.discovery_course_ids @> v_requested) then raise exception 'discovery chunk is outside exact scheduler binding' using errcode='22023'; end if;

  v_snapshot:=security.scheduler_workflow_profile_binding_snapshot_v1(p_profile_id,v_binding.sync_course_ids,v_binding.discovery_course_ids);
  if v_snapshot is null
     or (v_snapshot->>'profile_version_id')::uuid<>v_binding.profile_version_id
     or v_snapshot->>'identity_fingerprint'<>v_binding.identity_fingerprint
     or v_snapshot->>'queueable_fingerprint'<>v_binding.queueable_fingerprint
     or coalesce((v_snapshot->>'all_ids_valid')::boolean,false)=false
     or coalesce((v_snapshot->>'discovery_subset_valid')::boolean,false)=false
  then raise exception 'scheduler async bound profile/course identity changed before discovery Evidence write' using errcode='22023'; end if;

  select public.layer2_runtime_context(p_profile_id) into v_ctx;
  if v_ctx is null or v_ctx->>'domain'<>'course_facts' then raise exception 'course_facts profile required' using errcode='22023'; end if;
  if nullif(v_ctx->>'version_id','')::uuid<>v_binding.profile_version_id then raise exception 'scheduler bound profile version changed' using errcode='22023'; end if;

  begin
    v_retry_max:=least(greatest(coalesce(nullif(v_ctx#>>'{configuration,retry,max_attempts}','')::integer,3),1),10);
  exception when others then
    v_retry_max:=3;
  end;

  select s.provider_id into v_provider from pipeline.sources s where s.id=(v_ctx->>'source_id')::uuid;
  if v_provider is null then raise exception 'profile source is not bound to a canonical provider' using errcode='22023'; end if;

  select coalesce(
    jsonb_agg(to_jsonb(x)-'retry_attempts' order by x.retry_attempts,x.canonical_title,x.id),
    '[]'::jsonb
  ) into v_courses
  from (
    select c.id,c.canonical_title,c.display_title,c.course_code,coalesce(a.retry_attempts,0)::integer retry_attempts
    from catalogue.courses c
    left join lateral (
      select count(*)::integer retry_attempts
      from pipeline.jobs j
      cross join lateral jsonb_array_elements(coalesce(j.result->'results','[]'::jsonb)) r
      where j.job_type='layer2_discovery'
        and j.payload->>'scheduler_preview_token'=v_binding.preview_token::text
        and j.payload->>'profile_id'=p_profile_id::text
        and r->>'course_id'=c.id::text
        and r->>'status' in ('failed','candidate')
    ) a on true
    where c.provider_id=v_provider and c.id=any(v_requested)
      and coalesce(a.retry_attempts,0)<v_retry_max
      and not exists(
        select 1
        from pipeline.layer2_course_discovery_candidates dc
        join pipeline.layer2_provider_attempts pa on pa.id=dc.provider_attempt_id
        join pipeline.jobs j on j.id=pa.job_id
        where dc.course_id=c.id
          and dc.source_profile_version_id=v_binding.profile_version_id
          and dc.selected=true
          and nullif(dc.discovered_url,'') is not null
          and dc.created_at>=v_binding.activated_at
          and coalesce(j.payload->>'scheduler_preview_token','')=v_binding.preview_token::text
      )
    order by coalesce(a.retry_attempts,0),c.canonical_title,c.id
    limit least(greatest(coalesce(p_limit,50),1),50)
  ) x;

  return jsonb_build_object(
    'runtime',v_ctx,'canonical_provider_id',v_provider,'courses',v_courses,
    'scheduler_preview_token',v_binding.preview_token,'scheduler_bound_retry',true,
    'retry_max_attempts',v_retry_max,
    'identity_revalidated',true,'historical_dispositions_preserved',true
  );
end $$;

revoke all on function public.layer2_discovery_context_scope_bound_v1(uuid,uuid,uuid,uuid[],integer) from public,anon,authenticated;
grant execute on function public.layer2_discovery_context_scope_bound_v1(uuid,uuid,uuid,uuid[],integer) to service_role;

commit;
