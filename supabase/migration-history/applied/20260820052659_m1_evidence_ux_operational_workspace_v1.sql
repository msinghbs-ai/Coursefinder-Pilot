-- M1-EVIDENCE-UX operational workspace v1
-- Private, governed Evidence read path; legacy public definer ACL hardening;
-- selective indexes for visible-page lineage resolution; no canonical data rewrite.

create index if not exists evidence_artifacts_captured_idx
  on pipeline.evidence_artifacts (captured_at desc, id);
create index if not exists evidence_artifacts_type_captured_idx
  on pipeline.evidence_artifacts (evidence_type, captured_at desc);
create index if not exists evidence_artifacts_mime_captured_idx
  on pipeline.evidence_artifacts (mime_type, captured_at desc);
create index if not exists course_registrations_evidence_idx
  on catalogue.course_registrations (evidence_id);
create index if not exists course_intakes_evidence_idx
  on catalogue.course_intakes (evidence_id);
create index if not exists course_english_evidence_idx
  on catalogue.course_english_requirements (evidence_id);
create index if not exists course_campuses_evidence_idx
  on catalogue.course_campuses (evidence_id);
create index if not exists course_academic_options_evidence_idx
  on catalogue.course_academic_options (evidence_id);
create index if not exists course_collection_memberships_evidence_idx
  on catalogue.course_collection_memberships (evidence_id);
create index if not exists provider_registrations_evidence_idx
  on catalogue.provider_registrations (evidence_id);
create index if not exists provider_identifiers_evidence_idx
  on catalogue.provider_identifiers (evidence_id);
create index if not exists provider_rankings_evidence_idx
  on catalogue.provider_rankings (evidence_id);
create index if not exists provider_collection_memberships_evidence_idx
  on catalogue.provider_collection_memberships (evidence_id);
create index if not exists scholarships_evidence_idx
  on scholarship.scholarships (evidence_id);
create index if not exists scholarship_scopes_evidence_idx
  on scholarship.scopes (evidence_id);
create index if not exists scholarship_criteria_evidence_idx
  on scholarship.criteria (evidence_id);
create index if not exists scholarship_coverage_evidence_idx
  on scholarship.coverage (evidence_id);
create index if not exists provider_associations_evidence_idx
  on catalogue.provider_associations (evidence_id);

create or replace function security.admin_redact_json(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = pg_catalog, security
as $$
declare
  v_type text;
  v_result jsonb;
begin
  if p_value is null then return null; end if;
  v_type := jsonb_typeof(p_value);
  if v_type='object' then
    select coalesce(jsonb_object_agg(
      key,
      case
        when key ~* '(secret|token|password|credential|authorization|service.?role|api.?key|private.?key)'
          then '"[redacted]"'::jsonb
        else security.admin_redact_json(value)
      end
    ),'{}'::jsonb)
    into v_result
    from jsonb_each(p_value);
    return v_result;
  elsif v_type='array' then
    select coalesce(jsonb_agg(security.admin_redact_json(value) order by ordinality),'[]'::jsonb)
    into v_result
    from jsonb_array_elements(p_value) with ordinality;
    return v_result;
  end if;
  return p_value;
end
$$;

create or replace function security.admin_evidence_layer(
  p_storage_path text,
  p_evidence_type text,
  p_metadata jsonb,
  p_source_type text
)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
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
$$;

create or replace function security.admin_evidence_verification_at(p_evidence_id uuid)
returns timestamptz
language sql
stable
set search_path = pg_catalog, catalogue
as $$
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
$$;

create or replace function security.admin_evidence_observation_count(p_evidence_id uuid)
returns bigint
language sql
stable
set search_path = pg_catalog, catalogue, scholarship, pipeline
as $$
  select
    (select count(*) from catalogue.course_fees where evidence_id=p_evidence_id)
   +(select count(*) from catalogue.course_intakes where evidence_id=p_evidence_id)
   +(select count(*) from catalogue.course_english_requirements where evidence_id=p_evidence_id)
   +(select count(*) from catalogue.course_links where evidence_id=p_evidence_id)
   +(select count(*) from catalogue.course_registrations where evidence_id=p_evidence_id)
   +(select count(*) from catalogue.course_regulatory_observations where evidence_id=p_evidence_id)
   +(select count(*) from catalogue.course_study_level_observations where evidence_id=p_evidence_id)
   +(select count(*) from catalogue.course_field_observations where evidence_id=p_evidence_id)
   +(select count(*) from catalogue.course_campuses where evidence_id=p_evidence_id)
   +(select count(*) from catalogue.campuses where evidence_id=p_evidence_id)
   +(select count(*) from catalogue.provider_outcomes where evidence_id=p_evidence_id)
   +(select count(*) from catalogue.student_flow_observations where evidence_id=p_evidence_id)
   +(select count(*) from catalogue.provider_registrations where evidence_id=p_evidence_id)
   +(select count(*) from catalogue.provider_identifiers where evidence_id=p_evidence_id)
   +(select count(*) from scholarship.scholarships where evidence_id=p_evidence_id)
   +(select count(*) from scholarship.offering_cycles where evidence_id=p_evidence_id)
   +(select count(*) from scholarship.application_windows where evidence_id=p_evidence_id)
   +(select count(*) from scholarship.scopes where evidence_id=p_evidence_id)
   +(select count(*) from scholarship.criterion_groups where evidence_id=p_evidence_id)
   +(select count(*) from scholarship.criteria where evidence_id=p_evidence_id)
   +(select count(*) from scholarship.award_tiers where evidence_id=p_evidence_id)
   +(select count(*) from scholarship.coverage where evidence_id=p_evidence_id)
   +(select count(*) from scholarship.identifiers where evidence_id=p_evidence_id)
$$;

create or replace function security.admin_evidence_has_source_null(p_evidence_id uuid)
returns boolean
language sql
stable
set search_path = pg_catalog, catalogue, scholarship
as $$
  select exists(
    select 1 from catalogue.course_fees x
      where x.evidence_id=p_evidence_id and x.amount is null
    union all
    select 1 from catalogue.course_intakes x
      where x.evidence_id=p_evidence_id and x.intake_label is null and x.intake_year is null and x.start_date is null
    union all
    select 1 from catalogue.course_english_requirements x
      where x.evidence_id=p_evidence_id and x.overall_score is null and coalesce(x.component_scores,'{}'::jsonb)='{}'::jsonb
    union all
    select 1 from catalogue.course_links x
      where x.evidence_id=p_evidence_id and x.url is null
    union all
    select 1 from catalogue.course_registrations x
      where x.evidence_id=p_evidence_id and x.registration_code is null
    union all
    select 1 from catalogue.course_study_level_observations x
      where x.evidence_id=p_evidence_id and x.source_value is null
    union all
    select 1 from catalogue.course_field_observations x
      where x.evidence_id=p_evidence_id and x.source_field_code is null and x.source_field_name is null
    union all
    select 1 from catalogue.provider_outcomes x
      where x.evidence_id=p_evidence_id and x.metric_value is null
    union all
    select 1 from catalogue.student_flow_observations x
      where x.evidence_id=p_evidence_id and x.metric_value is null and coalesce(x.is_suppressed,false)=false
    union all
    select 1 from scholarship.criteria x
      where x.evidence_id=p_evidence_id
        and x.value_text is null and x.value_number is null and x.value_codes is null and x.value_json is null
    union all
    select 1 from scholarship.award_tiers x
      where x.evidence_id=p_evidence_id and x.amount is null and x.percentage is null and x.maximum_amount is null
    limit 1
  )
$$;

create or replace function security.admin_evidence_has_unresolved_conflict(p_evidence_id uuid)
returns boolean
language sql
stable
set search_path = pg_catalog, pipeline, workflow
as $$
  select exists(
    select 1
    from workflow.review_queue rq
    join pipeline.claims cl on cl.id=rq.candidate_claim_id
    where cl.evidence_id=p_evidence_id
      and lower(coalesce(rq.status,'open')) not in ('closed','resolved','accepted','rejected')
  )
$$;

create or replace function security.admin_evidence_operational_status(p_evidence_id uuid)
returns text
language plpgsql
stable
set search_path = pg_catalog, security, pipeline
as $$
declare
  e pipeline.evidence_artifacts%rowtype;
  v_count bigint;
begin
  select * into e from pipeline.evidence_artifacts where id=p_evidence_id;
  if e.id is null then return 'not_found'; end if;
  if security.admin_evidence_has_unresolved_conflict(p_evidence_id) then return 'conflict'; end if;
  if exists(select 1 from pipeline.claims cl where cl.evidence_id=p_evidence_id and lower(coalesce(cl.status,''))='rejected') then return 'rejected'; end if;
  if security.admin_evidence_has_source_null(p_evidence_id) then return 'source_null'; end if;
  v_count:=security.admin_evidence_observation_count(p_evidence_id);
  if v_count=0 then return 'missing_extraction'; end if;
  if lower(coalesce(e.metadata->>'freshness_state',''))='stale' or lower(coalesce(e.metadata->>'stale','false'))='true' then return 'stale'; end if;
  if e.valid_to is not null and e.valid_to<now() then return 'superseded'; end if;
  if exists(select 1 from pipeline.evidence_artifacts n where n.supersedes_evidence_id=p_evidence_id) then return 'superseded'; end if;
  return 'current';
end
$$;

create or replace function security.admin_evidence_matches_entity(
  p_evidence_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_provider_id uuid
)
returns boolean
language plpgsql
stable
set search_path = pg_catalog, catalogue, scholarship
as $$
declare
  v_type text:=lower(nullif(trim(coalesce(p_entity_type,'')),''));
begin
  if p_provider_id is not null then
    if exists(
      select 1 from catalogue.course_fees x join catalogue.courses c on c.id=x.course_id
      where x.evidence_id=p_evidence_id and c.provider_id=p_provider_id
      union all
      select 1 from catalogue.course_registrations x join catalogue.courses c on c.id=x.course_id
      where x.evidence_id=p_evidence_id and c.provider_id=p_provider_id
      union all
      select 1 from catalogue.course_regulatory_observations x join catalogue.courses c on c.id=x.course_id
      where x.evidence_id=p_evidence_id and c.provider_id=p_provider_id
      union all
      select 1 from catalogue.provider_outcomes x where x.evidence_id=p_evidence_id and x.provider_id=p_provider_id
      union all
      select 1 from catalogue.provider_registrations x where x.evidence_id=p_evidence_id and x.provider_id=p_provider_id
      union all
      select 1 from scholarship.scholarships x where x.evidence_id=p_evidence_id and x.provider_id=p_provider_id
      limit 1
    ) then return true; end if;
    return false;
  end if;

  if p_entity_id is null and v_type is null then return true; end if;

  if v_type='course' then
    return exists(
      select 1 from catalogue.course_fees x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.course_id=p_entity_id)
      union all select 1 from catalogue.course_intakes x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.course_id=p_entity_id)
      union all select 1 from catalogue.course_english_requirements x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.course_id=p_entity_id)
      union all select 1 from catalogue.course_links x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.course_id=p_entity_id)
      union all select 1 from catalogue.course_registrations x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.course_id=p_entity_id)
      union all select 1 from catalogue.course_regulatory_observations x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.course_id=p_entity_id)
      union all select 1 from catalogue.course_study_level_observations x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.course_id=p_entity_id)
      union all select 1 from catalogue.course_field_observations x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.course_id=p_entity_id)
      limit 1
    );
  elsif v_type='provider' then
    return exists(
      select 1 from catalogue.provider_outcomes x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.provider_id=p_entity_id)
      union all select 1 from catalogue.provider_registrations x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.provider_id=p_entity_id)
      union all select 1 from catalogue.provider_identifiers x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.provider_id=p_entity_id)
      limit 1
    );
  elsif v_type='campus' then
    return exists(select 1 from catalogue.campuses x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.id=p_entity_id));
  elsif v_type='scholarship' then
    return exists(
      select 1 from scholarship.scholarships x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.id=p_entity_id)
      union all select 1 from scholarship.offering_cycles x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.scholarship_id=p_entity_id)
      union all select 1 from scholarship.application_windows x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.scholarship_id=p_entity_id)
      union all select 1 from scholarship.scopes x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.scholarship_id=p_entity_id)
      union all select 1 from scholarship.criteria x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.scholarship_id=p_entity_id)
      union all select 1 from scholarship.award_tiers x where x.evidence_id=p_evidence_id and (p_entity_id is null or x.scholarship_id=p_entity_id)
      limit 1
    );
  elsif v_type is null and p_entity_id is not null then
    return security.admin_evidence_matches_entity(p_evidence_id,'course',p_entity_id,null)
        or security.admin_evidence_matches_entity(p_evidence_id,'provider',p_entity_id,null)
        or security.admin_evidence_matches_entity(p_evidence_id,'campus',p_entity_id,null)
        or security.admin_evidence_matches_entity(p_evidence_id,'scholarship',p_entity_id,null);
  end if;
  return false;
end
$$;

create or replace function security.admin_evidence_page(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, pipeline, ref, auth, storage
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce((p_args->>'limit')::integer,50),1),200);
  v_offset integer:=greatest(coalesce((p_args->>'offset')::integer,0),0);
  v_query text:=nullif(trim(coalesce(p_args->>'query','')), '');
  v_country text:=upper(nullif(trim(coalesce(p_args->>'country','')), ''));
  v_source_id uuid:=nullif(p_args->>'source_id','')::uuid;
  v_layer text:=upper(nullif(trim(coalesce(p_args->>'layer','')), ''));
  v_entity_type text:=nullif(trim(coalesce(p_args->>'entity_type','')), '');
  v_entity_id uuid:=nullif(p_args->>'entity_id','')::uuid;
  v_provider_id uuid:=nullif(p_args->>'provider_id','')::uuid;
  v_job_id uuid:=nullif(p_args->>'job_id','')::uuid;
  v_evidence_type text:=nullif(trim(coalesce(p_args->>'evidence_type','')), '');
  v_mime text:=nullif(trim(coalesce(p_args->>'mime','')), '');
  v_hash text:=lower(nullif(trim(coalesce(p_args->>'hash','')), ''));
  v_job_status text:=nullif(trim(coalesce(p_args->>'job_status','')), '');
  v_status text:=lower(nullif(trim(coalesce(p_args->>'status','')), ''));
  v_extraction_state text:=nullif(trim(coalesce(p_args->>'extraction_state','')), '');
  v_freshness text:=lower(nullif(trim(coalesce(p_args->>'freshness','')), ''));
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

  with filtered as materialized (
    select
      e.id,e.source_id,e.job_id,e.evidence_type,e.source_url,e.content_hash,e.mime_type,e.captured_at,
      e.valid_from,e.valid_to,e.supersedes_evidence_id,
      s.label source_label,s.source_type,s.status source_status,s.url authority_url,
      co.iso_alpha2 country_code,
      j.job_type,j.domain job_domain,j.status job_status,j.started_at job_started_at,j.completed_at job_completed_at,
      security.admin_evidence_layer(e.storage_path,e.evidence_type,e.metadata,s.source_type) layer_code
    from pipeline.evidence_artifacts e
    left join pipeline.sources s on s.id=e.source_id
    left join ref.countries co on co.id=s.country_id
    left join pipeline.jobs j on j.id=e.job_id
    where
      (v_query is null or
        e.id::text ilike '%'||v_query||'%' or
        coalesce(s.label,'') ilike '%'||v_query||'%' or
        coalesce(s.source_type,'') ilike '%'||v_query||'%' or
        coalesce(s.url,'') ilike '%'||v_query||'%' or
        coalesce(e.source_url,'') ilike '%'||v_query||'%' or
        coalesce(e.content_hash,'') ilike '%'||v_query||'%' or
        coalesce(j.job_type,'') ilike '%'||v_query||'%' or
        coalesce(j.domain,'') ilike '%'||v_query||'%' or
        coalesce(e.metadata::text,'') ilike '%'||v_query||'%' or
        coalesce(e.storage_path,'') ilike '%'||v_query||'%')
      and (v_country is null or co.iso_alpha2=v_country)
      and (v_source_id is null or e.source_id=v_source_id)
      and (v_layer is null or security.admin_evidence_layer(e.storage_path,e.evidence_type,e.metadata,s.source_type)=v_layer)
      and (v_job_id is null or e.job_id=v_job_id)
      and (v_evidence_type is null or e.evidence_type=v_evidence_type)
      and (v_mime is null or e.mime_type=v_mime)
      and (v_hash is null or lower(coalesce(e.content_hash,'')) like v_hash||'%')
      and (v_job_status is null or j.status=v_job_status)
      and (v_status is null or security.admin_evidence_operational_status(e.id)=v_status)
      and security.admin_evidence_matches_entity(e.id,v_entity_type,v_entity_id,v_provider_id)
      and (v_conflicts is null or security.admin_evidence_has_unresolved_conflict(e.id)=v_conflicts)
      and (
        v_freshness is null
        or (v_freshness='stale' and (lower(coalesce(e.metadata->>'freshness_state',''))='stale' or lower(coalesce(e.metadata->>'stale','false'))='true'))
        or (v_freshness='expired' and e.valid_to is not null and e.valid_to<now())
        or (v_freshness='current' and e.valid_to is not null and e.valid_to>=now())
        or (v_freshness='no_policy' and e.valid_to is null and lower(coalesce(e.metadata->>'freshness_state',''))<>'stale' and lower(coalesce(e.metadata->>'stale','false'))<>'true')
      )
      and (v_verified_from is null or security.admin_evidence_verification_at(e.id)>=v_verified_from)
      and (v_verified_to is null or security.admin_evidence_verification_at(e.id)<v_verified_to)
      and (
        v_extraction_state is null
        or (v_extraction_state='extracted' and security.admin_evidence_observation_count(e.id)>0)
        or (v_extraction_state='missing_extraction' and security.admin_evidence_observation_count(e.id)=0)
        or (v_extraction_state='rejected' and exists(select 1 from pipeline.claims cl where cl.evidence_id=e.id and lower(coalesce(cl.status,''))='rejected'))
      )
  ),
  page as materialized (
    select *
    from filtered
    order by
      case when v_sort='source' and v_direction='asc' then source_label end asc nulls last,
      case when v_sort='source' and v_direction='desc' then source_label end desc nulls last,
      case when v_sort='type' and v_direction='asc' then evidence_type end asc nulls last,
      case when v_sort='type' and v_direction='desc' then evidence_type end desc nulls last,
      case when v_sort='layer' and v_direction='asc' then layer_code end asc nulls last,
      case when v_sort='layer' and v_direction='desc' then layer_code end desc nulls last,
      case when v_sort='captured' and v_direction='asc' then captured_at end asc nulls last,
      case when v_sort='captured' and v_direction='desc' then captured_at end desc nulls last,
      captured_at desc nulls last,id
    limit v_limit offset v_offset
  ),
  enriched as (
    select p.*,
      security.admin_evidence_verification_at(p.id) verification_at,
      security.admin_evidence_observation_count(p.id) observation_count,
      security.admin_evidence_has_unresolved_conflict(p.id) unresolved_conflict,
      security.admin_evidence_has_source_null(p.id) has_source_null,
      security.admin_evidence_operational_status(p.id) operational_status,
      exists(select 1 from pipeline.evidence_artifacts n where n.supersedes_evidence_id=p.id) is_superseded,
      exists(select 1 from storage.objects o join pipeline.evidence_artifacts ee on ee.id=p.id
             where o.bucket_id='evidence' and o.name=ee.storage_path) storage_available
    from page p
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(
      jsonb_build_object(
        'id',x.id,
        'country_code',x.country_code,
        'source_id',x.source_id,
        'source_label',x.source_label,
        'source_type',x.source_type,
        'source_status',x.source_status,
        'authority_url',x.authority_url,
        'layer',x.layer_code,
        'job_id',x.job_id,
        'job_type',x.job_type,
        'job_domain',x.job_domain,
        'job_status',x.job_status,
        'evidence_type',x.evidence_type,
        'mime_type',x.mime_type,
        'captured_at',x.captured_at,
        'valid_from',x.valid_from,
        'valid_to',x.valid_to,
        'content_hash',x.content_hash,
        'verification_at',x.verification_at,
        'extraction_state',case
          when exists(select 1 from pipeline.claims cl where cl.evidence_id=x.id and lower(coalesce(cl.status,''))='rejected') and x.observation_count=0 then 'rejected'
          when x.observation_count>0 then 'extracted'
          else 'missing_extraction' end,
        'observation_count',x.observation_count,
        'has_source_null',x.has_source_null,
        'status',x.operational_status,
        'freshness_state',case
          when lower(coalesce((select e2.metadata->>'freshness_state' from pipeline.evidence_artifacts e2 where e2.id=x.id),''))='stale'
            or lower(coalesce((select e2.metadata->>'stale' from pipeline.evidence_artifacts e2 where e2.id=x.id),'false'))='true' then 'stale'
          when x.valid_to is not null and x.valid_to<now() then 'expired'
          when x.valid_to is not null then 'current'
          else 'no_policy' end,
        'unresolved_conflict',x.unresolved_conflict,
        'history_state',case when x.is_superseded then 'superseded' when x.supersedes_evidence_id is not null then 'superseding_snapshot' else 'current_or_unversioned' end,
        'storage_available',x.storage_available
      ) order by
        case when v_sort='source' and v_direction='asc' then x.source_label end asc nulls last,
        case when v_sort='source' and v_direction='desc' then x.source_label end desc nulls last,
        case when v_sort='type' and v_direction='asc' then x.evidence_type end asc nulls last,
        case when v_sort='type' and v_direction='desc' then x.evidence_type end desc nulls last,
        case when v_sort='layer' and v_direction='asc' then x.layer_code end asc nulls last,
        case when v_sort='layer' and v_direction='desc' then x.layer_code end desc nulls last,
        case when v_sort='captured' and v_direction='asc' then x.captured_at end asc nulls last,
        case when v_sort='captured' and v_direction='desc' then x.captured_at end desc nulls last,
        x.captured_at desc nulls last,x.id
    ) from enriched x),'[]'::jsonb),
    'total',(select count(*) from filtered),
    'limit',v_limit,
    'offset',v_offset
  ) into v_result;
  return v_result;
end
$$;

create or replace function security.admin_evidence_filter_options()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, pipeline, ref, auth
as $$
declare v_rank integer:=0; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
  select jsonb_build_object(
    'countries',coalesce((select jsonb_agg(x order by x->>'code') from (
      select jsonb_build_object('code',co.iso_alpha2,'name',co.name) x
      from pipeline.evidence_artifacts e join pipeline.sources s on s.id=e.source_id join ref.countries co on co.id=s.country_id
      group by co.iso_alpha2,co.name) q),'[]'::jsonb),
    'sources',coalesce((select jsonb_agg(x order by x->>'name') from (
      select jsonb_build_object('code',s.id,'name',s.label,'source_type',s.source_type) x
      from pipeline.evidence_artifacts e join pipeline.sources s on s.id=e.source_id
      group by s.id,s.label,s.source_type) q),'[]'::jsonb),
    'layers',coalesce((select jsonb_agg(x order by x->>'code') from (
      select jsonb_build_object('code',security.admin_evidence_layer(e.storage_path,e.evidence_type,e.metadata,s.source_type),'name',security.admin_evidence_layer(e.storage_path,e.evidence_type,e.metadata,s.source_type)) x
      from pipeline.evidence_artifacts e left join pipeline.sources s on s.id=e.source_id
      group by 1) q),'[]'::jsonb),
    'entity_types',jsonb_build_array(
      jsonb_build_object('code','provider','name','Provider'),
      jsonb_build_object('code','course','name','Course'),
      jsonb_build_object('code','campus','name','Campus'),
      jsonb_build_object('code','scholarship','name','Scholarship')
    ),
    'evidence_types',coalesce((select jsonb_agg(jsonb_build_object('code',evidence_type,'name',evidence_type) order by evidence_type) from (select distinct evidence_type from pipeline.evidence_artifacts where evidence_type is not null) q),'[]'::jsonb),
    'mimes',coalesce((select jsonb_agg(jsonb_build_object('code',mime_type,'name',mime_type) order by mime_type) from (select distinct mime_type from pipeline.evidence_artifacts where mime_type is not null) q),'[]'::jsonb),
    'job_statuses',coalesce((select jsonb_agg(jsonb_build_object('code',status,'name',status) order by status) from (select distinct j.status from pipeline.evidence_artifacts e join pipeline.jobs j on j.id=e.job_id where j.status is not null) q),'[]'::jsonb),
    'statuses',jsonb_build_array(
      jsonb_build_object('code','current','name','Current'),
      jsonb_build_object('code','missing_extraction','name','Missing extraction'),
      jsonb_build_object('code','source_null','name','Source-null value'),
      jsonb_build_object('code','stale','name','Stale'),
      jsonb_build_object('code','conflict','name','Unresolved conflict'),
      jsonb_build_object('code','rejected','name','Rejected'),
      jsonb_build_object('code','superseded','name','Superseded')
    ),
    'extraction_states',jsonb_build_array(
      jsonb_build_object('code','extracted','name','Extracted / linked'),
      jsonb_build_object('code','missing_extraction','name','Missing extraction'),
      jsonb_build_object('code','rejected','name','Rejected')
    ),
    'freshness_states',jsonb_build_array(
      jsonb_build_object('code','stale','name','Stale (policy-backed only)'),
      jsonb_build_object('code','expired','name','Expired validity'),
      jsonb_build_object('code','current','name','Within validity'),
      jsonb_build_object('code','no_policy','name','No freshness policy')
    )
  ) into v_result;
  return v_result;
end
$$;

create or replace function security.admin_evidence_detail(p_evidence_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, pipeline, workflow, ref, auth, storage
as $$
declare v_rank integer:=0; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;

  select jsonb_build_object(
    'artifact',jsonb_build_object(
      'id',e.id,
      'evidence_type',e.evidence_type,
      'layer',security.admin_evidence_layer(e.storage_path,e.evidence_type,e.metadata,s.source_type),
      'source_url',e.source_url,
      'captured_at',e.captured_at,
      'snapshot_version',coalesce(e.metadata->>'snapshot_version',e.metadata->>'source_version',e.metadata->>'worker_version',e.metadata->>'version'),
      'content_hash',e.content_hash,
      'mime_type',e.mime_type,
      'valid_from',e.valid_from,
      'valid_to',e.valid_to,
      'verification_at',security.admin_evidence_verification_at(e.id),
      'extraction_state',case
        when exists(select 1 from pipeline.claims cl where cl.evidence_id=e.id and lower(coalesce(cl.status,''))='rejected')
             and security.admin_evidence_observation_count(e.id)=0 then 'rejected'
        when security.admin_evidence_observation_count(e.id)>0 then 'extracted'
        else 'missing_extraction' end,
      'observation_count',security.admin_evidence_observation_count(e.id),
      'has_source_null',security.admin_evidence_has_source_null(e.id),
      'status',security.admin_evidence_operational_status(e.id),
      'freshness_state',case
        when lower(coalesce(e.metadata->>'freshness_state',''))='stale' or lower(coalesce(e.metadata->>'stale','false'))='true' then 'stale'
        when e.valid_to is not null and e.valid_to<now() then 'expired'
        when e.valid_to is not null then 'current'
        else 'no_policy' end,
      'metadata',security.admin_redact_json(e.metadata)
    ),
    'source',case when s.id is null then null else jsonb_build_object(
      'id',s.id,'label',s.label,'source_type',s.source_type,'authority_url',s.url,'status',s.status,'trust_rank',s.trust_rank,
      'country_code',co.iso_alpha2,'last_checked_at',s.last_checked_at,'last_success_at',s.last_success_at,'last_failure_at',s.last_failure_at,
      'metadata',security.admin_redact_json(s.metadata)
    ) end,
    'job',case when j.id is null then null else jsonb_build_object(
      'id',j.id,'job_type',j.job_type,'domain',j.domain,'status',j.status,'started_at',j.started_at,'completed_at',j.completed_at,
      'attempt_count',j.attempt_count
    ) end,
    'storage',jsonb_build_object(
      'available',o.id is not null,
      'size_bytes',case when jsonb_typeof(o.metadata->'size')='number' then o.metadata->'size' else null end,
      'content_type',coalesce(o.metadata->>'mimetype',e.mime_type),
      'object_created_at',o.created_at,
      'object_updated_at',o.updated_at,
      'preview_allowed',(o.id is not null and lower(coalesce(e.mime_type,'')) in ('application/pdf','image/png','image/jpeg','text/plain','application/json')),
      'download_allowed',(o.id is not null)
    ),
    'supersession',jsonb_build_object(
      'predecessor',case when prev.id is null then null else jsonb_build_object('id',prev.id,'captured_at',prev.captured_at,'content_hash',prev.content_hash) end,
      'successors',coalesce((select jsonb_agg(jsonb_build_object('id',n.id,'captured_at',n.captured_at,'content_hash',n.content_hash) order by n.captured_at) from pipeline.evidence_artifacts n where n.supersedes_evidence_id=e.id),'[]'::jsonb)
    ),
    'claims',coalesce((select jsonb_agg(jsonb_build_object(
      'id',cl.id,'entity_id',cl.entity_id,'field_code',cl.field_code,'value',security.admin_redact_json(cl.value_json),
      'layer',cl.layer,'confidence',cl.confidence,'status',cl.status,'created_at',cl.created_at
    ) order by cl.created_at desc) from pipeline.claims cl where cl.evidence_id=e.id),'[]'::jsonb),
    'reviews',coalesce((select jsonb_agg(jsonb_build_object(
      'id',rq.id,'entity_id',rq.entity_id,'domain',rq.domain,'field_code',rq.field_code,'priority',rq.priority,'status',rq.status,
      'created_at',rq.created_at,'updated_at',rq.updated_at,'closed_at',rq.closed_at
    ) order by rq.created_at desc)
      from workflow.review_queue rq join pipeline.claims cl on cl.id=rq.candidate_claim_id where cl.evidence_id=e.id),'[]'::jsonb),
    'review_actions',coalesce((select jsonb_agg(jsonb_build_object(
      'id',ra.id,'review_id',ra.review_id,'action',ra.action,'reason',ra.reason,'created_at',ra.created_at
    ) order by ra.created_at desc) from workflow.review_actions ra where ra.evidence_id=e.id),'[]'::jsonb),
    'change_control_ids',case
      when jsonb_typeof(e.metadata->'change_control_ids')='array' then e.metadata->'change_control_ids'
      when e.metadata ? 'change_control_id' then jsonb_build_array(e.metadata->>'change_control_id')
      else '[]'::jsonb end,
    'unresolved_conflict',security.admin_evidence_has_unresolved_conflict(e.id)
  )
  into v_result
  from pipeline.evidence_artifacts e
  left join pipeline.sources s on s.id=e.source_id
  left join ref.countries co on co.id=s.country_id
  left join pipeline.jobs j on j.id=e.job_id
  left join pipeline.evidence_artifacts prev on prev.id=e.supersedes_evidence_id
  left join storage.objects o on o.bucket_id='evidence' and o.name=e.storage_path
  where e.id=p_evidence_id;

  return coalesce(v_result,'{}'::jsonb);
end
$$;

create or replace function security.admin_evidence_observations(p_evidence_id uuid,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, catalogue, scholarship, ref, auth
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce((p_args->>'limit')::integer,50),1),200);
  v_offset integer:=greatest(coalesce((p_args->>'offset')::integer,0),0);
  v_entity_type text:=lower(nullif(trim(coalesce(p_args->>'entity_type','')), ''));
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;

  with obs as (
    select 'course_fee'::text observation_type,cf.id observation_id,'course'::text entity_type,c.id entity_id,
      c.canonical_title entity_label,c.course_code entity_code,c.provider_id,p.canonical_name provider_label,
      coalesce(cf.fee_type,'fee') field_code,
      security.admin_redact_json(to_jsonb(cf)-'source_id'-'evidence_id') value_json,
      cf.status,
      case when lower(coalesce(cf.status,''))='rejected' then 'rejected'
           when cf.amount is null then 'source_null'
           when cf.valid_to is not null and cf.valid_to<now() then 'superseded'
           else 'current' end value_state,
      cf.created_at observed_at,cf.last_verified_at verified_at,cf.valid_from::timestamptz valid_from,cf.valid_to::timestamptz valid_to
    from catalogue.course_fees cf join catalogue.courses c on c.id=cf.course_id join catalogue.providers p on p.id=c.provider_id
    where cf.evidence_id=p_evidence_id

    union all
    select 'course_intake',ci.id,'course',c.id,c.canonical_title,c.course_code,c.provider_id,p.canonical_name,
      'intake',
      security.admin_redact_json(to_jsonb(ci)-'source_id'-'evidence_id'),
      ci.status,
      case when lower(coalesce(ci.status,''))='rejected' then 'rejected'
           when ci.intake_label is null and ci.intake_year is null and ci.start_date is null then 'source_null'
           else 'current' end,
      null::timestamptz,null::timestamptz,null::timestamptz,null::timestamptz
    from catalogue.course_intakes ci join catalogue.courses c on c.id=ci.course_id join catalogue.providers p on p.id=c.provider_id
    where ci.evidence_id=p_evidence_id

    union all
    select 'course_english',ce.id,'course',c.id,c.canonical_title,c.course_code,c.provider_id,p.canonical_name,
      'english_requirement',
      security.admin_redact_json(to_jsonb(ce)-'source_id'-'evidence_id'),
      ce.status,
      case when lower(coalesce(ce.status,''))='rejected' then 'rejected'
           when ce.overall_score is null and coalesce(ce.component_scores,'{}'::jsonb)='{}'::jsonb then 'source_null'
           when ce.valid_to is not null and ce.valid_to<now() then 'superseded'
           else 'current' end,
      null::timestamptz,ce.last_verified_at,ce.valid_from::timestamptz,ce.valid_to::timestamptz
    from catalogue.course_english_requirements ce join catalogue.courses c on c.id=ce.course_id join catalogue.providers p on p.id=c.provider_id
    where ce.evidence_id=p_evidence_id

    union all
    select 'course_link',cl.id,'course',c.id,c.canonical_title,c.course_code,c.provider_id,p.canonical_name,
      coalesce('link:'||cl.link_type,'link'),
      security.admin_redact_json(to_jsonb(cl)-'source_id'-'evidence_id'),
      cl.status,
      case when lower(coalesce(cl.status,''))='rejected' then 'rejected'
           when cl.url is null then 'source_null'
           when cl.valid_to is not null and cl.valid_to<now() then 'superseded'
           else 'current' end,
      cl.created_at,cl.last_verified_at,cl.valid_from::timestamptz,cl.valid_to::timestamptz
    from catalogue.course_links cl join catalogue.courses c on c.id=cl.course_id join catalogue.providers p on p.id=c.provider_id
    where cl.evidence_id=p_evidence_id

    union all
    select 'course_registration',cr.id,'course',c.id,c.canonical_title,c.course_code,c.provider_id,p.canonical_name,
      coalesce('registration:'||cr.scheme,'registration'),
      security.admin_redact_json(to_jsonb(cr)-'source_id'-'evidence_id'),
      cr.status,
      case when lower(coalesce(cr.status,''))='rejected' then 'rejected'
           when cr.registration_code is null then 'source_null'
           when cr.valid_to is not null and cr.valid_to<now() then 'superseded'
           else 'current' end,
      null::timestamptz,null::timestamptz,cr.valid_from::timestamptz,cr.valid_to::timestamptz
    from catalogue.course_registrations cr join catalogue.courses c on c.id=cr.course_id join catalogue.providers p on p.id=c.provider_id
    where cr.evidence_id=p_evidence_id

    union all
    select 'course_regulatory',cro.id,'course',c.id,c.canonical_title,c.course_code,c.provider_id,p.canonical_name,
      'regulatory_facts',
      security.admin_redact_json(to_jsonb(cro)-'source_id'-'evidence_id'),
      cro.status,
      case when lower(coalesce(cro.status,''))='rejected' then 'rejected'
           when cro.valid_to is not null and cro.valid_to<now() then 'superseded'
           else 'current' end,
      cro.observed_at,cro.last_verified_at,cro.valid_from::timestamptz,cro.valid_to::timestamptz
    from catalogue.course_regulatory_observations cro join catalogue.courses c on c.id=cro.course_id join catalogue.providers p on p.id=c.provider_id
    where cro.evidence_id=p_evidence_id

    union all
    select 'course_study_level',sl.id,'course',c.id,c.canonical_title,c.course_code,c.provider_id,p.canonical_name,
      'study_level',
      security.admin_redact_json(to_jsonb(sl)-'source_id'-'evidence_id'),
      sl.status,
      case when lower(coalesce(sl.status,''))='rejected' then 'rejected'
           when sl.source_value is null then 'source_null'
           when sl.valid_to is not null and sl.valid_to<now() then 'superseded'
           else 'current' end,
      sl.observed_at,sl.last_verified_at,sl.valid_from::timestamptz,sl.valid_to::timestamptz
    from catalogue.course_study_level_observations sl join catalogue.courses c on c.id=sl.course_id join catalogue.providers p on p.id=c.provider_id
    where sl.evidence_id=p_evidence_id

    union all
    select 'course_field',fo.id,'course',c.id,c.canonical_title,c.course_code,c.provider_id,p.canonical_name,
      'field_of_study',
      security.admin_redact_json(to_jsonb(fo)-'source_id'-'evidence_id'),
      fo.status,
      case when lower(coalesce(fo.status,''))='rejected' then 'rejected'
           when fo.source_field_code is null and fo.source_field_name is null then 'source_null'
           else 'current' end,
      fo.observed_at,null::timestamptz,null::timestamptz,null::timestamptz
    from catalogue.course_field_observations fo join catalogue.courses c on c.id=fo.course_id join catalogue.providers p on p.id=c.provider_id
    where fo.evidence_id=p_evidence_id

    union all
    select 'provider_outcome',po.id,'provider',p.id,p.canonical_name,null::text,p.id,p.canonical_name,
      'outcome:'||po.metric_id::text,
      security.admin_redact_json(to_jsonb(po)-'source_id'-'evidence_id'),
      po.status,
      case when lower(coalesce(po.status,''))='rejected' then 'rejected'
           when po.metric_value is null then 'source_null' else 'current' end,
      po.observed_at,null::timestamptz,null::timestamptz,null::timestamptz
    from catalogue.provider_outcomes po join catalogue.providers p on p.id=po.provider_id
    where po.evidence_id=p_evidence_id

    union all
    select 'student_flow',sf.id,
      case when sf.course_id is not null then 'course' when sf.provider_id is not null then 'provider' else 'aggregate' end,
      coalesce(sf.course_id,sf.provider_id),coalesce(c.canonical_title,p.canonical_name,sf.source_geography_name),
      c.course_code,coalesce(c.provider_id,sf.provider_id),coalesce(cp.canonical_name,p.canonical_name),
      'student_flow:'||sf.metric_id::text,
      security.admin_redact_json(to_jsonb(sf)-'source_id'-'evidence_id'),
      sf.status,
      case when sf.is_suppressed then 'suppressed'
           when lower(coalesce(sf.status,''))='rejected' then 'rejected'
           when sf.metric_value is null then 'source_null' else 'current' end,
      sf.observed_at,null::timestamptz,null::timestamptz,null::timestamptz
    from catalogue.student_flow_observations sf
    left join catalogue.courses c on c.id=sf.course_id
    left join catalogue.providers cp on cp.id=c.provider_id
    left join catalogue.providers p on p.id=sf.provider_id
    where sf.evidence_id=p_evidence_id

    union all
    select 'scholarship',s.id,'scholarship',s.id,s.name,s.stable_key,s.provider_id,p.canonical_name,
      'scholarship',
      security.admin_redact_json(to_jsonb(s)-'source_id'-'evidence_id'),
      s.lifecycle_status,
      case when lower(coalesce(s.lifecycle_status,''))='rejected' then 'rejected' else 'current' end,
      s.created_at,null::timestamptz,null::timestamptz,null::timestamptz
    from scholarship.scholarships s join catalogue.providers p on p.id=s.provider_id
    where s.evidence_id=p_evidence_id

    union all
    select 'scholarship_cycle',oc.id,'scholarship',s.id,s.name,s.stable_key,s.provider_id,p.canonical_name,
      'offering_cycle',
      security.admin_redact_json(to_jsonb(oc)-'source_id'-'evidence_id'),
      oc.status,
      case when lower(coalesce(oc.status,''))='rejected' then 'rejected'
           when oc.valid_to is not null and oc.valid_to<now() then 'superseded' else 'current' end,
      oc.created_at,null::timestamptz,oc.valid_from::timestamptz,oc.valid_to::timestamptz
    from scholarship.offering_cycles oc join scholarship.scholarships s on s.id=oc.scholarship_id join catalogue.providers p on p.id=s.provider_id
    where oc.evidence_id=p_evidence_id

    union all
    select 'scholarship_window',aw.id,'scholarship',s.id,s.name,s.stable_key,s.provider_id,p.canonical_name,
      'application_window',
      security.admin_redact_json(to_jsonb(aw)-'source_id'-'evidence_id'),
      aw.status,
      case when lower(coalesce(aw.status,''))='rejected' then 'rejected' else 'current' end,
      aw.created_at,null::timestamptz,null::timestamptz,null::timestamptz
    from scholarship.application_windows aw join scholarship.scholarships s on s.id=aw.scholarship_id join catalogue.providers p on p.id=s.provider_id
    where aw.evidence_id=p_evidence_id

    union all
    select 'scholarship_criterion',sc.id,'scholarship',s.id,s.name,s.stable_key,s.provider_id,p.canonical_name,
      'criterion:'||coalesce(sc.criterion_type,'unknown'),
      security.admin_redact_json(to_jsonb(sc)-'source_id'-'evidence_id'),
      sc.status,
      case when lower(coalesce(sc.status,''))='rejected' then 'rejected'
           when sc.value_text is null and sc.value_number is null and sc.value_codes is null and sc.value_json is null then 'source_null'
           else 'current' end,
      sc.created_at,null::timestamptz,null::timestamptz,null::timestamptz
    from scholarship.criteria sc join scholarship.scholarships s on s.id=sc.scholarship_id join catalogue.providers p on p.id=s.provider_id
    where sc.evidence_id=p_evidence_id

    union all
    select 'scholarship_award',at.id,'scholarship',s.id,s.name,s.stable_key,s.provider_id,p.canonical_name,
      'award_tier',
      security.admin_redact_json(to_jsonb(at)-'source_id'-'evidence_id'),
      null::text,
      case when at.amount is null and at.percentage is null and at.maximum_amount is null then 'source_null' else 'current' end,
      null::timestamptz,null::timestamptz,null::timestamptz,null::timestamptz
    from scholarship.award_tiers at join scholarship.scholarships s on s.id=at.scholarship_id join catalogue.providers p on p.id=s.provider_id
    where at.evidence_id=p_evidence_id
  ),
  filtered as materialized (
    select * from obs where v_entity_type is null or entity_type=v_entity_type
  ),
  page as (
    select * from filtered
    order by coalesce(verified_at,observed_at) desc nulls last,observation_type,entity_label,observation_id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(to_jsonb(x) order by coalesce(x.verified_at,x.observed_at) desc nulls last,x.observation_type,x.entity_label) from page x),'[]'::jsonb),
    'total',(select count(*) from filtered),
    'limit',v_limit,'offset',v_offset
  ) into v_result;
  return v_result;
end
$$;

create or replace function security.admin_evidence_entities(p_evidence_id uuid,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, catalogue, scholarship, search, publishing, auth
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce((p_args->>'limit')::integer,50),1),200);
  v_offset integer:=greatest(coalesce((p_args->>'offset')::integer,0),0);
  v_type text:=lower(nullif(trim(coalesce(p_args->>'entity_type','')), ''));
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;

  with raw as (
    select 'course'::text entity_type,course_id entity_id from catalogue.course_fees where evidence_id=p_evidence_id
    union all select 'course',course_id from catalogue.course_intakes where evidence_id=p_evidence_id
    union all select 'course',course_id from catalogue.course_english_requirements where evidence_id=p_evidence_id
    union all select 'course',course_id from catalogue.course_links where evidence_id=p_evidence_id
    union all select 'course',course_id from catalogue.course_registrations where evidence_id=p_evidence_id
    union all select 'course',course_id from catalogue.course_regulatory_observations where evidence_id=p_evidence_id
    union all select 'course',course_id from catalogue.course_study_level_observations where evidence_id=p_evidence_id
    union all select 'course',course_id from catalogue.course_field_observations where evidence_id=p_evidence_id
    union all select 'provider',provider_id from catalogue.provider_outcomes where evidence_id=p_evidence_id and provider_id is not null
    union all select 'provider',provider_id from catalogue.provider_registrations where evidence_id=p_evidence_id
    union all select 'provider',provider_id from catalogue.provider_identifiers where evidence_id=p_evidence_id
    union all select 'campus',id from catalogue.campuses where evidence_id=p_evidence_id
    union all select 'scholarship',id from scholarship.scholarships where evidence_id=p_evidence_id
    union all select 'scholarship',scholarship_id from scholarship.offering_cycles where evidence_id=p_evidence_id
    union all select 'scholarship',scholarship_id from scholarship.application_windows where evidence_id=p_evidence_id
    union all select 'scholarship',scholarship_id from scholarship.criteria where evidence_id=p_evidence_id
    union all select 'scholarship',scholarship_id from scholarship.award_tiers where evidence_id=p_evidence_id
  ),
  grouped as materialized (
    select entity_type,entity_id,count(*) link_count from raw
    where entity_id is not null and (v_type is null or entity_type=v_type)
    group by entity_type,entity_id
  ),
  resolved as materialized (
    select g.entity_type,g.entity_id,g.link_count,
      coalesce(c.canonical_title,p.canonical_name,ca.name,s.name) entity_label,
      coalesce(c.course_code,c.stable_key,p.stable_key,ca.stable_key,s.stable_key) entity_code,
      coalesce(c.provider_id,ca.provider_id,s.provider_id,case when g.entity_type='provider' then p.id end) provider_id,
      coalesce(cp.canonical_name,cap.canonical_name,sp.canonical_name,p.canonical_name) provider_label,
      coalesce(c.publication_status,p.publication_status,ca.publication_status,s.publication_status) canonical_publication_status,
      d.course_id is not null search_projected,d.publication_status search_publication_status,
      d.has_fee search_has_fee,d.has_intake search_has_intake,d.has_english search_has_english,d.has_scholarship search_has_scholarship,
      coalesce((select jsonb_agg(jsonb_build_object('channel_code',es.channel_code,'locale',es.locale,'publication_status',es.publication_status,'updated_at',es.updated_at) order by es.channel_code,es.locale) from publishing.entity_states es where es.entity_id=g.entity_id),'[]'::jsonb) consumer_publication
    from grouped g
    left join catalogue.courses c on g.entity_type='course' and c.id=g.entity_id
    left join catalogue.providers cp on cp.id=c.provider_id
    left join catalogue.providers p on g.entity_type='provider' and p.id=g.entity_id
    left join catalogue.campuses ca on g.entity_type='campus' and ca.id=g.entity_id
    left join catalogue.providers cap on cap.id=ca.provider_id
    left join scholarship.scholarships s on g.entity_type='scholarship' and s.id=g.entity_id
    left join catalogue.providers sp on sp.id=s.provider_id
    left join search.course_documents d on g.entity_type='course' and d.course_id=g.entity_id
  ),
  page as (
    select * from resolved order by entity_type,entity_label nulls last,entity_id limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.entity_type,x.entity_label) from page x),'[]'::jsonb),
    'total',(select count(*) from grouped),
    'limit',v_limit,'offset',v_offset,
    'consequence_note','Downstream Search/publication fields show the current state of related canonical entities; they are not asserted as causal consequences of this evidence unless a separate governed admission record exists.'
  ) into v_result;
  return v_result;
end
$$;

create or replace function security.admin_evidence_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, auth
as $$
declare v_id uuid;
begin
  if p_operation='evidence_page' then return security.admin_evidence_page(p_args); end if;
  if p_operation='evidence_filters' then return security.admin_evidence_filter_options(); end if;
  if p_operation='evidence_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    return security.admin_evidence_detail(v_id);
  end if;
  if p_operation='evidence_observations' then
    v_id:=nullif(p_args->>'id','')::uuid;
    return security.admin_evidence_observations(v_id,p_args);
  end if;
  if p_operation='evidence_entities' then
    v_id:=nullif(p_args->>'id','')::uuid;
    return security.admin_evidence_entities(v_id,p_args);
  end if;
  raise exception 'unsupported evidence read operation: %',p_operation using errcode='22023';
end
$$;

create or replace function public.svc_admin_evidence_access_descriptor(p_evidence_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, pipeline, storage, auth
as $$
declare v_result jsonb;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'service role required' using errcode='42501'; end if;
  select jsonb_build_object(
    'evidence_id',e.id,
    'storage_path',e.storage_path,
    'mime_type',e.mime_type,
    'available',o.id is not null
  ) into v_result
  from pipeline.evidence_artifacts e
  left join storage.objects o on o.bucket_id='evidence' and o.name=e.storage_path
  where e.id=p_evidence_id;
  return coalesce(v_result,'{}'::jsonb);
end
$$;

revoke all on function public.svc_admin_evidence_access_descriptor(uuid) from public,anon,authenticated;
grant execute on function public.svc_admin_evidence_access_descriptor(uuid) to service_role;

revoke execute on function public.ui_evidence_filter_options() from authenticated;
revoke execute on function public.ui_evidence_list(integer) from authenticated;
revoke execute on function public.ui_evidence_page(integer,integer,text,text,text,text) from authenticated;
revoke execute on function public.ui_provider_related_evidence(uuid,integer,integer,text,text) from authenticated;

create or replace function public.admin_read(p_operation text, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public, security
as $$
declare
  v_result jsonb;
  v_id uuid;
begin
  if p_operation in ('evidence_page','evidence_filters','evidence_detail','evidence_observations','evidence_entities') then
    return security.admin_evidence_read(p_operation,p_args);
  end if;
  if p_operation='courses_page' then
    return security.admin_course_page_search_state(security.admin_catalogue_page(p_operation,p_args));
  end if;
  if p_operation in ('providers_page','campuses_page','scholarships_page') then
    return security.admin_catalogue_page(p_operation,p_args);
  end if;
  if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then
    return security.admin_insights_read(p_operation,p_args);
  end if;
  if p_operation in ('reviews','jobs','sources') then
    return security.admin_operations_read(p_operation,p_args);
  end if;
  if p_operation='attributes' then
    return security.admin_pim_governance_read(p_args);
  end if;

  v_result:=security.admin_read_impl(p_operation,p_args);
  if p_operation='course_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    return v_result
      || jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))
      || jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))
      || jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id))
      || jsonb_build_object('state_summary',security.admin_course_state_summary(v_id));
  end if;
  if p_operation='scholarship_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    return v_result || jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));
  end if;
  return v_result;
end
$$;

grant execute on function security.admin_evidence_page(jsonb) to authenticated,service_role;
grant execute on function security.admin_evidence_filter_options() to authenticated,service_role;
grant execute on function security.admin_evidence_detail(uuid) to authenticated,service_role;
grant execute on function security.admin_evidence_observations(uuid,jsonb) to authenticated,service_role;
grant execute on function security.admin_evidence_entities(uuid,jsonb) to authenticated,service_role;
grant execute on function security.admin_evidence_read(text,jsonb) to authenticated,service_role;
