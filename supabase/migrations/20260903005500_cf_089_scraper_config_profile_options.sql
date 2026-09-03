-- CF-089: bounded Layer 2 profile options for Scraper Config routing.
create or replace function public.layer2_provider_profile_options_service(
  p_actor uuid,
  p_query text default null,
  p_limit integer default 10,
  p_offset integer default 0
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','security','pipeline','catalogue','ref'
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(p_limit,10),1),10);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_query text:=nullif(trim(coalesce(p_query,'')),'');
  v_total bigint:=0;
  v_items jsonb:='[]'::jsonb;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  select coalesce(max(r.rank),0) into v_rank
  from security.user_roles ur
  join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor
    and (ur.expires_at is null or ur.expires_at>now())
    and r.status='active';
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  with base as (
    select p.id profile_id,p.profile_key,p.domain,p.target_entity_type,p.enabled,p.paused,
           s.label source_label,c.iso_alpha2 country_code,cp.canonical_name affected_provider_name,
           v.validation_status
    from pipeline.layer2_source_profiles p
    join pipeline.sources s on s.id=p.source_id
    left join ref.countries c on c.id=s.country_id
    left join catalogue.providers cp on cp.id=s.provider_id
    left join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id
    where p.domain in ('course_facts','scholarship')
      and p.target_entity_type in ('course_fact','scholarship')
      and (
        v_query is null or
        p.profile_key ilike '%'||v_query||'%' or
        s.label ilike '%'||v_query||'%' or
        coalesce(cp.canonical_name,'') ilike '%'||v_query||'%' or
        coalesce(c.iso_alpha2,'') ilike '%'||v_query||'%'
      )
  )
  select count(*) into v_total from base;

  with base as (
    select p.id profile_id,p.profile_key,p.domain,p.target_entity_type,p.enabled,p.paused,
           s.label source_label,c.iso_alpha2 country_code,cp.canonical_name affected_provider_name,
           v.validation_status
    from pipeline.layer2_source_profiles p
    join pipeline.sources s on s.id=p.source_id
    left join ref.countries c on c.id=s.country_id
    left join catalogue.providers cp on cp.id=s.provider_id
    left join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id
    where p.domain in ('course_facts','scholarship')
      and p.target_entity_type in ('course_fact','scholarship')
      and (
        v_query is null or
        p.profile_key ilike '%'||v_query||'%' or
        s.label ilike '%'||v_query||'%' or
        coalesce(cp.canonical_name,'') ilike '%'||v_query||'%' or
        coalesce(c.iso_alpha2,'') ilike '%'||v_query||'%'
      )
    order by lower(s.label),p.profile_key
    limit v_limit offset v_offset
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'profile_id',profile_id,'profile_key',profile_key,'source_label',source_label,
    'country_code',country_code,'domain',domain,'target_entity_type',target_entity_type,
    'affected_provider_name',affected_provider_name,'enabled',enabled,'paused',paused,
    'validation_status',validation_status
  )),'[]'::jsonb) into v_items from base;

  return jsonb_build_object(
    'items',v_items,'total',v_total,'limit',v_limit,'offset',v_offset,
    'has_more',v_offset+v_limit<v_total
  );
end
$$;
revoke all on function public.layer2_provider_profile_options_service(uuid,text,integer,integer) from public, anon, authenticated;
grant execute on function public.layer2_provider_profile_options_service(uuid,text,integer,integer) to service_role;
