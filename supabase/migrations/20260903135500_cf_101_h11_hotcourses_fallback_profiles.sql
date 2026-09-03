begin;

-- CF-CHG-20260903-101 — bounded Hotcourses fallback acquisition profiles for unresolved AU/NZ university logos.

with hc as (
 select s.id source_id,s.provider_id,c.iso_alpha2,s.url
 from pipeline.sources s
 join catalogue.providers p on p.id=s.provider_id
 join ref.countries c on c.id=p.country_id
 where s.source_type='third_party_directory'
   and s.metadata->>'directory'='hotcourses_abroad'
   and coalesce((s.metadata->>'operator_fallback_reuse_approved')::boolean,false)=true
)
insert into pipeline.layer2_source_profiles(
 source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,
 enabled,paused,operational_owner,freshness_sla_hours,schedule_text
)
select source_id,lower(iso_alpha2)||'-hotcourses-logo-'||provider_id::text,
       'provider_asset','website','provider_asset','third_party_discovery',
       true,false,'PIM/Data Operations',2160,'manual fallback only; first-party preferred'
from hc
on conflict(profile_key) do update set
 source_id=excluded.source_id,enabled=true,paused=false,updated_at=now();

do $$
declare r record;cfg jsonb;h text;val jsonb;vid uuid;vno int;
begin
 for r in
   select p.*,s.url
   from pipeline.layer2_source_profiles p
   join pipeline.sources s on s.id=p.source_id
   where p.profile_key like '%-hotcourses-logo-%'
 loop
   cfg:=jsonb_build_object(
     'acquisition_method','website',
     'base_domain','https://www.hotcoursesabroad.com',
     'discovery_url',r.url,
     'url_patterns',jsonb_build_array(r.url),
     'headers',jsonb_build_object('user_agent','CourseFinder Provider Asset Reconciliation/1.0'),
     'rate_limit_per_minute',10,
     'concurrency',1,
     'timeout_seconds',90,
     'retry',jsonb_build_object('max_attempts',1,'backoff','fixed'),
     'robots_policy','respect',
     'allowed_mime_types',jsonb_build_array('text/html','application/json'),
     'max_payload_mb',25,
     'target_entity_type','provider_asset',
     'evidence_required',true,
     'freshness_sla_hours',2160,
     'schedule','manual fallback only',
     'shared_fetch_ttl_hours',24,
     'reuse_shared_fetch',true,
     'fanout_domains',jsonb_build_array('provider_asset'),
     'content_change_policy','Hotcourses-hosted university-logo fallback; retain aggregator provenance and canonical Provider identity',
     'change_control_ref','CF-CHG-20260903-101'
   );
   h:=encode(extensions.digest(cfg::text,'sha256'),'hex');
   val:=security.layer2_validate_profile_config(cfg);
   select coalesce(max(version_no),0)+1 into vno
   from pipeline.layer2_source_profile_versions where profile_id=r.id;
   insert into pipeline.layer2_source_profile_versions(
     profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref
   ) values(
     r.id,vno,cfg,h,case when (val->>'valid')::boolean then 'valid' else 'invalid' end,val,'CF-CHG-20260903-101'
   )
   on conflict(profile_id,configuration_hash) do update set validation_result=excluded.validation_result
   returning id into vid;
   update pipeline.layer2_source_profiles set current_version_id=vid,updated_at=now() where id=r.id;
 end loop;
end $$;

with ap as (
 select id,provider_key from pipeline.layer2_acquisition_providers
 where provider_key in('direct-http','firecrawl') and enabled
), prof as (
 select id from pipeline.layer2_source_profiles where profile_key like '%-hotcourses-logo-%'
)
insert into pipeline.layer2_profile_provider_routes(
 profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,
 evidence_policy,fallback_on,change_control_ref
)
select prof.id,ap.id,
       case ap.provider_key when 'direct-http' then 10 else 40 end,
       true,'{}'::jsonb,'{}'::jsonb,
       case when ap.provider_key='firecrawl'
         then '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":true}'::jsonb
         else '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":false}'::jsonb
       end,
       '["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb,
       'CF-CHG-20260903-101'
from prof cross join ap
on conflict(profile_id,acquisition_provider_id) do update set
 priority=excluded.priority,enabled=true,evidence_policy=excluded.evidence_policy,
 fallback_on=excluded.fallback_on,change_control_ref=excluded.change_control_ref,updated_at=now();

commit;
