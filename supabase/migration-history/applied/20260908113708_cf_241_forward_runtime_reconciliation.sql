-- CF-241 — forward reconciliation of superseded CF-239 admin_read helper routing.
--
-- Scope is intentionally narrow:
--   * restore the governed Evidence lineage cache subsystem missing from migration history;
--   * restore the governed security.admin_evidence_page implementation missing from migration history;
--   * restore evidence_page to the governed security.admin_evidence_page implementation;
--   * restore layer2_ops_overview to security.admin_layer2_ops_read;
--   * preserve all other current admin_read routes, including later accepted Course PIM work;
--   * leave CF-239 fast-helper definitions and indexes in place for separate planner/latency review;
--   * do not mutate canonical data.
--
-- This migration is replay-safe across the checked-in pre-CF-239 dispatcher, the live
-- superseded CF-239 dispatcher, and the already-reconciled dispatcher. It fails closed
-- on any other shape rather than guessing.

create table if not exists pipeline.evidence_lineage_stats (
  evidence_id uuid primary key references pipeline.evidence_artifacts(id) on delete cascade,
  observation_count bigint not null default 0 check (observation_count >= 0),
  source_null_count bigint not null default 0 check (source_null_count >= 0),
  rejected_count bigint not null default 0 check (rejected_count >= 0),
  updated_at timestamptz not null default now()
);

create or replace function security.evidence_row_rejected(p_row jsonb)
returns boolean
language sql
immutable
set search_path to 'pg_catalog'
as $function$
  select lower(coalesce(p_row->>'status',p_row->>'lifecycle_status',''))='rejected'
$function$;

create or replace function security.evidence_row_source_null(p_table text,p_row jsonb)
returns boolean
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
begin
  return case p_table
    when 'catalogue.course_fees' then (p_row->'amount') is null or jsonb_typeof(p_row->'amount')='null'
    when 'catalogue.course_intakes' then coalesce(p_row->>'intake_label','')='' and (p_row->'intake_year' is null or jsonb_typeof(p_row->'intake_year')='null') and (p_row->'start_date' is null or jsonb_typeof(p_row->'start_date')='null')
    when 'catalogue.course_english_requirements' then (p_row->'overall_score' is null or jsonb_typeof(p_row->'overall_score')='null') and coalesce(p_row->'component_scores','{}'::jsonb)='{}'::jsonb
    when 'catalogue.course_links' then coalesce(p_row->>'url','')=''
    when 'catalogue.course_registrations' then coalesce(p_row->>'registration_code','')=''
    when 'catalogue.course_study_level_observations' then coalesce(p_row->>'source_value','')=''
    when 'catalogue.course_field_observations' then coalesce(p_row->>'source_field_code','')='' and coalesce(p_row->>'source_field_name','')=''
    when 'catalogue.provider_outcomes' then (p_row->'metric_value' is null or jsonb_typeof(p_row->'metric_value')='null')
    when 'catalogue.student_flow_observations' then (p_row->'metric_value' is null or jsonb_typeof(p_row->'metric_value')='null') and coalesce((p_row->>'is_suppressed')::boolean,false)=false
    when 'scholarship.criteria' then (p_row->'value_text' is null or jsonb_typeof(p_row->'value_text')='null') and (p_row->'value_number' is null or jsonb_typeof(p_row->'value_number')='null') and (p_row->'value_codes' is null or jsonb_typeof(p_row->'value_codes')='null') and (p_row->'value_json' is null or jsonb_typeof(p_row->'value_json')='null')
    when 'scholarship.award_tiers' then (p_row->'amount' is null or jsonb_typeof(p_row->'amount')='null') and (p_row->'percentage' is null or jsonb_typeof(p_row->'percentage')='null') and (p_row->'maximum_amount' is null or jsonb_typeof(p_row->'maximum_amount')='null')
    else false
  end;
end
$function$;

create or replace function security.adjust_evidence_lineage_stats(
  p_evidence_id uuid,
  p_observation_delta bigint,
  p_source_null_delta bigint,
  p_rejected_delta bigint
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline'
as $function$
begin
  if p_evidence_id is null then return; end if;
  insert into pipeline.evidence_lineage_stats(evidence_id,observation_count,source_null_count,rejected_count,updated_at)
  values(p_evidence_id,greatest(p_observation_delta,0),greatest(p_source_null_delta,0),greatest(p_rejected_delta,0),now())
  on conflict(evidence_id) do update set
    observation_count=greatest(0,pipeline.evidence_lineage_stats.observation_count+p_observation_delta),
    source_null_count=greatest(0,pipeline.evidence_lineage_stats.source_null_count+p_source_null_delta),
    rejected_count=greatest(0,pipeline.evidence_lineage_stats.rejected_count+p_rejected_delta),
    updated_at=now();
end
$function$;

create or replace function security.sync_evidence_lineage_stats()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','security'
as $function$
declare
  v_old jsonb;
  v_new jsonb;
  v_old_evidence uuid;
  v_new_evidence uuid;
  v_table text:=tg_table_schema||'.'||tg_table_name;
begin
  if tg_op in ('UPDATE','DELETE') then
    v_old:=to_jsonb(old);
    v_old_evidence:=nullif(v_old->>'evidence_id','')::uuid;
    perform security.adjust_evidence_lineage_stats(
      v_old_evidence,
      -1,
      case when security.evidence_row_source_null(v_table,v_old) then -1 else 0 end,
      case when security.evidence_row_rejected(v_old) then -1 else 0 end
    );
  end if;
  if tg_op in ('INSERT','UPDATE') then
    v_new:=to_jsonb(new);
    v_new_evidence:=nullif(v_new->>'evidence_id','')::uuid;
    perform security.adjust_evidence_lineage_stats(
      v_new_evidence,
      1,
      case when security.evidence_row_source_null(v_table,v_new) then 1 else 0 end,
      case when security.evidence_row_rejected(v_new) then 1 else 0 end
    );
  end if;
  return case when tg_op='DELETE' then old else new end;
end
$function$;

-- A clean replay has no lineage cache rows. Rebuild the derived cache once from the
-- same 30 relations maintained by the accepted live trigger topology. Existing Pilot
-- cache rows are preserved and are never cleared or rewritten by this migration.
do $$
declare
  v_rel text;
  v_relations text[] := array[
    'catalogue.campuses','catalogue.course_academic_options','catalogue.course_campuses',
    'catalogue.course_collection_memberships','catalogue.course_english_requirements','catalogue.course_fees',
    'catalogue.course_field_observations','catalogue.course_identifiers','catalogue.course_intakes',
    'catalogue.course_links','catalogue.course_registrations','catalogue.course_regulatory_observations',
    'catalogue.course_study_level_observations','catalogue.outcome_benchmarks','catalogue.provider_associations',
    'catalogue.provider_collection_memberships','catalogue.provider_identifiers','catalogue.provider_outcomes',
    'catalogue.provider_rankings','catalogue.provider_registrations','catalogue.student_flow_observations',
    'scholarship.application_windows','scholarship.award_tiers','scholarship.coverage','scholarship.criteria',
    'scholarship.criterion_groups','scholarship.identifiers','scholarship.offering_cycles',
    'scholarship.scholarships','scholarship.scopes'
  ];
begin
  if not exists(select 1 from pipeline.evidence_lineage_stats) then
    create temporary table cf241_evidence_lineage_rebuild (
      evidence_id uuid primary key,
      observation_count bigint not null default 0,
      source_null_count bigint not null default 0,
      rejected_count bigint not null default 0
    ) on commit drop;

    foreach v_rel in array v_relations loop
      if to_regclass(v_rel) is not null and exists(
        select 1 from pg_attribute
        where attrelid=to_regclass(v_rel) and attname='evidence_id' and attnum>0 and not attisdropped
      ) then
        execute format($sql$
          insert into cf241_evidence_lineage_rebuild(evidence_id,observation_count,source_null_count,rejected_count)
          select t.evidence_id,
                 count(*)::bigint,
                 count(*) filter(where security.evidence_row_source_null(%L,to_jsonb(t)))::bigint,
                 count(*) filter(where security.evidence_row_rejected(to_jsonb(t)))::bigint
          from %s t
          where t.evidence_id is not null
          group by t.evidence_id
          on conflict(evidence_id) do update set
            observation_count=cf241_evidence_lineage_rebuild.observation_count+excluded.observation_count,
            source_null_count=cf241_evidence_lineage_rebuild.source_null_count+excluded.source_null_count,
            rejected_count=cf241_evidence_lineage_rebuild.rejected_count+excluded.rejected_count
        $sql$,v_rel,v_rel);
      end if;
    end loop;

    insert into pipeline.evidence_lineage_stats(evidence_id,observation_count,source_null_count,rejected_count,updated_at)
    select evidence_id,observation_count,source_null_count,rejected_count,now()
    from cf241_evidence_lineage_rebuild
    on conflict(evidence_id) do update set
      observation_count=excluded.observation_count,
      source_null_count=excluded.source_null_count,
      rejected_count=excluded.rejected_count,
      updated_at=now();
  end if;

  foreach v_rel in array v_relations loop
    if to_regclass(v_rel) is not null and exists(
      select 1 from pg_attribute
      where attrelid=to_regclass(v_rel) and attname='evidence_id' and attnum>0 and not attisdropped
    ) and not exists(
      select 1 from pg_trigger
      where tgrelid=to_regclass(v_rel) and tgname='evidence_lineage_stats_sync' and not tgisinternal
    ) then
      execute format('create trigger evidence_lineage_stats_sync after insert or delete or update on %s for each row execute function security.sync_evidence_lineage_stats()',v_rel);
    end if;
  end loop;
end
$$;

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
        or (v_freshness='expired' and lower(coalesce(e.metadata->>'freshness_state',''))<>'stale' and lower(coalesce(e.metadata->>'stale','false'))<>'true' and e.valid_to is not null and e.valid_to<now())
        or (v_freshness='current' and lower(coalesce(e.metadata->>'freshness_state',''))<>'stale' and lower(coalesce(e.metadata->>'stale','false'))<>'true' and e.valid_to is not null and e.valid_to>=now())
        or (v_freshness='no_policy' and lower(coalesce(e.metadata->>'freshness_state',''))<>'stale' and lower(coalesce(e.metadata->>'stale','false'))<>'true' and e.valid_to is null))
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

comment on table pipeline.evidence_lineage_stats is
  'Derived Evidence lineage counters restored to migration history by CF-241; maintained by evidence_lineage_stats_sync triggers.';
comment on function security.admin_evidence_page(jsonb) is
  'Governed Evidence catalogue page implementation restored to migration history by CF-241 from current accepted Pilot runtime truth.';
comment on function public.admin_read(text,jsonb) is
  'Governed Admin read dispatcher. CF-241 restores pre-CF-239 Evidence and Layer 2 overview routes while preserving later accepted contracts.';
