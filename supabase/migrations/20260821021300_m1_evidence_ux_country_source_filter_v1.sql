create or replace function security.admin_evidence_filter_options()
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'security', 'pipeline', 'ref', 'auth'
as $function$
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
      select jsonb_build_object('code',s.id,'name',s.label,'source_type',s.source_type,'country_code',co.iso_alpha2) x
      from pipeline.evidence_artifacts e
      join pipeline.sources s on s.id=e.source_id
      left join ref.countries co on co.id=s.country_id
      group by s.id,s.label,s.source_type,co.iso_alpha2) q),'[]'::jsonb),
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
$function$;
