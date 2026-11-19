-- CF-CHG-20260902-080 / A30 Provider Contacts admin read and mutation contracts

create or replace function security.provider_contact_append_version(
  p_contact_id uuid,p_actor uuid,p_payload jsonb,p_source_class text,p_source_authority text,p_reason text,
  p_import_batch_id uuid default null,p_import_row_id uuid default null,p_evidence_id uuid default null,p_source_observation_id uuid default null
) returns uuid
language plpgsql security definer
set search_path to 'pg_catalog','security','pipeline'
as $$
declare
 v_contact pipeline.provider_contacts%rowtype;v_prev pipeline.provider_contact_versions%rowtype;
 v_version_no int;v_new_id uuid;v_full_name text;v_team_name text;v_job_title text;v_functional_area text;
 v_region_scope text;v_markets text;v_email text;v_phone text;v_location text;v_verification text;v_verified_on date;
 v_source_url text;v_source_page_title text;v_source_notes text;v_hash text;v_identity text;v_payload jsonb;v_domain text;
begin
 select * into v_contact from pipeline.provider_contacts where id=p_contact_id for update;
 if not found then raise exception 'managed contact not found' using errcode='P0002'; end if;
 if v_contact.current_version_id is not null then select * into v_prev from pipeline.provider_contact_versions where id=v_contact.current_version_id; end if;

 v_full_name:=case when p_payload?'full_name' then nullif(btrim(p_payload->>'full_name'),'') else v_prev.full_name end;
 v_team_name:=case when p_payload?'team_name' then nullif(btrim(p_payload->>'team_name'),'') else v_prev.team_name end;
 v_job_title:=case when p_payload?'job_title' then nullif(btrim(p_payload->>'job_title'),'') else v_prev.job_title end;
 v_functional_area:=case when p_payload?'functional_area' then nullif(btrim(p_payload->>'functional_area'),'') else v_prev.functional_area end;
 v_region_scope:=case when p_payload?'region_scope' then nullif(btrim(p_payload->>'region_scope'),'') else v_prev.region_scope end;
 v_markets:=case when p_payload?'countries_or_markets' then nullif(btrim(p_payload->>'countries_or_markets'),'') else v_prev.countries_or_markets end;
 v_email:=case when p_payload?'work_email' then nullif(lower(btrim(p_payload->>'work_email')),'') else v_prev.work_email end;
 v_phone:=case when p_payload?'work_phone' then nullif(btrim(p_payload->>'work_phone'),'') else v_prev.work_phone end;
 v_location:=case when p_payload?'staff_location' then nullif(btrim(p_payload->>'staff_location'),'') else v_prev.staff_location end;
 v_verification:=case when p_payload?'verification_state' then nullif(lower(btrim(p_payload->>'verification_state')),'') else coalesce(v_prev.verification_state,'manual') end;
 v_verified_on:=case when p_payload?'verified_on' and nullif(btrim(p_payload->>'verified_on'),'') is not null then (p_payload->>'verified_on')::date when p_payload?'verified_on' then null else v_prev.verified_on end;
 v_source_url:=case when p_payload?'source_url' then nullif(btrim(p_payload->>'source_url'),'') else v_prev.source_url end;
 v_source_page_title:=case when p_payload?'source_page_title' then nullif(btrim(p_payload->>'source_page_title'),'') else v_prev.source_page_title end;
 v_source_notes:=case when p_payload?'source_notes' then nullif(btrim(p_payload->>'source_notes'),'') else v_prev.source_notes end;

 if v_contact.record_type='named_staff' and v_full_name is null then raise exception 'named staff contact requires full_name' using errcode='22023'; end if;
 if v_contact.record_type='team_contact' and coalesce(v_team_name,v_job_title,v_functional_area,v_email,v_phone,v_source_url) is null then raise exception 'team contact requires team/function/contact/source context' using errcode='22023'; end if;
 if coalesce(v_email,v_phone,v_job_title,v_functional_area,v_region_scope,v_source_url) is null then raise exception 'contact requires meaningful assignment/contact/source context' using errcode='22023'; end if;
 if v_email is not null then
  if v_email !~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$' then raise exception 'invalid professional email' using errcode='22023'; end if;
  v_domain:=split_part(v_email,'@',2);
  if v_domain in ('gmail.com','googlemail.com','yahoo.com','yahoo.com.au','hotmail.com','outlook.com','live.com','icloud.com','proton.me','protonmail.com') then
   raise exception 'personal/free-mail address is not permitted for Provider Contacts' using errcode='22023';
  end if;
 end if;
 if v_source_url is not null and v_source_url !~* '^https?://' then raise exception 'source_url must be HTTP(S)' using errcode='22023'; end if;

 v_payload:=jsonb_build_object('full_name',v_full_name,'team_name',v_team_name,'job_title',v_job_title,'functional_area',v_functional_area,
  'region_scope',v_region_scope,'countries_or_markets',v_markets,'work_email',v_email,'work_phone',v_phone,'staff_location',v_location,
  'verification_state',v_verification,'verified_on',case when v_verified_on is null then null else v_verified_on::text end,
  'source_authority',p_source_authority,'source_url',v_source_url);
 v_hash:=security.provider_contact_payload_hash(v_payload);
 select coalesce(max(version_no),0)+1 into v_version_no from pipeline.provider_contact_versions where contact_id=p_contact_id;

 insert into pipeline.provider_contact_versions(contact_id,version_no,full_name,team_name,job_title,functional_area,region_scope,countries_or_markets,
  work_email,work_phone,staff_location,verification_state,verified_on,source_class,source_authority,source_url,source_page_title,source_notes,
  source_observation_id,evidence_id,import_batch_id,import_row_id,content_hash,effective_from,change_reason,created_at,created_by,metadata)
 values(p_contact_id,v_version_no,v_full_name,v_team_name,v_job_title,v_functional_area,v_region_scope,v_markets,v_email,v_phone,v_location,
  v_verification,v_verified_on,p_source_class,p_source_authority,v_source_url,v_source_page_title,v_source_notes,p_source_observation_id,
  p_evidence_id,p_import_batch_id,p_import_row_id,v_hash,now(),p_reason,now(),p_actor,jsonb_build_object('change_control','CF-CHG-20260902-080'))
 returning id into v_new_id;

 if v_contact.current_version_id is not null then update pipeline.provider_contact_versions set effective_to=now(),superseded_by=v_new_id where id=v_contact.current_version_id and effective_to is null; end if;
 v_identity:=security.provider_contact_identity_key(v_contact.record_type,v_full_name,v_job_title,v_region_scope,v_email,v_source_url);
 update pipeline.provider_contacts set current_version_id=v_new_id,identity_key=v_identity,updated_at=now(),updated_by=p_actor where id=p_contact_id;
 return v_new_id;
end $$;
revoke all on function security.provider_contact_append_version(uuid,uuid,jsonb,text,text,text,uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function security.provider_contact_append_version(uuid,uuid,jsonb,text,text,text,uuid,uuid,uuid,uuid) to service_role;

create or replace function security.admin_provider_contact_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','ref','auth'
as $$
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
end $$;
revoke all on function security.admin_provider_contact_read(text,jsonb) from public,anon;
grant execute on function security.admin_provider_contact_read(text,jsonb) to authenticated,service_role;

create or replace function public.provider_contact_manage(p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','public','security','pipeline','catalogue','auth'
as $$
declare v_rank int:=0;v_actor uuid:=auth.uid();v_action text:=lower(btrim(coalesce(p_action,'')));v_contact_id uuid;v_provider_id uuid;
 v_record_type text;v_identity text;v_version_id uuid;v_reason text;v_current pipeline.provider_contacts%rowtype;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank();if v_rank<5 then raise exception 'PIM Operator role required' using errcode='42501'; end if;
 if v_action='create' then
  v_provider_id:=nullif(p_payload->>'provider_id','')::uuid;
  if v_provider_id is null or not exists(select 1 from catalogue.providers where id=v_provider_id) then raise exception 'valid provider_id required' using errcode='22023'; end if;
  v_record_type:=lower(coalesce(nullif(p_payload->>'record_type',''),'named_staff'));if v_record_type not in ('named_staff','team_contact') then raise exception 'invalid record_type' using errcode='22023'; end if;
  v_identity:=security.provider_contact_identity_key(v_record_type,p_payload->>'full_name',p_payload->>'job_title',p_payload->>'region_scope',p_payload->>'work_email',p_payload->>'source_url');
  if v_identity is null then raise exception 'insufficient contact identity' using errcode='22023'; end if;
  insert into pipeline.provider_contacts(provider_id,record_type,lifecycle_status,identity_key,created_by,updated_by,metadata)
  values(v_provider_id,v_record_type,'active',v_identity,v_actor,v_actor,jsonb_build_object('origin','manual','change_control','CF-CHG-20260902-080')) returning id into v_contact_id;
  v_version_id:=security.provider_contact_append_version(v_contact_id,v_actor,p_payload,'manual','manual',coalesce(nullif(p_payload->>'reason',''),'Manual Provider Contact creation'));
  insert into pipeline.provider_contact_audit_events(contact_id,event_type,actor_id,reason,after_version_id,metadata)
  values(v_contact_id,'create',v_actor,coalesce(nullif(p_payload->>'reason',''),'Manual Provider Contact creation'),v_version_id,jsonb_build_object('change_control','CF-CHG-20260902-080'));
  return jsonb_build_object('ok',true,'action','create','contact_id',v_contact_id,'version_id',v_version_id);
 end if;
 v_contact_id:=nullif(coalesce(p_payload->>'contact_id',p_payload->>'id'),'')::uuid;if v_contact_id is null then raise exception 'contact_id required' using errcode='22023'; end if;
 select * into v_current from pipeline.provider_contacts where id=v_contact_id for update;if not found then raise exception 'managed contact not found' using errcode='P0002'; end if;
 if v_action in ('update','verify') then
  if v_current.lifecycle_status='deleted' then raise exception 'restore deleted contact before editing' using errcode='22023'; end if;
  if v_action='verify' then p_payload:=p_payload||jsonb_build_object('verification_state','current','verified_on',current_date::text); end if;
  v_reason:=coalesce(nullif(p_payload->>'reason',''),case when v_action='verify' then 'Contact verification' else 'Manual Provider Contact update' end);
  v_version_id:=security.provider_contact_append_version(v_contact_id,v_actor,p_payload,'manual','manual',v_reason,null,null,nullif(p_payload->>'evidence_id','')::uuid,null);
  insert into pipeline.provider_contact_audit_events(contact_id,event_type,actor_id,reason,before_version_id,after_version_id,metadata)
  values(v_contact_id,v_action,v_actor,v_reason,v_current.current_version_id,v_version_id,jsonb_build_object('change_control','CF-CHG-20260902-080'));
  return jsonb_build_object('ok',true,'action',v_action,'contact_id',v_contact_id,'version_id',v_version_id);
 end if;
 if v_action='delete' then
  v_reason:=nullif(btrim(coalesce(p_payload->>'reason','')),'');if v_reason is null then raise exception 'delete reason required' using errcode='22023'; end if;
  if v_current.lifecycle_status='deleted' then return jsonb_build_object('ok',true,'action','delete','contact_id',v_contact_id,'unchanged',true); end if;
  update pipeline.provider_contacts set lifecycle_status='deleted',deleted_at=now(),deleted_by=v_actor,delete_reason=v_reason,updated_at=now(),updated_by=v_actor where id=v_contact_id;
  insert into pipeline.provider_contact_audit_events(contact_id,event_type,actor_id,reason,before_version_id,metadata)
  values(v_contact_id,'delete',v_actor,v_reason,v_current.current_version_id,jsonb_build_object('change_control','CF-CHG-20260902-080'));
  return jsonb_build_object('ok',true,'action','delete','contact_id',v_contact_id);
 end if;
 if v_action='restore' then
  v_reason:=coalesce(nullif(btrim(p_payload->>'reason'),''),'Restore deleted Provider Contact');
  if v_current.lifecycle_status<>'deleted' then return jsonb_build_object('ok',true,'action','restore','contact_id',v_contact_id,'unchanged',true); end if;
  update pipeline.provider_contacts set lifecycle_status='active',deleted_at=null,deleted_by=null,delete_reason=null,restored_at=now(),restored_by=v_actor,updated_at=now(),updated_by=v_actor where id=v_contact_id;
  insert into pipeline.provider_contact_audit_events(contact_id,event_type,actor_id,reason,after_version_id,metadata)
  values(v_contact_id,'restore',v_actor,v_reason,v_current.current_version_id,jsonb_build_object('change_control','CF-CHG-20260902-080'));
  return jsonb_build_object('ok',true,'action','restore','contact_id',v_contact_id);
 end if;
 if v_action in ('deactivate','activate') then
  v_reason:=coalesce(nullif(btrim(p_payload->>'reason'),''),initcap(v_action)||' Provider Contact');
  if v_current.lifecycle_status='deleted' then raise exception 'deleted contact must be restored first' using errcode='22023'; end if;
  update pipeline.provider_contacts set lifecycle_status=case when v_action='activate' then 'active' else 'inactive' end,updated_at=now(),updated_by=v_actor where id=v_contact_id;
  insert into pipeline.provider_contact_audit_events(contact_id,event_type,actor_id,reason,after_version_id,metadata)
  values(v_contact_id,v_action,v_actor,v_reason,v_current.current_version_id,jsonb_build_object('change_control','CF-CHG-20260902-080'));
  return jsonb_build_object('ok',true,'action',v_action,'contact_id',v_contact_id);
 end if;
 raise exception 'unsupported Provider Contact action: %',v_action using errcode='22023';
end $$;
revoke all on function public.provider_contact_manage(text,jsonb) from public,anon;
grant execute on function public.provider_contact_manage(text,jsonb) to authenticated,service_role;

create or replace function public.provider_contact_export_audit(p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','public','security','pipeline','auth'
as $$
declare v_actor uuid:=auth.uid();v_rank int;v_rows int:=greatest(coalesce(nullif(p_payload->>'row_count','')::int,0),0);
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank();if v_rank<5 then raise exception 'PIM Operator role required' using errcode='42501'; end if;
 insert into pipeline.provider_contact_audit_events(event_type,actor_id,reason,metadata)
 values('export',v_actor,coalesce(nullif(p_payload->>'reason',''),'Provider Contacts export'),
 jsonb_build_object('row_count',v_rows,'filters',coalesce(p_payload->'filters','{}'::jsonb),'columns',coalesce(p_payload->'columns','[]'::jsonb),'format',coalesce(nullif(p_payload->>'format',''),'csv'),'change_control','CF-CHG-20260902-080'));
 return jsonb_build_object('ok',true,'row_count',v_rows,'audited',true);
end $$;
revoke all on function public.provider_contact_export_audit(jsonb) from public,anon;
grant execute on function public.provider_contact_export_audit(jsonb) to authenticated,service_role;

create or replace function security.admin_provider_contacts(p_provider_id uuid)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','ref','public','auth'
as $$
declare v_rank integer:=0;v_profile jsonb;v_items jsonb;v_events jsonb;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 select security.current_role_rank() into v_rank;if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
 select jsonb_build_object('profile_id',p.id,'enabled',p.enabled,'paused',p.paused,'base_url',p.base_url,'domain',p.domain,'last_run_at',p.last_run_at,'last_success_at',p.last_success_at,'last_error',p.last_error)
 into v_profile from pipeline.provider_contact_profiles p where p.provider_id=p_provider_id;
 select coalesce(jsonb_agg(row_json order by source_priority,lower(coalesce(row_json->>'territory_text','')),lower(coalesce(row_json->>'job_title','')),lower(coalesce(row_json->>'full_name',''))),'[]'::jsonb)
 into v_items from (
  select case v.source_authority when 'first_party' then 1 when 'manual' then 2 else 3 end source_priority,
  jsonb_build_object('id',c.id,'managed_contact_id',c.id,'source_class',v.source_authority,'managed_source_class',v.source_class,'source_authority',v.source_authority,
   'source_provider',coalesce(v.metadata->>'source_provider',v.source_authority),'full_name',v.full_name,'job_title',v.job_title,'team_name',coalesce(v.team_name,v.functional_area),
   'territory_text',coalesce(v.countries_or_markets,v.region_scope),'territory_codes',coalesce(v.metadata->'territory_codes','[]'::jsonb),'work_email',v.work_email,'work_phone',v.work_phone,
   'professional_profile_url',v.metadata->>'professional_profile_url','source_url',v.source_url,'evidence_id',v.evidence_id,'verification_state',v.verification_state,
   'confidence',v.metadata->'confidence','observed_at',v.effective_from,'last_verified_at',v.verified_on,
   'source_priority',case v.source_authority when 'first_party' then 'preferred' when 'manual' then 'governed_manual' else 'secondary_enrichment' end,
   'record_type',c.record_type,'lifecycle_status',c.lifecycle_status) row_json
  from pipeline.provider_contacts c join pipeline.provider_contact_versions v on v.id=c.current_version_id
  where c.provider_id=p_provider_id and c.lifecycle_status in ('active','inactive') order by 1,v.verified_on desc nulls last limit 100
 ) q;
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'event_type',e.event_type,'source_class',e.source_class,'before_state',e.before_state,'after_state',e.after_state,'detected_at',e.detected_at,'acknowledged',e.acknowledged) order by e.detected_at desc),'[]'::jsonb)
 into v_events from (select * from pipeline.provider_contact_watch_events where provider_id=p_provider_id order by detected_at desc limit 20)e;
 return jsonb_build_object('profile',coalesce(v_profile,'{}'::jsonb),'items',coalesce(v_items,'[]'::jsonb),'events',coalesce(v_events,'[]'::jsonb),'summary',jsonb_build_object(
  'current_contacts',(select count(*) from pipeline.provider_contacts where provider_id=p_provider_id and lifecycle_status='active'),
  'first_party_contacts',(select count(*) from pipeline.provider_contacts c join pipeline.provider_contact_versions v on v.id=c.current_version_id where c.provider_id=p_provider_id and c.lifecycle_status='active' and v.source_authority='first_party'),
  'manual_contacts',(select count(*) from pipeline.provider_contacts c join pipeline.provider_contact_versions v on v.id=c.current_version_id where c.provider_id=p_provider_id and c.lifecycle_status='active' and v.source_authority='manual'),
  'enriched_contacts',(select count(*) from pipeline.provider_contacts c join pipeline.provider_contact_versions v on v.id=c.current_version_id where c.provider_id=p_provider_id and c.lifecycle_status='active' and v.source_authority='licensed_enrichment'),
  'unacknowledged_changes',(select count(*) from pipeline.provider_contact_watch_events where provider_id=p_provider_id and acknowledged=false)));
end $$;
revoke all on function security.admin_provider_contacts(uuid) from public,anon;
grant execute on function security.admin_provider_contacts(uuid) to authenticated,service_role;

do $$
declare v_def text;v_marker text:=' if p_operation=''contextual_compare'' then return security.admin_contextual_compare(p_args); end if;';
v_insert text:=' if p_operation in (''provider_contacts_page'',''provider_contact_detail'',''provider_contact_imports'',''provider_contact_import_detail'') then return security.admin_provider_contact_read(p_operation,p_args); end if;'||chr(10);
begin
 select pg_get_functiondef('public.admin_read(text,jsonb)'::regprocedure) into v_def;
 if position('provider_contacts_page' in v_def)=0 then
  if position(v_marker in v_def)=0 then raise exception 'admin_read insertion marker not found'; end if;
  execute replace(v_def,v_marker,v_insert||v_marker);
 end if;
end $$;
