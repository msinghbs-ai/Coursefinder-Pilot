-- Mirrors deployed 20260823103650 · CF-CHG-20260823-029
create or replace function security.layer2_sanitise_config(p_value jsonb)
returns jsonb language plpgsql immutable set search_path='pg_catalog','security' as $$
declare v_type text;v_result jsonb;v_key text;v_item jsonb;begin
 if p_value is null then return null;end if;v_type:=jsonb_typeof(p_value);
 if v_type='object' then v_result:='{}'::jsonb;for v_key,v_item in select key,value from jsonb_each(p_value) loop if lower(v_key)~'^(secret|password|token|api[_-]?key|authorization|cookie|client[_-]?secret)$' then continue;end if;v_result:=v_result||jsonb_build_object(v_key,security.layer2_sanitise_config(v_item));end loop;return v_result;
 elsif v_type='array' then select coalesce(jsonb_agg(security.layer2_sanitise_config(value)),'[]'::jsonb) into v_result from jsonb_array_elements(p_value);return v_result;end if;return p_value;end $$;

create or replace function public.layer2_create_profile_version(p_actor uuid,p_profile_id uuid,p_configuration jsonb,p_change_control_ref text,p_uat_ref text default null)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','security','pipeline','extensions' as $$
declare v_rank integer:=0;v_profile pipeline.layer2_source_profiles%rowtype;v_validation jsonb;v_hash text;v_next integer;v_id uuid;v_old uuid;begin
 if p_actor is null then raise exception 'actor required' using errcode='42501';end if;
 select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
 if v_rank<5 then raise exception 'pim_admin role required' using errcode='42501';end if;
 if p_configuration is null or jsonb_typeof(p_configuration)<>'object' then raise exception 'configuration object required' using errcode='22023';end if;
 if coalesce(nullif(trim(p_change_control_ref),''),'')='' then raise exception 'change_control_ref required' using errcode='22023';end if;
 select * into v_profile from pipeline.layer2_source_profiles where id=p_profile_id for update;if not found then raise exception 'profile not found' using errcode='22023';end if;
 if coalesce(p_configuration->>'acquisition_method','')<>v_profile.acquisition_method then raise exception 'acquisition_method must match stable profile; create a new profile for method changes' using errcode='22023';end if;
 if coalesce(p_configuration->>'target_entity_type','')<>v_profile.target_entity_type then raise exception 'target_entity_type must match stable profile; create a new profile for target changes' using errcode='22023';end if;
 v_validation:=security.layer2_validate_profile_config(p_configuration);if not coalesce((v_validation->>'valid')::boolean,false) then raise exception 'configuration validation failed: %',coalesce(v_validation->'errors','[]'::jsonb)::text using errcode='22023';end if;
 v_hash:=encode(extensions.digest(p_configuration::text,'sha256'),'hex');select coalesce(max(version_no),0)+1 into v_next from pipeline.layer2_source_profile_versions where profile_id=p_profile_id;v_old:=v_profile.current_version_id;
 insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref,uat_ref,created_by) values(p_profile_id,v_next,p_configuration,v_hash,'valid',v_validation,trim(p_change_control_ref),nullif(trim(coalesce(p_uat_ref,'')),''),p_actor) returning id into v_id;
 if v_old is not null then update pipeline.layer2_source_profile_versions set validation_status='superseded' where id=v_old and validation_status='valid';end if;
 update pipeline.layer2_source_profiles set current_version_id=v_id,freshness_sla_hours=case when p_configuration?'freshness_sla_hours' then nullif(p_configuration->>'freshness_sla_hours','')::integer else freshness_sla_hours end,schedule_text=coalesce(nullif(p_configuration->>'schedule',''),schedule_text),updated_at=now() where id=p_profile_id;
 return jsonb_build_object('ok',true,'profile_id',p_profile_id,'version_id',v_id,'version_no',v_next,'configuration_hash',v_hash,'validation',v_validation);
exception when unique_violation then raise exception 'configuration already exists for this profile' using errcode='23505';end $$;
revoke all on function public.layer2_create_profile_version(uuid,uuid,jsonb,text,text) from public,anon,authenticated;grant execute on function public.layer2_create_profile_version(uuid,uuid,jsonb,text,text) to service_role;

-- Browser read projection is reconciled to the deployed sanitised/set-based definition in 20260823104311.