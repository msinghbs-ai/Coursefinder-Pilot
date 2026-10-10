CREATE OR REPLACE FUNCTION security.admin_provider_contact_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue', 'ref', 'auth'
AS $function$
declare
 v_rank int:=0;v_limit int:=least(greatest(coalesce(nullif(p_args->>'limit','')::int,50),1),200);v_offset int:=greatest(coalesce(nullif(p_args->>'offset','')::int,0),0);
 v_query text:=nullif(btrim(coalesce(p_args->>'query','')),'');v_country text:=nullif(upper(btrim(coalesce(p_args->>'country_code',''))),'');
 v_provider uuid:=nullif(p_args->>'provider_id','')::uuid;v_lifecycle text:=nullif(lower(btrim(coalesce(p_args->>'lifecycle_status',''))),'');
 v_record_type text:=nullif(lower(btrim(coalesce(p_args->>'record_type',''))),'');v_source text:=nullif(lower(btrim(coalesce(p_args->>'source_authority',''))),'');
 v_verify text:=nullif(lower(btrim(coalesce(p_args->>'verification_state',''))),'');v_has_email text:=nullif(lower(btrim(coalesce(p_args->>'has_email',''))),'');
 v_has_phone text:=nullif(lower(btrim(coalesce(p_args->>'has_phone',''))),'');v_freshness text:=nullif(lower(btrim(coalesce(p_args->>'freshness',''))),'');
 v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'provider'));v_direction text:=case when lower(coalesce(p_args->>'direction','asc'))='desc' then 'desc' else 'asc' end;
 v_id uuid;v_items jsonb;v_total bigint:=0;v_result jsonb;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank();if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

 if p_operation='provider_contacts_page' then
  with base as (
   select c.id,c.provider_id,p.canonical_name provider_name,p.stable_key provider_stable_key,co.iso_alpha2 country_code,
    c.record_type,c.lifecycle_status,c.identity_key,c.updated_at,c.deleted_at,v.id version_id,v.version_no,v.full_name,v.team_name,
    v.job_title,v.functional_area,v.region_scope,v.countries_or_markets,v.work_email,v.work_phone,v.staff_location,v.verification_state,
    v.verified_on,v.source_class,v.source_authority,v.source_url,v.source_page_title,v.evidence_id,v.source_observation_id,v.created_at version_created_at
   from pipeline.provider_contacts c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
   left join pipeline.provider_contact_versions v on v.id=c.current_version_id
   where (v_country is null or upper(co.iso_alpha2)=v_country) and (v_provider is null or c.provider_id=v_provider)
    and (v_lifecycle is null or c.lifecycle_status=v_lifecycle) and (v_record_type is null or c.record_type=v_record_type)
    and (v_source is null or lower(coalesce(v.source_authority,''))=v_source) and (v_verify is null or lower(coalesce(v.verification_state,''))=v_verify)
    and (v_has_email is null or (v_has_email='true')=(nullif(btrim(coalesce(v.work_email,'')),'') is not null))
    and (v_has_phone is null or (v_has_phone='true')=(nullif(btrim(coalesce(v.work_phone,'')),'') is not null))
    and (v_freshness is null or (v_freshness='stale' and (v.verified_on is null or v.verified_on<current_date-365))
      or (v_freshness='current' and v.verified_on is not null and v.verified_on>=current_date-365) or (v_freshness='unverified' and v.verified_on is null))
    and (v_query is null or position(lower(v_query) in lower(concat_ws(' ',p.canonical_name,p.stable_key,v.full_name,v.team_name,v.job_title,
      v.functional_area,v.region_scope,v.countries_or_markets,v.work_email,v.work_phone,v.staff_location,v.source_page_title,v.source_url)))>0)
  ), numbered as (select base.*,count(*) over() total_count from base), ordered as (
   select * from numbered order by
    case when v_direction='asc' and v_sort='provider' then lower(provider_name) end asc,
    case when v_direction='desc' and v_sort='provider' then lower(provider_name) end desc,
    case when v_direction='asc' and v_sort='contact' then lower(coalesce(full_name,team_name,'')) end asc,
    case when v_direction='desc' and v_sort='contact' then lower(coalesce(full_name,team_name,'')) end desc,
    case when v_direction='asc' and v_sort='title' then lower(coalesce(job_title,'')) end asc,
    case when v_direction='desc' and v_sort='title' then lower(coalesce(job_title,'')) end desc,
    case when v_direction='asc' and v_sort='region' then lower(coalesce(region_scope,'')) end asc,
    case when v_direction='desc' and v_sort='region' then lower(coalesce(region_scope,'')) end desc,
    case when v_direction='asc' and v_sort='verified' then verified_on end asc nulls last,
    case when v_direction='desc' and v_sort='verified' then verified_on end desc nulls last,
    case when v_direction='asc' and v_sort='status' then lifecycle_status end asc,
    case when v_direction='desc' and v_sort='status' then lifecycle_status end desc,
    lower(provider_name),lower(coalesce(full_name,team_name,'')),id limit v_limit offset v_offset
  )
  select coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),coalesce(max(total_count),0) into v_items,v_total from ordered o;
  return jsonb_build_object('items',coalesce(v_items,'[]'::jsonb),'total',v_total,'limit',v_limit,'offset',v_offset,'summary',jsonb_build_object(
   'active',(select count(*) from pipeline.provider_contacts where lifecycle_status='active'),
   'inactive',(select count(*) from pipeline.provider_contacts where lifecycle_status='inactive'),
   'deleted',(select count(*) from pipeline.provider_contacts where lifecycle_status='deleted'),
   'stale',(select count(*) from pipeline.provider_contacts c join pipeline.provider_contact_versions v on v.id=c.current_version_id where v.verified_on is null or v.verified_on<current_date-365),
   'providers',(select count(distinct provider_id) from pipeline.provider_contacts)));
 end if;

 if p_operation='provider_contact_detail' then
  v_id:=nullif(p_args->>'id','')::uuid;if v_id is null then raise exception 'contact id required' using errcode='22023'; end if;
  select jsonb_build_object(
   'contact',jsonb_build_object('id',c.id,'provider_id',c.provider_id,'provider_name',p.canonical_name,'provider_stable_key',p.stable_key,'country_code',co.iso_alpha2,
    'record_type',c.record_type,'lifecycle_status',c.lifecycle_status,'identity_key',c.identity_key,'created_at',c.created_at,'updated_at',c.updated_at,
    'deleted_at',c.deleted_at,'deleted_by',c.deleted_by,'delete_reason',c.delete_reason,'restored_at',c.restored_at,'restored_by',c.restored_by),
   'current',case when v.id is null then '{}'::jsonb else to_jsonb(v) end,
   'versions',coalesce((select jsonb_agg(to_jsonb(h) order by h.version_no desc) from (
    select vv.id,vv.version_no,vv.full_name,vv.team_name,vv.job_title,vv.functional_area,vv.region_scope,vv.countries_or_markets,vv.work_email,vv.work_phone,
     vv.staff_location,vv.verification_state,vv.verified_on,vv.source_class,vv.source_authority,vv.source_url,vv.source_page_title,vv.source_notes,
     vv.source_observation_id,vv.evidence_id,vv.import_batch_id,vv.import_row_id,vv.content_hash,vv.effective_from,vv.effective_to,vv.change_reason,vv.created_at,vv.created_by
    from pipeline.provider_contact_versions vv where vv.contact_id=c.id order by vv.version_no desc limit 100) h),'[]'::jsonb),
   'audit',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from (
    select aa.id,aa.event_type,aa.actor_id,aa.reason,aa.before_version_id,aa.after_version_id,aa.metadata,aa.created_at
    from pipeline.provider_contact_audit_events aa where aa.contact_id=c.id order by aa.created_at desc limit 100) a),'[]'::jsonb),
   'source_observations',coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'source_class',o.source_class,'source_provider',o.source_provider,'source_url',o.source_url,
    'full_name',o.full_name,'job_title',o.job_title,'team_name',o.team_name,'territory_text',o.territory_text,'territory_codes',o.territory_codes,
    'work_email',o.work_email,'work_phone',o.work_phone,'professional_profile_url',o.professional_profile_url,'evidence_id',o.evidence_id,
    'verification_state',o.verification_state,'observed_at',o.observed_at,'last_verified_at',o.last_verified_at,'is_current',o.is_current,'confidence',o.confidence)
    order by o.last_verified_at desc) from pipeline.provider_contact_observations o where o.managed_contact_id=c.id),'[]'::jsonb)
  ) into v_result from pipeline.provider_contacts c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
  left join pipeline.provider_contact_versions v on v.id=c.current_version_id where c.id=v_id;
  return coalesce(v_result,'{}'::jsonb);
 end if;

 if p_operation='provider_contact_imports' then
  if v_rank<5 then raise exception 'PIM Operator role required' using errcode='42501'; end if;
  with numbered as (select b.*,count(*) over() total_count from pipeline.provider_contact_import_batches b where v_country is null or upper(b.country_code)=v_country),
  ordered as (select * from numbered order by uploaded_at desc,id desc limit v_limit offset v_offset)
  select coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),coalesce(max(total_count),0) into v_items,v_total from ordered o;
  return jsonb_build_object('items',coalesce(v_items,'[]'::jsonb),'total',v_total,'limit',v_limit,'offset',v_offset);
 end if;

 if p_operation='provider_contact_import_detail' then
  if v_rank<5 then raise exception 'PIM Operator role required' using errcode='42501'; end if;
  v_id:=nullif(p_args->>'id','')::uuid;if v_id is null then raise exception 'import id required' using errcode='22023'; end if;
  select jsonb_build_object('batch',to_jsonb(b),'rows',coalesce((select jsonb_agg(to_jsonb(r) order by r.row_number) from (
   select rr.id,rr.row_number,rr.row_hash,rr.logical_key,rr.source_institution_name,rr.current_institution_name,rr.mapped_provider_id,p.canonical_name mapped_provider_name,
    rr.mapping_state,rr.matched_contact_id,rr.proposed_action,rr.applied_action,rr.validation_errors,rr.conflict_detail,rr.normalized_payload,rr.created_at,rr.applied_at
   from pipeline.provider_contact_import_rows rr left join catalogue.providers p on p.id=rr.mapped_provider_id where rr.batch_id=b.id order by rr.row_number limit 2000) r),'[]'::jsonb))
  into v_result from pipeline.provider_contact_import_batches b where b.id=v_id;
  return coalesce(v_result,'{}'::jsonb);
 end if;

 raise exception 'unsupported provider contact read operation: %',p_operation using errcode='22023';
end $function$
