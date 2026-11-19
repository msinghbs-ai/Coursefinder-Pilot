-- M2.3 operational read/write contracts
-- Change Control: CF-CHG-20260825-038

create or replace function public.layer3_recent_interpretations(p_limit integer default 100)
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,security,pipeline,auth as $$
begin
 if auth.uid() is null or security.current_role_rank()<3 then raise exception 'curator role required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
   select i.id,i.evidence_id,i.entity_type,i.entity_id,i.task_class,i.eligibility_reason,i.status,i.candidate_value,i.confidence,i.rationale,
          i.aggregator_response_model,i.input_tokens,i.output_tokens,i.estimated_cost_usd,i.interpretation_expires_at,i.change_control_ref,i.uat_ref,i.created_at,
          p.code as profile_code,p.aggregator_provider,p.model_identifier,p.prompt_profile_version
   from pipeline.layer3_interpretations i join pipeline.layer3_model_profiles p on p.id=i.profile_id
   order by i.created_at desc limit least(greatest(p_limit,1),250)
 ) x),'[]'::jsonb);
end $$;

create or replace function public.layer3_model_profile_upsert(
 p_id uuid,p_code text,p_aggregator_provider text,p_base_url text,p_model_identifier text,p_secret_env_key text,p_allowed_task_classes text[],
 p_prompt_profile_version text,p_prompt_system text,p_structured_output_schema jsonb,p_deterministic_validators jsonb,p_max_input_tokens integer,p_max_output_tokens integer,
 p_requests_per_minute integer,p_requests_per_day integer,p_retry_ceiling integer,p_timeout_ms integer,p_fallback_profile_id uuid,p_cost_ceiling_usd numeric,p_enabled boolean,p_paused boolean,p_reason text
) returns uuid language plpgsql security definer set search_path=pg_catalog,security,pipeline,auth as $$
declare v_id uuid:=coalesce(p_id,gen_random_uuid());
begin
 if auth.uid() is null or security.current_role_rank()<5 then raise exception 'PIM administrator role required' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<5 then raise exception 'governance reason required'; end if;
 if p_base_url !~* '^https://' then raise exception 'HTTPS base URL required'; end if;
 if p_secret_env_key !~ '^[A-Z][A-Z0-9_]{2,127}$' then raise exception 'secret environment key name is invalid'; end if;
 if coalesce(array_length(p_allowed_task_classes,1),0)<1 then raise exception 'at least one allowed task class required'; end if;
 insert into pipeline.layer3_model_profiles(id,code,aggregator_provider,base_url,model_identifier,secret_env_key,allowed_task_classes,prompt_profile_version,prompt_system,structured_output_schema,deterministic_validators,max_input_tokens,max_output_tokens,requests_per_minute,requests_per_day,retry_ceiling,timeout_ms,fallback_profile_id,cost_ceiling_usd,enabled,paused,last_validation_result,change_control_ref)
 values(v_id,trim(p_code),trim(p_aggregator_provider),trim(p_base_url),trim(p_model_identifier),trim(p_secret_env_key),p_allowed_task_classes,trim(p_prompt_profile_version),p_prompt_system,coalesce(p_structured_output_schema,'{}'::jsonb),coalesce(p_deterministic_validators,'{}'::jsonb),p_max_input_tokens,p_max_output_tokens,p_requests_per_minute,p_requests_per_day,p_retry_ceiling,p_timeout_ms,p_fallback_profile_id,p_cost_ceiling_usd,p_enabled,p_paused,jsonb_build_object('validated',false,'state','configuration_changed_requires_validation','reason',trim(p_reason),'changed_at',now(),'changed_by',auth.uid()),'CF-CHG-20260825-038')
 on conflict(id) do update set code=excluded.code,aggregator_provider=excluded.aggregator_provider,base_url=excluded.base_url,model_identifier=excluded.model_identifier,secret_env_key=excluded.secret_env_key,allowed_task_classes=excluded.allowed_task_classes,prompt_profile_version=excluded.prompt_profile_version,prompt_system=excluded.prompt_system,structured_output_schema=excluded.structured_output_schema,deterministic_validators=excluded.deterministic_validators,max_input_tokens=excluded.max_input_tokens,max_output_tokens=excluded.max_output_tokens,requests_per_minute=excluded.requests_per_minute,requests_per_day=excluded.requests_per_day,retry_ceiling=excluded.retry_ceiling,timeout_ms=excluded.timeout_ms,fallback_profile_id=excluded.fallback_profile_id,cost_ceiling_usd=excluded.cost_ceiling_usd,enabled=excluded.enabled,paused=excluded.paused,last_validation_result=excluded.last_validation_result,updated_at=now();
 return v_id;
end $$;

create or replace function public.refresh_intelligence_overview(p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,security,pipeline,auth as $$
begin
 if auth.uid() is null or security.current_role_rank()<3 then raise exception 'curator role required' using errcode='42501'; end if;
 return jsonb_build_object(
  'policies',coalesce((select jsonb_agg(to_jsonb(x) order by x.next_due_at nulls last) from (select id,country_code,layer,source_profile_id,entity_type,entity_id,freshness_class,cadence_interval,next_due_at,hash_sensitive,important_date_sensitive,enabled,change_control_ref,updated_at from pipeline.refresh_policies order by next_due_at nulls last limit least(greatest(p_limit,1),250)) x),'[]'::jsonb),
  'requests',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,requested_layer,country_code,source_profile_id,entity_type,entity_id,reason,trigger_type,important_date_id,status,requested_by,change_control_ref,created_at,completed_at from pipeline.refresh_requests order by created_at desc limit least(greatest(p_limit,1),250)) x),'[]'::jsonb)
 );
end $$;

create or replace function public.refresh_policy_upsert(p_id uuid,p_country_code text,p_layer smallint,p_source_profile_id uuid,p_entity_type text,p_entity_id uuid,p_freshness_class text,p_cadence_days integer,p_next_due_at timestamptz,p_hash_sensitive boolean,p_important_date_sensitive boolean,p_enabled boolean,p_reason text)
returns uuid language plpgsql security definer set search_path=pg_catalog,security,pipeline,auth as $$ declare v_id uuid:=coalesce(p_id,gen_random_uuid()); begin
 if auth.uid() is null or security.current_role_rank()<4 then raise exception 'pipeline operator role required' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<5 then raise exception 'governance reason required'; end if;
 if p_layer=4 and p_freshness_class<>'event-driven' then raise exception 'Layer 4 refresh policy must be event-driven'; end if;
 if p_layer in (1,2,3) and p_source_profile_id is null and p_entity_id is null then raise exception 'bounded source or entity target required'; end if;
 insert into pipeline.refresh_policies(id,country_code,layer,source_profile_id,entity_type,entity_id,freshness_class,cadence_interval,next_due_at,hash_sensitive,important_date_sensitive,enabled,change_control_ref)
 values(v_id,upper(nullif(p_country_code,'')),p_layer,p_source_profile_id,p_entity_type,p_entity_id,p_freshness_class,case when p_cadence_days is null then null else make_interval(days=>p_cadence_days) end,p_next_due_at,p_hash_sensitive,p_important_date_sensitive,p_enabled,'CF-CHG-20260825-038')
 on conflict(id) do update set country_code=excluded.country_code,layer=excluded.layer,source_profile_id=excluded.source_profile_id,entity_type=excluded.entity_type,entity_id=excluded.entity_id,freshness_class=excluded.freshness_class,cadence_interval=excluded.cadence_interval,next_due_at=excluded.next_due_at,hash_sensitive=excluded.hash_sensitive,important_date_sensitive=excluded.important_date_sensitive,enabled=excluded.enabled,change_control_ref=excluded.change_control_ref,updated_at=now(); return v_id; end $$;

create or replace function public.important_link_verify(p_id uuid,p_health_status text,p_note text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,security,pipeline,auth as $$ declare v pipeline.important_links%rowtype; begin
 if auth.uid() is null or security.current_role_rank()<3 then raise exception 'curator role required' using errcode='42501'; end if;
 if length(trim(coalesce(p_note,'')))<3 then raise exception 'verification note required'; end if;
 update pipeline.important_links set health_status=p_health_status,last_verified_at=now(),next_verification_at=now()+verification_cadence,updated_by=auth.uid(),updated_at=now(),purpose=purpose||case when position('[verification:' in purpose)>0 then '' else '' end where id=p_id returning * into v;
 if not found then raise exception 'important link not found'; end if;
 return jsonb_build_object('ok',true,'id',v.id,'health_status',v.health_status,'last_verified_at',v.last_verified_at,'next_verification_at',v.next_verification_at,'verification_note',trim(p_note)); end $$;

-- Repair cadence recalculation on directory update.
create or replace function public.important_link_upsert(p_id uuid,p_country_code text,p_authority_category text,p_authority_name text,p_owner_label text,p_url text,p_purpose text,p_related_layer smallint,p_related_source_profile_id uuid,p_verification_days integer,p_health_status text)
returns uuid language plpgsql security definer set search_path=pg_catalog,security,pipeline,auth as $$ declare v_id uuid:=coalesce(p_id,gen_random_uuid()); begin
 if auth.uid() is null or security.current_role_rank()<3 then raise exception 'curator role required' using errcode='42501'; end if;
 if p_verification_days not between 1 and 730 then raise exception 'verification cadence days must be 1..730'; end if;
 insert into pipeline.important_links(id,country_code,authority_category,authority_name,owner_label,url,purpose,related_layer,related_source_profile_id,verification_cadence,next_verification_at,health_status,change_control_ref,created_by,updated_by)
 values(v_id,upper(p_country_code),p_authority_category,trim(p_authority_name),trim(p_owner_label),trim(p_url),trim(p_purpose),p_related_layer,p_related_source_profile_id,make_interval(days=>p_verification_days),now()+make_interval(days=>p_verification_days),p_health_status,'CF-CHG-20260825-038',auth.uid(),auth.uid())
 on conflict(id) do update set country_code=excluded.country_code,authority_category=excluded.authority_category,authority_name=excluded.authority_name,owner_label=excluded.owner_label,url=excluded.url,purpose=excluded.purpose,related_layer=excluded.related_layer,related_source_profile_id=excluded.related_source_profile_id,verification_cadence=excluded.verification_cadence,next_verification_at=coalesce(pipeline.important_links.last_verified_at,now())+excluded.verification_cadence,health_status=excluded.health_status,updated_by=auth.uid(),updated_at=now(); return v_id; end $$;

revoke all on function public.layer3_recent_interpretations(integer) from public,anon,authenticated;
revoke all on function public.layer3_model_profile_upsert(uuid,text,text,text,text,text,text[],text,text,jsonb,jsonb,integer,integer,integer,integer,integer,integer,uuid,numeric,boolean,boolean,text) from public,anon,authenticated;
revoke all on function public.refresh_intelligence_overview(integer) from public,anon,authenticated;
revoke all on function public.refresh_policy_upsert(uuid,text,smallint,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text) from public,anon,authenticated;
revoke all on function public.important_link_verify(uuid,text,text) from public,anon,authenticated;
grant execute on function public.layer3_recent_interpretations(integer) to authenticated;
grant execute on function public.layer3_model_profile_upsert(uuid,text,text,text,text,text,text[],text,text,jsonb,jsonb,integer,integer,integer,integer,integer,integer,uuid,numeric,boolean,boolean,text) to authenticated;
grant execute on function public.refresh_intelligence_overview(integer) to authenticated;
grant execute on function public.refresh_policy_upsert(uuid,text,smallint,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text) to authenticated;
grant execute on function public.important_link_verify(uuid,text,text) to authenticated;
