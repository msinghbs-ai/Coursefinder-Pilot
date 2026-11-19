create or replace function security.layer2_sanitise_config(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path='pg_catalog','security'
as $$
declare
  v_type text;
  v_result jsonb;
  v_key text;
  v_item jsonb;
begin
  if p_value is null then return null; end if;
  v_type:=jsonb_typeof(p_value);
  if v_type='object' then
    v_result:='{}'::jsonb;
    for v_key,v_item in select key,value from jsonb_each(p_value) loop
      if lower(v_key) ~ '^(secret|password|token|api[_-]?key|authorization|cookie|client[_-]?secret)$' then
        continue;
      end if;
      v_result:=v_result||jsonb_build_object(v_key,security.layer2_sanitise_config(v_item));
    end loop;
    return v_result;
  elsif v_type='array' then
    select coalesce(jsonb_agg(security.layer2_sanitise_config(value)),'[]'::jsonb) into v_result from jsonb_array_elements(p_value);
    return v_result;
  end if;
  return p_value;
end
$$;

create or replace function public.layer2_create_profile_version(
  p_actor uuid,
  p_profile_id uuid,
  p_configuration jsonb,
  p_change_control_ref text,
  p_uat_ref text default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','security','pipeline','extensions'
as $$
declare
  v_rank integer:=0;
  v_profile pipeline.layer2_source_profiles%rowtype;
  v_validation jsonb;
  v_hash text;
  v_next integer;
  v_id uuid;
  v_old uuid;
begin
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
  select coalesce(max(r.rank),0) into v_rank
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank < 5 then raise exception 'pim_admin role required' using errcode='42501'; end if;
  if p_configuration is null or jsonb_typeof(p_configuration)<>'object' then raise exception 'configuration object required' using errcode='22023'; end if;
  if coalesce(nullif(trim(p_change_control_ref),''),'')='' then raise exception 'change_control_ref required' using errcode='22023'; end if;

  select * into v_profile from pipeline.layer2_source_profiles where id=p_profile_id for update;
  if not found then raise exception 'profile not found' using errcode='22023'; end if;
  if coalesce(p_configuration->>'acquisition_method','')<>v_profile.acquisition_method then raise exception 'acquisition_method must match stable profile; create a new profile for method changes' using errcode='22023'; end if;
  if coalesce(p_configuration->>'target_entity_type','')<>v_profile.target_entity_type then raise exception 'target_entity_type must match stable profile; create a new profile for target changes' using errcode='22023'; end if;

  v_validation:=security.layer2_validate_profile_config(p_configuration);
  if not coalesce((v_validation->>'valid')::boolean,false) then
    raise exception 'configuration validation failed: %',coalesce(v_validation->'errors','[]'::jsonb)::text using errcode='22023';
  end if;

  v_hash:=encode(extensions.digest(p_configuration::text,'sha256'),'hex');
  select coalesce(max(version_no),0)+1 into v_next from pipeline.layer2_source_profile_versions where profile_id=p_profile_id;
  v_old:=v_profile.current_version_id;

  insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref,uat_ref,created_by)
  values(p_profile_id,v_next,p_configuration,v_hash,'valid',v_validation,trim(p_change_control_ref),nullif(trim(coalesce(p_uat_ref,'')),''),p_actor)
  returning id into v_id;

  if v_old is not null then
    update pipeline.layer2_source_profile_versions set validation_status='superseded' where id=v_old and validation_status='valid';
  end if;

  update pipeline.layer2_source_profiles
  set current_version_id=v_id,
      freshness_sla_hours=case when p_configuration ? 'freshness_sla_hours' then nullif(p_configuration->>'freshness_sla_hours','')::integer else freshness_sla_hours end,
      schedule_text=coalesce(nullif(p_configuration->>'schedule',''),schedule_text),
      updated_at=now()
  where id=p_profile_id;

  return jsonb_build_object('ok',true,'profile_id',p_profile_id,'version_id',v_id,'version_no',v_next,'configuration_hash',v_hash,'validation',v_validation);
exception when unique_violation then
  raise exception 'configuration already exists for this profile' using errcode='23505';
end
$$;
revoke all on function public.layer2_create_profile_version(uuid,uuid,jsonb,text,text) from public,anon,authenticated;
grant execute on function public.layer2_create_profile_version(uuid,uuid,jsonb,text,text) to service_role;

create or replace function security.admin_layer2_config_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path='pg_catalog','security','pipeline','ref','catalogue','public'
as $$
declare
  v_rank integer:=0;
  v_id uuid;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  if p_operation='layer2_profiles' then
    select coalesce(jsonb_agg(row_json order by lower(row_json->>'source_label')),'[]'::jsonb) into v_result
    from (
      select jsonb_build_object(
        'profile_id',p.id,'profile_key',p.profile_key,'source_id',p.source_id,'source_label',s.label,'country_code',c.iso_alpha2,
        'source_type',s.source_type,'source_url',s.url,'trust_rank',s.trust_rank,'domain',p.domain,'acquisition_method',p.acquisition_method,
        'target_entity_type',p.target_entity_type,'authority_class',p.authority_class,'enabled',p.enabled,'paused',p.paused,
        'operational_owner',p.operational_owner,'freshness_sla_hours',p.freshness_sla_hours,'schedule_text',p.schedule_text,
        'current_version_id',p.current_version_id,'current_version',v.version_no,'validation_status',v.validation_status,
        'validation_result',v.validation_result,'change_control_ref',v.change_control_ref,'uat_ref',v.uat_ref,
        'last_success_at',s.last_success_at,'last_failure_at',s.last_failure_at,'last_error',s.last_error,
        'last_inventory_at',p.last_inventory_at,'last_inventory_count',p.last_inventory_count,'last_inventory_hash',p.last_inventory_hash,
        'job_count',(select count(*) from pipeline.jobs j where j.source_id=p.source_id),
        'evidence_count',(select count(*) from pipeline.evidence_artifacts e where e.source_id=p.source_id),
        'version_count',(select count(*) from pipeline.layer2_source_profile_versions vv where vv.profile_id=p.id),
        'affected_provider_id',s.provider_id,'affected_provider_name',cp.canonical_name,
        'health',case when not p.enabled then 'disabled' when p.paused then 'paused' when v.validation_status<>'valid' then 'blocked' when s.last_failure_at is not null and (s.last_success_at is null or s.last_failure_at>s.last_success_at) then 'degraded' when p.freshness_sla_hours is not null and s.last_success_at is not null and s.last_success_at < now()-(p.freshness_sla_hours||' hours')::interval then 'stale' else 'healthy' end
      ) row_json
      from pipeline.layer2_source_profiles p
      join pipeline.sources s on s.id=p.source_id
      left join ref.countries c on c.id=s.country_id
      left join catalogue.providers cp on cp.id=s.provider_id
      left join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id
    ) q;
    return v_result;
  end if;

  if p_operation='layer2_profile_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    select jsonb_build_object(
      'profile',jsonb_build_object('id',p.id,'profile_key',p.profile_key,'source_id',p.source_id,'source_label',s.label,'country_code',c.iso_alpha2,'source_url',s.url,'trust_rank',s.trust_rank,'domain',p.domain,'acquisition_method',p.acquisition_method,'target_entity_type',p.target_entity_type,'authority_class',p.authority_class,'enabled',p.enabled,'paused',p.paused,'operational_owner',p.operational_owner,'freshness_sla_hours',p.freshness_sla_hours,'schedule_text',p.schedule_text,'last_inventory_at',p.last_inventory_at,'last_inventory_count',p.last_inventory_count,'last_inventory_hash',p.last_inventory_hash,'last_success_at',s.last_success_at,'last_failure_at',s.last_failure_at,'last_error',s.last_error,'affected_provider_id',s.provider_id,'affected_provider_name',cp.canonical_name),
      'current_version',case when v.id is null then null else jsonb_build_object('id',v.id,'version_no',v.version_no,'configuration',security.layer2_sanitise_config(v.configuration),'configuration_hash',v.configuration_hash,'validation_status',v.validation_status,'validation_result',v.validation_result,'change_control_ref',v.change_control_ref,'uat_ref',v.uat_ref,'created_at',v.created_at) end,
      'history',(select coalesce(jsonb_agg(jsonb_build_object('id',h.id,'version_no',h.version_no,'configuration_hash',h.configuration_hash,'validation_status',h.validation_status,'validation_result',h.validation_result,'change_control_ref',h.change_control_ref,'uat_ref',h.uat_ref,'created_at',h.created_at,'configuration',security.layer2_sanitise_config(h.configuration)) order by h.version_no desc),'[]'::jsonb) from pipeline.layer2_source_profile_versions h where h.profile_id=p.id),
      'recent_jobs',(select coalesce(jsonb_agg(jsonb_build_object('id',j.id,'status',j.status,'job_type',j.job_type,'created_at',j.created_at,'completed_at',j.completed_at,'source_profile_version_id',j.source_profile_version_id) order by j.created_at desc),'[]'::jsonb) from (select * from pipeline.jobs jj where jj.source_id=p.source_id order by jj.created_at desc limit 20) j),
      'recent_evidence',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'evidence_type',e.evidence_type,'mime_type',e.mime_type,'captured_at',e.captured_at,'content_hash',e.content_hash,'source_profile_version_id',e.source_profile_version_id) order by e.captured_at desc),'[]'::jsonb) from (select * from pipeline.evidence_artifacts ee where ee.source_id=p.source_id order by ee.captured_at desc limit 20) e)
    ) into v_result
    from pipeline.layer2_source_profiles p
    join pipeline.sources s on s.id=p.source_id
    left join ref.countries c on c.id=s.country_id
    left join catalogue.providers cp on cp.id=s.provider_id
    left join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id
    where p.id=v_id;
    return coalesce(v_result,'{}'::jsonb);
  end if;
  raise exception 'unsupported layer2 read operation: %',p_operation using errcode='22023';
end
$$;
