create or replace function public.scholarship_scope_acquisition_service(
  p_actor uuid,
  p_action text,
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','catalogue','ref','scholarship'
as $$
declare
  v_rank integer:=0; v_provider_count integer:=0; v_catalogue_ready integer:=0; v_request uuid; v_scope_name text; v_jobs integer:=0;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  if lower(coalesce(p_action,'')) not in ('preview','start') then raise exception 'unsupported action' using errcode='22023'; end if;
  if lower(coalesce(p_scope_type,'')) not in ('country','state','university') then raise exception 'invalid scope type' using errcode='22023'; end if;
  if lower(p_scope_type) in ('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;

  with scoped as (
    select distinct p.id from catalogue.providers p join ref.countries c on c.id=p.country_id
    where upper(c.iso_alpha2::text)=upper(p_country_code)
      and (lower(p_scope_type)='country' or (lower(p_scope_type)='state' and (p.subdivision_id=p_scope_id or exists(select 1 from catalogue.campuses ca where ca.provider_id=p.id and ca.subdivision_id=p_scope_id))) or (lower(p_scope_type)='university' and p.id=p_scope_id))
  ) select count(*) into v_provider_count from scoped;

  with scoped as (
    select distinct p.id from catalogue.providers p join ref.countries c on c.id=p.country_id
    where upper(c.iso_alpha2::text)=upper(p_country_code)
      and (lower(p_scope_type)='country' or (lower(p_scope_type)='state' and (p.subdivision_id=p_scope_id or exists(select 1 from catalogue.campuses ca where ca.provider_id=p.id and ca.subdivision_id=p_scope_id))) or (lower(p_scope_type)='university' and p.id=p_scope_id))
  ) select count(*) into v_catalogue_ready from scoped s where
    exists(select 1 from pipeline.scholarship_acquisition_trace t where t.provider_id=s.id and t.first_party_catalogue_url is not null)
    or exists(select 1 from pipeline.sources ps where ps.provider_id=s.id and ps.status='active' and (ps.source_type ilike '%scholar%' or ps.label ilike '%scholar%'));

  if lower(p_scope_type)='state' then select name into v_scope_name from ref.subdivisions where id=p_scope_id;
  elsif lower(p_scope_type)='university' then select canonical_name into v_scope_name from catalogue.providers where id=p_scope_id;
  else v_scope_name:=upper(p_country_code); end if;

  if lower(p_action)='preview' then return jsonb_build_object('ok',true,'domain','scholarship','action','preview','country_code',upper(p_country_code),'scope_type',lower(p_scope_type),'scope_id',p_scope_id,'scope_name',v_scope_name,'provider_count',v_provider_count,'first_party_catalogue_ready',v_catalogue_ready,'jobs_if_started',v_catalogue_ready,'catalogue_gap',greatest(v_provider_count-v_catalogue_ready,0),'publication_changed',false); end if;

  insert into pipeline.scholarship_scope_acquisition_requests(requested_by,country_code,scope_type,scope_id,provider_id,provider_count,status,metadata)
  values(p_actor,upper(p_country_code),lower(p_scope_type),p_scope_id,case when lower(p_scope_type)='university' then p_scope_id else null end,v_catalogue_ready,'queued',jsonb_build_object('scope_name',v_scope_name,'scope_provider_count',v_provider_count,'first_party_catalogue_ready',v_catalogue_ready,'catalogue_gap',greatest(v_provider_count-v_catalogue_ready,0),'change_control_ref','CF-CHG-20260904-119')) returning id into v_request;

  with scoped as (
    select distinct p.id,p.canonical_name
    from catalogue.providers p join ref.countries c on c.id=p.country_id
    where upper(c.iso_alpha2::text)=upper(p_country_code)
      and (lower(p_scope_type)='country' or (lower(p_scope_type)='state' and (p.subdivision_id=p_scope_id or exists(select 1 from catalogue.campuses ca where ca.provider_id=p.id and ca.subdivision_id=p_scope_id))) or (lower(p_scope_type)='university' and p.id=p_scope_id))
  ), ready as (
    select s.* from scoped s where
      exists(select 1 from pipeline.scholarship_acquisition_trace t where t.provider_id=s.id and t.first_party_catalogue_url is not null)
      or exists(select 1 from pipeline.sources ps where ps.provider_id=s.id and ps.status='active' and (ps.source_type ilike '%scholar%' or ps.label ilike '%scholar%'))
  ), ins as (
    insert into pipeline.jobs(job_type,domain,provider_id,status,requested_by,payload)
    select 'scholarship_scope_acquisition','scholarship',s.id,'queued',p_actor,jsonb_build_object('request_id',v_request,'country_code',upper(p_country_code),'scope_type',lower(p_scope_type),'scope_id',p_scope_id,'scope_name',v_scope_name,'provider_name',s.canonical_name,'acquisition_stage','first_party_catalogue_then_detail','publication_authorised',false,'change_control_ref','CF-CHG-20260904-119') from ready s returning 1
  ) select count(*) into v_jobs from ins;

  return jsonb_build_object('ok',true,'domain','scholarship','action','start','status',case when v_jobs>0 then 'queued' else 'no_ready_provider' end,'request_id',v_request,'country_code',upper(p_country_code),'scope_type',lower(p_scope_type),'scope_id',p_scope_id,'scope_name',v_scope_name,'scope_provider_count',v_provider_count,'jobs_queued',v_jobs,'first_party_catalogue_ready',v_catalogue_ready,'catalogue_gap',greatest(v_provider_count-v_catalogue_ready,0),'publication_changed',false,'next_step',case when v_jobs>0 then 'Qualified first-party Scholarship catalogue jobs are queued and visible in Recent Jobs.' else 'No qualified first-party Scholarship catalogue is registered in this scope; source qualification is required first.' end);
end $$;
revoke all on function public.scholarship_scope_acquisition_service(uuid,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.scholarship_scope_acquisition_service(uuid,text,text,text,uuid) to service_role;
