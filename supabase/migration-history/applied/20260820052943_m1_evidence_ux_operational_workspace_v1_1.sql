-- M1-EVIDENCE-UX operational workspace v1.1
-- Fast Evidence list path: existence checks for list; exact counts remain detail-only.

create or replace function security.admin_evidence_has_extraction(p_evidence_id uuid)
returns boolean
language sql
stable
set search_path = pg_catalog, catalogue, scholarship
as $$
  select exists(
    select 1 from catalogue.course_fees where evidence_id=p_evidence_id
    union all select 1 from catalogue.course_intakes where evidence_id=p_evidence_id
    union all select 1 from catalogue.course_english_requirements where evidence_id=p_evidence_id
    union all select 1 from catalogue.course_links where evidence_id=p_evidence_id
    union all select 1 from catalogue.course_registrations where evidence_id=p_evidence_id
    union all select 1 from catalogue.course_regulatory_observations where evidence_id=p_evidence_id
    union all select 1 from catalogue.course_study_level_observations where evidence_id=p_evidence_id
    union all select 1 from catalogue.course_field_observations where evidence_id=p_evidence_id
    union all select 1 from catalogue.course_campuses where evidence_id=p_evidence_id
    union all select 1 from catalogue.campuses where evidence_id=p_evidence_id
    union all select 1 from catalogue.provider_outcomes where evidence_id=p_evidence_id
    union all select 1 from catalogue.student_flow_observations where evidence_id=p_evidence_id
    union all select 1 from catalogue.provider_registrations where evidence_id=p_evidence_id
    union all select 1 from catalogue.provider_identifiers where evidence_id=p_evidence_id
    union all select 1 from scholarship.scholarships where evidence_id=p_evidence_id
    union all select 1 from scholarship.offering_cycles where evidence_id=p_evidence_id
    union all select 1 from scholarship.application_windows where evidence_id=p_evidence_id
    union all select 1 from scholarship.scopes where evidence_id=p_evidence_id
    union all select 1 from scholarship.criterion_groups where evidence_id=p_evidence_id
    union all select 1 from scholarship.criteria where evidence_id=p_evidence_id
    union all select 1 from scholarship.award_tiers where evidence_id=p_evidence_id
    union all select 1 from scholarship.coverage where evidence_id=p_evidence_id
    union all select 1 from scholarship.identifiers where evidence_id=p_evidence_id
    limit 1
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
begin
  select * into e from pipeline.evidence_artifacts where id=p_evidence_id;
  if e.id is null then return 'not_found'; end if;
  if security.admin_evidence_has_unresolved_conflict(p_evidence_id) then return 'conflict'; end if;
  if exists(select 1 from pipeline.claims cl where cl.evidence_id=p_evidence_id and lower(coalesce(cl.status,''))='rejected') then return 'rejected'; end if;
  if not security.admin_evidence_has_extraction(p_evidence_id) then return 'missing_extraction'; end if;
  if security.admin_evidence_has_source_null(p_evidence_id) then return 'source_null'; end if;
  if lower(coalesce(e.metadata->>'freshness_state',''))='stale' or lower(coalesce(e.metadata->>'stale','false'))='true' then return 'stale'; end if;
  if e.valid_to is not null and e.valid_to<now() then return 'superseded'; end if;
  if exists(select 1 from pipeline.evidence_artifacts n where n.supersedes_evidence_id=p_evidence_id) then return 'superseded'; end if;
  return 'current';
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

  with filtered as materialized (
    select
      e.id,e.source_id,e.job_id,e.evidence_type,e.source_url,e.content_hash,e.mime_type,e.captured_at,
      e.valid_from,e.valid_to,e.supersedes_evidence_id,
      s.label source_label,s.source_type,s.status source_status,s.url authority_url,
      co.iso_alpha2 country_code,
      j.job_type,j.domain job_domain,j.status job_status,j.started_at job_started_at,j.completed_at job_completed_at,
      security.admin_evidence_layer(e.storage_path,e.evidence_type,e.metadata,s.source_type) layer_code,
      (lower(coalesce(e.metadata->>'freshness_state',''))='stale'
        or lower(coalesce(e.metadata->>'stale','false'))='true') explicit_stale
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
        or (v_extraction_state='extracted' and security.admin_evidence_has_extraction(e.id))
        or (v_extraction_state='missing_extraction' and not security.admin_evidence_has_extraction(e.id))
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
  metrics as materialized (
    select p.*,
      security.admin_evidence_verification_at(p.id) verification_at,
      security.admin_evidence_has_extraction(p.id) has_extraction,
      security.admin_evidence_has_unresolved_conflict(p.id) unresolved_conflict,
      exists(select 1 from pipeline.claims cl where cl.evidence_id=p.id and lower(coalesce(cl.status,''))='rejected') has_rejected_claim,
      exists(select 1 from pipeline.evidence_artifacts n where n.supersedes_evidence_id=p.id) is_superseded,
      exists(select 1 from storage.objects o join pipeline.evidence_artifacts ee on ee.id=p.id
             where o.bucket_id='evidence' and o.name=ee.storage_path) storage_available
    from page p
  ),
  enriched as materialized (
    select m.*,
      case when m.has_extraction then security.admin_evidence_has_source_null(m.id) else false end has_source_null
    from metrics m
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
        'extraction_state',case when x.has_rejected_claim and not x.has_extraction then 'rejected'
                                when x.has_extraction then 'extracted' else 'missing_extraction' end,
        'has_extraction',x.has_extraction,
        'has_source_null',x.has_source_null,
        'status',case
          when x.unresolved_conflict then 'conflict'
          when x.has_rejected_claim then 'rejected'
          when not x.has_extraction then 'missing_extraction'
          when x.has_source_null then 'source_null'
          when x.explicit_stale then 'stale'
          when (x.valid_to is not null and x.valid_to<now()) or x.is_superseded then 'superseded'
          else 'current' end,
        'freshness_state',case
          when x.explicit_stale then 'stale'
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

grant execute on function security.admin_evidence_has_extraction(uuid) to authenticated,service_role;
