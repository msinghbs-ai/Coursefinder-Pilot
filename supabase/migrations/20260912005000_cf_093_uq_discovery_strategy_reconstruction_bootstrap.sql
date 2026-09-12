-- CF-CHG-20260910-093 reconstruction bootstrap.
-- Ordering is deliberate: this must replay before already-applied 20260912005948.
-- Pilot already has a qualified discovery_strategy through later applied runtime state,
-- so the governed remote-history action for this retroactive migration is to mark it
-- applied with the official Supabase migration-repair command, not to rewrite 005948.
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
  select p.id,p.current_version_id,v.configuration
    into v_profile_id,v_old_version_id,v_cfg
  from pipeline.layer2_source_profiles p
  join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id
  where p.profile_key='au-uq-course-catalogue'
    and p.domain='course_facts'
  for update of p;

  if v_profile_id is null then
    raise exception 'UQ Course Facts profile not found for reconstruction bootstrap' using errcode='22023';
  end if;

  if v_cfg ? 'discovery_strategy' then
    return;
  end if;

  v_cfg:=jsonb_set(
    v_cfg,
    '{discovery_strategy}',
    jsonb_build_object('type','first_party_search'),
    true
  );

  v_validation:=security.layer2_validate_profile_config(v_cfg);
  if not coalesce((v_validation->>'valid')::boolean,false) then
    raise exception 'UQ reconstruction bootstrap validation failed: %',coalesce(v_validation->'errors','[]'::jsonb)::text using errcode='22023';
  end if;

  v_hash:=encode(extensions.digest(v_cfg::text,'sha256'),'hex');

  select id into v_new_version_id
  from pipeline.layer2_source_profile_versions
  where profile_id=v_profile_id and configuration_hash=v_hash
  order by version_no desc
  limit 1;

  if v_new_version_id is null then
    select coalesce(max(version_no),0)+1 into v_next
    from pipeline.layer2_source_profile_versions
    where profile_id=v_profile_id;

    insert into pipeline.layer2_source_profile_versions(
      profile_id,version_no,configuration,configuration_hash,
      validation_status,validation_result,change_control_ref,uat_ref
    ) values (
      v_profile_id,v_next,v_cfg,v_hash,
      'valid',v_validation,'CF-CHG-20260910-093','CF-093-reconstruction-bootstrap-before-005948'
    ) returning id into v_new_version_id;
  end if;

  update pipeline.layer2_source_profile_versions
  set validation_status='superseded'
  where id=v_old_version_id and id<>v_new_version_id and validation_status='valid';

  update pipeline.layer2_source_profiles
  set current_version_id=v_new_version_id,updated_at=now()
  where id=v_profile_id and current_version_id is distinct from v_new_version_id;
end
$$;
