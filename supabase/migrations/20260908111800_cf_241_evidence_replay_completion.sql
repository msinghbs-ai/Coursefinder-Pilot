-- CF-241 — complete Evidence replay dependencies and align derived Evidence semantics.
--
-- This forward-only completion migration:
--   * restores remaining live Evidence helper functions missing from migration history;
--   * atomically rebuilds the derived Evidence lineage cache under write-blocking locks;
--   * aligns extraction-state and freshness filters with returned DTO precedence;
--   * does not mutate canonical catalogue/scholarship content.

create or replace function security.admin_evidence_layer(
  p_storage_path text,
  p_evidence_type text,
  p_metadata jsonb,
  p_source_type text
)
returns text
language sql
immutable
set search_path to 'pg_catalog'
as $function$
  select case
    when coalesce(p_metadata->>'layer','') ~ '^[1-4]$' then 'L'||(p_metadata->>'layer')
    when lower(coalesce(p_storage_path,'')) like 'layer2%' then 'L2'
    when lower(coalesce(p_evidence_type,'')) in ('qilt_source_workbook','prisms_published_workbook','layer2a_source_file','source_snapshot')
         and lower(coalesce(p_source_type,'')) not in ('regulatory_register','regulatory') then 'L2'
    when lower(coalesce(p_storage_path,'')) like 'regulatory%'
      or lower(coalesce(p_evidence_type,''))='regulatory_snapshot' then 'L1'
    when lower(coalesce(p_storage_path,'')) like 'layer3%' then 'L3'
    when lower(coalesce(p_storage_path,'')) like 'layer4%' then 'L4'
    else 'Unclassified'
  end
$function$;

create or replace function security.admin_evidence_matches_entity(
  p_evidence_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_provider_id uuid
)
returns boolean
language sql
stable
set search_path to 'pg_catalog','pipeline'
as $function$
  select case
    when nullif(trim(coalesce(p_entity_type,'')),'') is null
      and p_entity_id is null
      and p_provider_id is null then true
    else exists(
      select 1
      from pipeline.evidence_entity_links el
      where el.evidence_id=p_evidence_id
        and (nullif(trim(coalesce(p_entity_type,'')),'') is null or el.entity_type=lower(trim(p_entity_type)))
        and (p_entity_id is null or el.entity_id=p_entity_id)
        and (p_provider_id is null or el.provider_id=p_provider_id)
    )
  end
$function$;

create or replace function security.admin_evidence_verification_at(p_evidence_id uuid)
returns timestamptz
language sql
stable
set search_path to 'pg_catalog','catalogue'
as $function$
  select max(v) from (
    select max(last_verified_at) v from catalogue.course_fees where evidence_id=p_evidence_id
    union all select max(last_verified_at) from catalogue.course_english_requirements where evidence_id=p_evidence_id
    union all select max(last_verified_at) from catalogue.course_links where evidence_id=p_evidence_id
    union all select max(last_verified_at) from catalogue.course_regulatory_observations where evidence_id=p_evidence_id
    union all select max(last_verified_at) from catalogue.course_study_level_observations where evidence_id=p_evidence_id
    union all select max(verified_at) from catalogue.course_identifiers where evidence_id=p_evidence_id
    union all select max(last_verified_at) from catalogue.campuses where evidence_id=p_evidence_id
    union all select max(verified_at) from catalogue.provider_identifiers where evidence_id=p_evidence_id
    union all select max(verified_at) from catalogue.provider_rankings where evidence_id=p_evidence_id
    union all select max(verified_at) from catalogue.provider_collection_memberships where evidence_id=p_evidence_id
    union all select max(checked_at) from catalogue.provider_registrations where evidence_id=p_evidence_id
  ) q
$function$;

-- Make the derived-cache repair atomic relative to writes. Locks are held until the
-- migration transaction commits, so no source row can slip between snapshot and trigger state.
do $$
declare
  v_relation text;
  v_relations constant text[] := array[
    'catalogue.campuses',
    'catalogue.course_academic_options',
    'catalogue.course_campuses',
    'catalogue.course_collection_memberships',
    'catalogue.course_english_requirements',
    'catalogue.course_fees',
    'catalogue.course_field_observations',
    'catalogue.course_identifiers',
    'catalogue.course_intakes',
    'catalogue.course_links',
    'catalogue.course_registrations',
    'catalogue.course_regulatory_observations',
    'catalogue.course_study_level_observations',
    'catalogue.outcome_benchmarks',
    'catalogue.provider_associations',
    'catalogue.provider_collection_memberships',
    'catalogue.provider_identifiers',
    'catalogue.provider_outcomes',
    'catalogue.provider_rankings',
    'catalogue.provider_registrations',
    'catalogue.student_flow_observations',
    'scholarship.application_windows',
    'scholarship.award_tiers',
    'scholarship.coverage',
    'scholarship.criteria',
    'scholarship.criterion_groups',
    'scholarship.identifiers',
    'scholarship.offering_cycles',
    'scholarship.scholarships',
    'scholarship.scopes'
  ];
begin
  foreach v_relation in array v_relations loop
    if to_regclass(v_relation) is not null then
      execute format('lock table %s in share row exclusive mode', v_relation);
    end if;
  end loop;

  create temporary table cf241_lineage_rebuild (
    evidence_id uuid primary key,
    observation_count bigint not null default 0,
    source_null_count bigint not null default 0,
    rejected_count bigint not null default 0
  ) on commit drop;

  foreach v_relation in array v_relations loop
    if to_regclass(v_relation) is null then
      continue;
    end if;
    execute format($sql$
      insert into cf241_lineage_rebuild(evidence_id,observation_count,source_null_count,rejected_count)
      select t.evidence_id,
             count(*)::bigint,
             count(*) filter (where security.evidence_row_source_null(%L,to_jsonb(t)))::bigint,
             count(*) filter (where security.evidence_row_rejected(to_jsonb(t)))::bigint
      from %s t
      where t.evidence_id is not null
      group by t.evidence_id
      on conflict(evidence_id) do update set
        observation_count=cf241_lineage_rebuild.observation_count+excluded.observation_count,
        source_null_count=cf241_lineage_rebuild.source_null_count+excluded.source_null_count,
        rejected_count=cf241_lineage_rebuild.rejected_count+excluded.rejected_count
    $sql$, v_relation, v_relation);
  end loop;

  delete from pipeline.evidence_lineage_stats;
  insert into pipeline.evidence_lineage_stats(evidence_id,observation_count,source_null_count,rejected_count,updated_at)
  select evidence_id,observation_count,source_null_count,rejected_count,now()
  from cf241_lineage_rebuild;
end
$$;

-- Patch the governed Evidence page in place so later accepted behaviour is preserved while
-- extraction/freshness filters use the same precedence as the returned DTO.
do $$
declare
  v_oid oid := to_regprocedure('security.admin_evidence_page(jsonb)');
  v_definition text;
  v_old text;
  v_new text;
begin
  if v_oid is null then
    raise exception 'CF-241: security.admin_evidence_page(jsonb) is missing' using errcode='55000';
  end if;

  select pg_get_functiondef(v_oid) into v_definition;

  v_old := '(v_freshness=''expired'' and e.valid_to is not null and e.valid_to<now())';
  v_new := '(v_freshness=''expired'' and not (lower(coalesce(e.metadata->>''freshness_state'',''''))=''stale'' or lower(coalesce(e.metadata->>''stale'',''false''))=''true'') and e.valid_to is not null and e.valid_to<now())';
  if position(v_old in v_definition)>0 then v_definition:=replace(v_definition,v_old,v_new); end if;

  v_old := '(v_freshness=''current'' and e.valid_to is not null and e.valid_to>=now())';
  v_new := '(v_freshness=''current'' and not (lower(coalesce(e.metadata->>''freshness_state'',''''))=''stale'' or lower(coalesce(e.metadata->>''stale'',''false''))=''true'') and e.valid_to is not null and e.valid_to>=now())';
  if position(v_old in v_definition)>0 then v_definition:=replace(v_definition,v_old,v_new); end if;

  v_old := '(v_extraction_state=''extracted'' and observation_count>0)';
  v_new := '(v_extraction_state=''extracted'' and observation_count>0 and rejected_count=0)';
  if position(v_old in v_definition)>0 then v_definition:=replace(v_definition,v_old,v_new); end if;

  v_old := 'case when x.rejected_count>0 and x.observation_count=0 then ''rejected'' when x.observation_count>0 then ''extracted'' else ''missing_extraction'' end';
  v_new := 'case when x.rejected_count>0 then ''rejected'' when x.observation_count>0 then ''extracted'' else ''missing_extraction'' end';
  if position(v_old in v_definition)>0 then v_definition:=replace(v_definition,v_old,v_new); end if;

  if position('(v_extraction_state=''extracted'' and observation_count>0 and rejected_count=0)' in v_definition)=0
     or position('case when x.rejected_count>0 then ''rejected'' when x.observation_count>0 then ''extracted'' else ''missing_extraction'' end' in v_definition)=0
     or position('(v_freshness=''expired'' and not (lower(coalesce(e.metadata->>''freshness_state'',''''))=''stale'' or lower(coalesce(e.metadata->>''stale'',''false''))=''true'')' in v_definition)=0
     or position('(v_freshness=''current'' and not (lower(coalesce(e.metadata->>''freshness_state'',''''))=''stale'' or lower(coalesce(e.metadata->>''stale'',''false''))=''true'')' in v_definition)=0 then
    raise exception 'CF-241: Evidence page semantic patch did not converge to expected shape' using errcode='55000';
  end if;

  execute v_definition;
end
$$;

comment on function security.admin_evidence_layer(text,text,jsonb,text) is
  'Governed Evidence layer classifier restored to migration history by CF-241.';
comment on function security.admin_evidence_matches_entity(uuid,text,uuid,uuid) is
  'Governed Evidence entity matcher restored to migration history by CF-241.';
comment on function security.admin_evidence_verification_at(uuid) is
  'Governed Evidence verification timestamp helper restored to migration history by CF-241.';
