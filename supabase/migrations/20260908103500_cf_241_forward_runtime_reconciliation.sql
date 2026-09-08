-- CF-241 — forward reconciliation of superseded CF-239 admin_read helper routing.
--
-- Scope is intentionally narrow:
--   * restore the governed security.admin_evidence_page implementation missing from migration history;
--   * restore evidence_page to the governed security.admin_evidence_page implementation;
--   * restore layer2_ops_overview to security.admin_layer2_ops_read;
--   * preserve all other current admin_read routes, including later accepted Course PIM work;
--   * leave CF-239 helper definitions and indexes in place for separate planner/latency review;
--   * do not mutate canonical data.
--
-- This migration is replay-safe across the checked-in pre-CF-239 dispatcher, the live
-- superseded CF-239 dispatcher, and the already-reconciled dispatcher. It fails closed
-- on any other shape rather than guessing.

create or replace function security.admin_evidence_page(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','security','pipeline','ref','auth','storage'
as $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce((p_args->>'limit')::integer,50),1),200);
  v_offset integer:=greatest(coalesce((p_args->>'offset')::integer,0),0);
  v_query text:=nullif(trim(coalesce(p_args->>'query','')),'');
  v_country text:=upper(nullif(trim(coalesce(p_args->>'country','')),''));
  v_source_id uuid:=nullif(p_args->>'source_id','')::uuid;
  v_layer text:=upper(nullif(trim(coalesce(p_args->>'layer','')),''));
  v_entity_type text:=nullif(trim(coalesce(p_args->>'entity_type','')),'');
  v_entity_id uuid:=nullif(p_args->>'entity_id','')::uuid;
  v_provider_id uuid:=nullif(p_args->>'provider_id','')::uuid;
  v_job_id uuid:=nullif(p_args->>'job_id','')::uuid;
  v_evidence_type text:=nullif(trim(coalesce(p_args->>'evidence_type','')),'');
  v_mime text:=nullif(trim(coalesce(p_args->>'mime','')),'');
  v_hash text:=lower(nullif(trim(coalesce(p_args->>'hash','')),''));
  v_job_status text:=nullif(trim(coalesce(p_args->>'job_status','')),'');
  v_status text:=lower(nullif(trim(coalesce(p_args->>'status','')),''));
  v_extraction_state text:=nullif(trim(coalesce(p_args->>'extraction_state','')),'');
  v_freshness text:=lower(nullif(trim(coalesce(p_args->>'freshness','')),''));
  v_verified_from timestamptz:=nullif(p_args->>'verified_from','')::timestamptz;
  v_verified_to timestamptz:=nullif(p_args->>'verified_to','')::timestamptz;
  v_conflicts boolean:=case when p_args ? 'unresolved_conflicts' then (p_args->>'unresolved_conflicts')::boolean else null end;
  v_sort text:=lower(coalesce(p_args->>'sort','captured'));
  v_direction text:=case when lower(coalesce(p_args->>'direction','desc'))='asc' then 'asc' else 'desc' end;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;

  with conflicts as materialized (
    select distinct cl.evidence_id
    from workflow.review_queue rq join pipeline.claims cl on cl.id=rq.candidate_claim_id
    where cl.evidence_id is not null and lower(coalesce(rq.status,'open')) not in ('closed','resolved','accepted','rejected')
  ),
  successors as materialized (
    select distinct supersedes_evidence_id evidence_id
    from pipeline.evidence_artifacts where supersedes_evidence_id is not null
  ),
  base as materialized (
    select e.id,e.source_id,e.job_id,e.evidence_type,e.source_url,e.content_hash,e.mime_type,e.captured_at,
      e.valid_from,e.valid_to,e.supersedes_evidence_id,
      s.label source_label,s.source_type,s.status source_status,s.url authority_url,
      co.iso_alpha2 country_code,j.job_type,j.domain job_domain,j.status job_status,
      security.admin_evidence_layer(e.storage_path,e.evidence_type,e.metadata,s.source_type) layer_code,
      (lower(coalesce(e.metadata->>'freshness_state',''))='stale' or lower(coalesce(e.metadata->>'stale','false'))='true') explicit_stale,
      coalesce(ls.observation_count,0) observation_count,coalesce(ls.source_null_count,0) source_null_count,
      coalesce(ls.rejected_count,0) rejected_count,(cf.evidence_id is not null) unresolved_conflict,(su.evidence_id is not null) is_superseded
    from pipeline.evidence_artifacts e
    left join pipeline.sources s on s.id=e.source_id
    left join ref.countries co on co.id=s.country_id
    left join pipeline.jobs j on j.id=e.job_id
    left join pipeline.evidence_lineage_stats ls on ls.evidence_id=e.id
    left join conflicts cf on cf.evidence_id=e.id
    left join successors su on su.evidence_id=e.id
    where
      (v_query is null or e.id::text ilike '%'||v_query||'%' or coalesce(s.label,'') ilike '%'||v_query||'%' or
       coalesce(s.source_type,'') ilike '%'||v_query||'%' or coalesce(s.url,'') ilike '%'||v_query||'%' or
       coalesce(e.source_url,'') ilike '%'||v_query||'%' or coalesce(e.content_hash,'') ilike '%'||v_query||'%' or
       coalesce(j.job_type,'') ilike '%'||v_query||'%' or coalesce(j.domain,'') ilike '%'||v_query||'%' or
       coalesce(e.metadata::text,'') ilike '%'||v_query||'%' or coalesce(e.storage_path,'') ilike '%'||v_query||'%')
      and (v_country is null or co.iso_alpha2=v_country)
      and (v_source_id is null or e.source_id=v_source_id)
      and (v_layer is null or security.admin_evidence_layer(e.storage_path,e.evidence_type,e.metadata,s.source_type)=v_layer)
      and (v_job_id is null or e.job_id=v_job_id)
      and (v_evidence_type is null or e.evidence_type=v_evidence_type)
      and (v_mime is null or e.mime_type=v_mime)
      and (v_hash is null or lower(coalesce(e.content_hash,'')) like v_hash||'%')
      and (v_job_status is null or j.status=v_job_status)
      and ((v_entity_type is null and v_entity_id is null and v_provider_id is null) or security.admin_evidence_matches_entity(e.id,v_entity_type,v_entity_id,v_provider_id))
      and (v_conflicts is null or (cf.evidence_id is not null)=v_conflicts)
      and (v_freshness is null
        or (v_freshness='stale' and (lower(coalesce(e.metadata->>'freshness_state',''))='stale' or lower(coalesce(e.metadata->>'stale','false'))='true'))
        or (v_freshness='expired' and e.valid_to is not null and e.valid_to<now())
        or (v_freshness='current' and e.valid_to is not null and e.valid_to>=now())
        or (v_freshness='no_policy' and e.valid_to is null and lower(coalesce(e.metadata->>'freshness_state',''))<>'stale' and lower(coalesce(e.metadata->>'stale','false'))<>'true'))
      and (v_verified_from is null or security.admin_evidence_verification_at(e.id)>=v_verified_from)
      and (v_verified_to is null or security.admin_evidence_verification_at(e.id)<v_verified_to)
  ),
  classified as materialized (
    select b.*,case when b.unresolved_conflict then 'conflict' when b.rejected_count>0 then 'rejected'
      when b.observation_count=0 then 'missing_extraction' when b.source_null_count>0 then 'source_null'
      when b.explicit_stale then 'stale' when (b.valid_to is not null and b.valid_to<now()) or b.is_superseded then 'superseded'
      else 'current' end operational_status
    from base b
  ),
  filtered as materialized (
    select * from classified where (v_status is null or operational_status=v_status)
      and (v_extraction_state is null or (v_extraction_state='extracted' and observation_count>0)
        or (v_extraction_state='missing_extraction' and observation_count=0)
        or (v_extraction_state='rejected' and rejected_count>0))
  ),
  page as materialized (
    select * from filtered order by
      case when v_sort='source' and v_direction='asc' then source_label end asc nulls last,
      case when v_sort='source' and v_direction='desc' then source_label end desc nulls last,
      case when v_sort='type' and v_direction='asc' then evidence_type end asc nulls last,
      case when v_sort='type' and v_direction='desc' then evidence_type end desc nulls last,
      case when v_sort='layer' and v_direction='asc' then layer_code end asc nulls last,
      case when v_sort='layer' and v_direction='desc' then layer_code end desc nulls last,
      case when v_sort='captured' and v_direction='asc' then captured_at end asc nulls last,
      case when v_sort='captured' and v_direction='desc' then captured_at end desc nulls last,
      captured_at desc nulls last,id limit v_limit offset v_offset
  ),
  final_page as materialized (
    select p.*,exists(select 1 from storage.objects o join pipeline.evidence_artifacts ee on ee.id=p.id where o.bucket_id='evidence' and o.name=ee.storage_path) storage_available from page p
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'id',x.id,'country_code',x.country_code,'source_id',x.source_id,'source_label',x.source_label,'source_type',x.source_type,
      'source_status',x.source_status,'authority_url',x.authority_url,'layer',x.layer_code,'job_id',x.job_id,'job_type',x.job_type,
      'job_domain',x.job_domain,'job_status',x.job_status,'evidence_type',x.evidence_type,'mime_type',x.mime_type,'captured_at',x.captured_at,
      'valid_from',x.valid_from,'valid_to',x.valid_to,'content_hash',x.content_hash,
      'extraction_state',case when x.rejected_count>0 and x.observation_count=0 then 'rejected' when x.observation_count>0 then 'extracted' else 'missing_extraction' end,
      'observation_count',x.observation_count,'has_source_null',x.source_null_count>0,'status',x.operational_status,
      'freshness_state',case when x.explicit_stale then 'stale' when x.valid_to is not null and x.valid_to<now() then 'expired' when x.valid_to is not null then 'current' else 'no_policy' end,
      'unresolved_conflict',x.unresolved_conflict,'history_state',case when x.is_superseded then 'superseded' when x.supersedes_evidence_id is not null then 'superseding_snapshot' else 'current_or_unversioned' end,
      'storage_available',x.storage_available
    ) order by
      case when v_sort='source' and v_direction='asc' then x.source_label end asc nulls last,
      case when v_sort='source' and v_direction='desc' then x.source_label end desc nulls last,
      case when v_sort='type' and v_direction='asc' then x.evidence_type end asc nulls last,
      case when v_sort='type' and v_direction='desc' then x.evidence_type end desc nulls last,
      case when v_sort='layer' and v_direction='asc' then x.layer_code end asc nulls last,
      case when v_sort='layer' and v_direction='desc' then x.layer_code end desc nulls last,
      case when v_sort='captured' and v_direction='asc' then x.captured_at end asc nulls last,
      case when v_sort='captured' and v_direction='desc' then x.captured_at end desc nulls last,x.captured_at desc nulls last,x.id)
      from final_page x),'[]'::jsonb),
    'total',(select count(*) from filtered),'limit',v_limit,'offset',v_offset
  ) into v_result;
  return v_result;
end
$function$;

do $$
declare
  v_oid oid := to_regprocedure('public.admin_read(text,jsonb)');
  v_definition text;
  v_evidence_old constant text := 'if p_operation=''evidence_page'' then return security.admin_evidence_page_default_fast(p_args); end if;';
  v_evidence_checked_in constant text := 'if p_operation in (''evidence_page'',''evidence_filters'',''evidence_detail'',''evidence_observations'',''evidence_entities'') then return security.admin_evidence_read(p_operation,p_args); end if;';
  v_evidence_checked_in_reconciled constant text := 'if p_operation=''evidence_page'' then return security.admin_evidence_page(p_args); end if;' || E'\n ' || 'if p_operation in (''evidence_filters'',''evidence_detail'',''evidence_observations'',''evidence_entities'') then return security.admin_evidence_read(p_operation,p_args); end if;';
  v_evidence_new constant text := 'if p_operation=''evidence_page'' then return security.admin_evidence_page(p_args); end if;';
  v_layer2_old constant text := 'if p_operation=''layer2_ops_overview'' then return security.admin_layer2_ops_overview_fast(); end if;';
  v_layer2_checked_in constant text := 'if p_operation in (''layer2_ops_overview'',''layer2_ops_run_detail'') then return security.admin_layer2_ops_read(p_operation,p_args); end if;';
  v_layer2_checked_in_reconciled constant text := 'if p_operation=''layer2_ops_overview'' then return security.admin_layer2_ops_read(''layer2_ops_overview'',p_args); end if;' || E'\n ' || 'if p_operation=''layer2_ops_run_detail'' then return security.admin_layer2_ops_read(p_operation,p_args); end if;';
  v_layer2_new constant text := 'if p_operation=''layer2_ops_overview'' then return security.admin_layer2_ops_read(''layer2_ops_overview'',p_args); end if;';
begin
  if v_oid is null then
    raise exception 'CF-241: public.admin_read(text,jsonb) is missing' using errcode = '55000';
  end if;

  select pg_get_functiondef(v_oid) into v_definition;

  if position(v_evidence_old in v_definition) > 0 then
    v_definition := replace(v_definition, v_evidence_old, v_evidence_new);
  elsif position(v_evidence_checked_in in v_definition) > 0 then
    v_definition := replace(v_definition, v_evidence_checked_in, v_evidence_checked_in_reconciled);
  elsif position(v_evidence_new in v_definition) = 0 then
    raise exception 'CF-241: evidence_page dispatcher shape is neither checked-in, superseded nor reconciled' using errcode = '55000';
  end if;

  if position(v_layer2_old in v_definition) > 0 then
    v_definition := replace(v_definition, v_layer2_old, v_layer2_new);
  elsif position(v_layer2_checked_in in v_definition) > 0 then
    v_definition := replace(v_definition, v_layer2_checked_in, v_layer2_checked_in_reconciled);
  elsif position(v_layer2_new in v_definition) = 0 then
    raise exception 'CF-241: layer2_ops_overview dispatcher shape is neither checked-in, superseded nor reconciled' using errcode = '55000';
  end if;

  execute v_definition;
end
$$;

comment on function security.admin_evidence_page(jsonb) is
  'Governed Evidence catalogue page implementation restored to migration history by CF-241 from current accepted Pilot runtime truth.';
comment on function public.admin_read(text,jsonb) is
  'Governed Admin read dispatcher. CF-241 restores pre-CF-239 Evidence and Layer 2 overview routes while preserving later accepted contracts.';
