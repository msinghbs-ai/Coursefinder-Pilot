do $$
declare
  v_profile_id uuid;
  v_old_version_id uuid;
  v_cfg jsonb;
  v_validation jsonb;
  v_hash text;
  v_next integer;
  v_new_version_id uuid;
begin
  select lp.id, lp.current_version_id, pv.configuration
    into v_profile_id, v_old_version_id, v_cfg
  from pipeline.layer2_source_profiles lp
  join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
  where lp.profile_key='au-uq-course-catalogue'
    and lp.domain='course_facts'
  for update of lp;

  if v_profile_id is null then
    raise exception 'UQ Course Facts profile not found' using errcode='22023';
  end if;

  v_cfg:=jsonb_set(
    jsonb_set(
      jsonb_set(v_cfg,'{discovery_strategy,search_url_template}',to_jsonb('https://study.uq.edu.au/study-options/programs?search={query}&type=program&studentType=international'::text),true),
      '{discovery_strategy,query_field}',to_jsonb('canonical_title_normalized'::text),true
    ),
    '{discovery_strategy,require_url_prefix}',to_jsonb('/study-options/programs/'::text),true
  );

  v_validation:=security.layer2_validate_profile_config(v_cfg);
  if not coalesce((v_validation->>'valid')::boolean,false) then
    raise exception 'UQ discovery profile validation failed: %',coalesce(v_validation->'errors','[]'::jsonb)::text using errcode='22023';
  end if;

  v_hash:=encode(extensions.digest(v_cfg::text,'sha256'),'hex');
  select coalesce(max(version_no),0)+1 into v_next
  from pipeline.layer2_source_profile_versions
  where profile_id=v_profile_id;

  insert into pipeline.layer2_source_profile_versions(
    profile_id,version_no,configuration,configuration_hash,
    validation_status,validation_result,change_control_ref,uat_ref
  ) values (
    v_profile_id,v_next,v_cfg,v_hash,
    'valid',v_validation,'CF-CHG-20260910-093','CF-093-UQ-native-program-discovery'
  ) returning id into v_new_version_id;

  update pipeline.layer2_source_profile_versions
  set validation_status='superseded'
  where id=v_old_version_id and validation_status='valid';

  update pipeline.layer2_source_profiles
  set current_version_id=v_new_version_id,
      freshness_sla_hours=case when v_cfg?'freshness_sla_hours' then nullif(v_cfg->>'freshness_sla_hours','')::integer else freshness_sla_hours end,
      schedule_text=coalesce(nullif(v_cfg->>'schedule',''),schedule_text),
      updated_at=now()
  where id=v_profile_id;
end
$$;
