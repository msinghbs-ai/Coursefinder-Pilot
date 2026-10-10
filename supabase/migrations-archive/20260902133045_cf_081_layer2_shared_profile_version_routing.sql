-- CF-CHG-20260902-081: reconcile current profile versions and shared routing.
-- Applied in Pilot after the base schema migration.
begin;

create or replace function security.layer2_validate_profile_config(p_config jsonb)
returns jsonb language plpgsql stable set search_path='pg_catalog','security' as $$
declare v_errors jsonb:='[]'::jsonb;v_method text:=coalesce(p_config->>'acquisition_method','');
v_target text:=coalesce(p_config->>'target_entity_type','');v_text text:=lower(p_config::text);
begin
 if v_method not in ('website','course_catalogue','course_detail','fee_schedule','intake_calendar','english_requirements','scholarship_catalogue','document','structured_api','json_endpoint','csv_feed','xlsx_feed','sitemap','search_endpoint','other_deterministic') then v_errors:=v_errors||jsonb_build_array('unsupported acquisition_method'); end if;
 if v_target not in ('provider','course','campus','scholarship','provider_asset','provider_outcome','student_flow','course_fact','mixed') then v_errors:=v_errors||jsonb_build_array('unsupported target_entity_type'); end if;
 if coalesce(p_config->>'base_domain','')='' and coalesce(p_config->>'discovery_url','')='' then v_errors:=v_errors||jsonb_build_array('base_domain or discovery_url is required'); end if;
 if coalesce((p_config->>'timeout_seconds')::integer,30)<1 or coalesce((p_config->>'timeout_seconds')::integer,30)>120 then v_errors:=v_errors||jsonb_build_array('timeout_seconds must be between 1 and 120'); end if;
 if coalesce((p_config->>'concurrency')::integer,1)<1 or coalesce((p_config->>'concurrency')::integer,1)>20 then v_errors:=v_errors||jsonb_build_array('concurrency must be between 1 and 20'); end if;
 if coalesce((p_config->>'max_payload_mb')::integer,10)<1 or coalesce((p_config->>'max_payload_mb')::integer,10)>100 then v_errors:=v_errors||jsonb_build_array('max_payload_mb must be between 1 and 100'); end if;
 if v_text ~ '"(secret|password|token|api[_-]?key|authorization|cookie|client[_-]?secret)"[[:space:]]*:' then v_errors:=v_errors||jsonb_build_array('secret-like configuration keys are prohibited; use server-side secret references only'); end if;
 if coalesce(p_config->>'evidence_required','true')<>'true' then v_errors:=v_errors||jsonb_build_array('Layer 2 evidence_required must be true'); end if;
 return jsonb_build_object('valid',jsonb_array_length(v_errors)=0,'errors',v_errors,'validated_at',now());
exception when others then return jsonb_build_object('valid',false,'errors',jsonb_build_array('configuration type validation failed'),'validated_at',now());
end $$;

do $$
declare r record;cfg jsonb;h text;val jsonb;vid uuid;vno int;
begin
 for r in
  select p.*,s.url from pipeline.layer2_source_profiles p join pipeline.sources s on s.id=p.source_id
  where p.current_version_id is null and (p.profile_key like 'au-provider-scholarship-%' or p.profile_key like 'nz-provider-scholarship-%' or p.profile_key like 'au-provider-logo-%' or p.profile_key like 'nz-provider-logo-%')
 loop
  cfg:=jsonb_build_object('acquisition_method',r.acquisition_method,'base_domain',regexp_replace(r.url,'^(https?://[^/]+).*$','\1'),'discovery_url',r.url,'url_patterns',jsonb_build_array(r.url),
   'headers',jsonb_build_object('user_agent','CourseFinder deterministic Layer 2 acquisition'),'rate_limit_per_minute',30,'concurrency',2,'timeout_seconds',60,
   'retry',jsonb_build_object('max_attempts',2,'backoff','exponential'),'robots_policy','respect',
   'allowed_mime_types',jsonb_build_array('text/html','application/json','image/svg+xml','image/png','image/jpeg','image/webp'),'max_payload_mb',25,
   'target_entity_type',r.target_entity_type,'evidence_required',true,'freshness_sla_hours',r.freshness_sla_hours,'schedule',r.schedule_text,
   'shared_fetch_ttl_hours',24,'reuse_shared_fetch',true,'fanout_domains',jsonb_build_array('course_facts','scholarship','provider_asset'),
   'content_change_policy','reuse same-url Evidence inside TTL; hash before downstream extraction; no direct canonical mutation','change_control_ref','CF-CHG-20260902-081');
  h:=encode(extensions.digest(cfg::text,'sha256'),'hex');val:=security.layer2_validate_profile_config(cfg);
  select coalesce(max(version_no),0)+1 into vno from pipeline.layer2_source_profile_versions where profile_id=r.id;
  insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref)
  values(r.id,vno,cfg,h,case when (val->>'valid')::boolean then 'valid' else 'invalid' end,val,'CF-CHG-20260902-081')
  on conflict(profile_id,configuration_hash) do update set validation_result=excluded.validation_result returning id into vid;
  update pipeline.layer2_source_profiles set current_version_id=vid,updated_at=now() where id=r.id;
 end loop;
end $$;

do $$
declare r record;cfg jsonb;h text;val jsonb;vid uuid;vno int;
begin
 for r in
  select p.id,v.configuration from pipeline.layer2_source_profiles p join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id
  where p.domain='course_facts' and p.target_entity_type='course_fact' and p.enabled and not p.paused
   and coalesce((v.configuration->>'reuse_shared_fetch')::boolean,false)=false
   and exists(select 1 from pipeline.layer2_source_profiles s where s.source_id=p.source_id and s.domain='scholarship' and s.enabled and not s.paused)
   and exists(select 1 from pipeline.layer2_source_profiles a where a.source_id=p.source_id and a.domain='provider_asset' and a.enabled and not a.paused)
 loop
  cfg:=r.configuration||jsonb_build_object('shared_fetch_ttl_hours',24,'reuse_shared_fetch',true,'fanout_domains',jsonb_build_array('course_facts','scholarship','provider_asset'),'change_control_ref','CF-CHG-20260902-081');
  h:=encode(extensions.digest(cfg::text,'sha256'),'hex');val:=security.layer2_validate_profile_config(cfg);
  select coalesce(max(version_no),0)+1 into vno from pipeline.layer2_source_profile_versions where profile_id=r.id;
  insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref)
  values(r.id,vno,cfg,h,case when (val->>'valid')::boolean then 'valid' else 'invalid' end,val,'CF-CHG-20260902-081')
  on conflict(profile_id,configuration_hash) do update set validation_result=excluded.validation_result returning id into vid;
  update pipeline.layer2_source_profiles set current_version_id=vid,updated_at=now() where id=r.id;
 end loop;
end $$;

with ap as(select id,provider_key from pipeline.layer2_acquisition_providers where provider_key in('direct-http','parsebot','firecrawl','zenrows')),
prof as(select id from pipeline.layer2_source_profiles where profile_key like 'au-provider-scholarship-%' or profile_key like 'nz-provider-scholarship-%' or profile_key like 'au-provider-logo-%' or profile_key like 'nz-provider-logo-%')
insert into pipeline.layer2_profile_provider_routes(profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref)
select prof.id,ap.id,case ap.provider_key when 'direct-http' then 10 when 'parsebot' then 20 when 'firecrawl' then 40 else 50 end,true,'{}'::jsonb,'{}'::jsonb,
case when ap.provider_key='firecrawl' then '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":true,"capture_screenshot_on_extraction_failure":true}'::jsonb else '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":false}'::jsonb end,
'["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb,'CF-CHG-20260902-081'
from prof cross join ap
on conflict(profile_id,acquisition_provider_id) do update set priority=excluded.priority,enabled=excluded.enabled,evidence_policy=excluded.evidence_policy,fallback_on=excluded.fallback_on,change_control_ref=excluded.change_control_ref,updated_at=now();

commit;
