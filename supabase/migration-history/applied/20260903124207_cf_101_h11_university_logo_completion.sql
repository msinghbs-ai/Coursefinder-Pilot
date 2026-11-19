begin;

-- CF-CHG-20260903-101 — H11 AU/NZ University Logo Completion.
-- The H11 university denominator is the accepted AU/NZ ranked-Provider cohort.
-- First-party source anchors are repaired/created only for the seven cohort gaps.

update catalogue.providers set website='https://adelaideuni.edu.au',updated_at=now()
where id='de2201a1-69ee-40ff-b6aa-0e54e535e6c0' and website is null;
update catalogue.providers set website='https://www.auckland.ac.nz',updated_at=now()
where id='e096aba7-e1eb-4903-9a63-2bfb71e9a8b8' and website like 'https://https://%';
update catalogue.providers set website='https://www.aut.ac.nz',updated_at=now()
where id='39301fa8-bff2-4389-bbcd-32d8415fae04' and website like 'https://https://%';
update catalogue.providers set website='https://www.lincoln.ac.nz',updated_at=now()
where id='248374d1-0629-41cd-a6f4-0804c422a4ff' and website like 'https://https://%';

with targets(provider_id,url) as (values
 ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0'::uuid,'https://adelaideuni.edu.au'),
 ('8e1adb6c-e069-43db-9584-bd054255e702'::uuid,'https://www.rmit.edu.au'),
 ('e55396d2-869a-46ef-9d17-841c7eab1313'::uuid,'https://www.uq.edu.au'),
 ('e096aba7-e1eb-4903-9a63-2bfb71e9a8b8'::uuid,'https://www.auckland.ac.nz'),
 ('39301fa8-bff2-4389-bbcd-32d8415fae04'::uuid,'https://www.aut.ac.nz'),
 ('248374d1-0629-41cd-a6f4-0804c422a4ff'::uuid,'https://www.lincoln.ac.nz'),
 ('ab12c7f8-e368-453d-9dfe-4ab8bd744829'::uuid,'https://www.otago.ac.nz')
), rows as (
 select t.provider_id,p.country_id,t.url,p.canonical_name
 from targets t join catalogue.providers p on p.id=t.provider_id
)
insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'web_catalogue',provider_id,country_id,url,canonical_name||' official Provider homepage',100,'active',
 jsonb_build_object('authority','first_party_provider','purpose','H11 provider logo and shared Provider-page acquisition','change_control_ref','CF-CHG-20260903-101')
from rows r
where not exists(select 1 from pipeline.sources s where s.provider_id=r.provider_id and s.source_type='web_catalogue' and lower(rtrim(s.url,'/'))=lower(rtrim(r.url,'/')));

with targets(provider_id) as (values
 ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0'::uuid),
 ('8e1adb6c-e069-43db-9584-bd054255e702'::uuid),
 ('e55396d2-869a-46ef-9d17-841c7eab1313'::uuid),
 ('e096aba7-e1eb-4903-9a63-2bfb71e9a8b8'::uuid),
 ('39301fa8-bff2-4389-bbcd-32d8415fae04'::uuid),
 ('248374d1-0629-41cd-a6f4-0804c422a4ff'::uuid),
 ('ab12c7f8-e368-453d-9dfe-4ab8bd744829'::uuid)
), anchors as (
 select distinct on(s.provider_id) s.id source_id,s.provider_id,c.iso_alpha2 country_code
 from pipeline.sources s join ref.countries c on c.id=s.country_id join targets t on t.provider_id=s.provider_id
 where s.source_type='web_catalogue' and nullif(s.url,'') is not null and s.status='active'
 order by s.provider_id,s.trust_rank desc nulls last,s.updated_at desc
)
insert into pipeline.layer2_source_profiles(source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,enabled,paused,operational_owner,freshness_sla_hours,schedule_text)
select source_id,lower(country_code)||'-provider-logo-'||provider_id::text,'provider_asset','website','provider_asset','first_party',true,false,'PIM/Data Operations',2160,'90-day routine; monthly hash check'
from anchors
on conflict(profile_key) do update set source_id=excluded.source_id,enabled=true,paused=false,updated_at=now();

do $$
declare r record;cfg jsonb;h text;val jsonb;vid uuid;vno int;
begin
 for r in
  select p.*,s.url
  from pipeline.layer2_source_profiles p join pipeline.sources s on s.id=p.source_id
  where p.domain='provider_asset' and p.profile_key in(
    'au-provider-logo-de2201a1-69ee-40ff-b6aa-0e54e535e6c0',
    'au-provider-logo-8e1adb6c-e069-43db-9584-bd054255e702',
    'au-provider-logo-e55396d2-869a-46ef-9d17-841c7eab1313',
    'nz-provider-logo-e096aba7-e1eb-4903-9a63-2bfb71e9a8b8',
    'nz-provider-logo-39301fa8-bff2-4389-bbcd-32d8415fae04',
    'nz-provider-logo-248374d1-0629-41cd-a6f4-0804c422a4ff',
    'nz-provider-logo-ab12c7f8-e368-453d-9dfe-4ab8bd744829'
  )
 loop
  cfg:=jsonb_build_object(
   'acquisition_method','website','base_domain',regexp_replace(r.url,'^(https?://[^/]+).*$','\1'),
   'discovery_url',r.url,'url_patterns',jsonb_build_array(r.url),
   'headers',jsonb_build_object('user_agent','CourseFinder deterministic Layer 2 acquisition'),
   'rate_limit_per_minute',30,'concurrency',2,'timeout_seconds',60,
   'retry',jsonb_build_object('max_attempts',2,'backoff','exponential'),'robots_policy','respect',
   'allowed_mime_types',jsonb_build_array('text/html','application/json','image/svg+xml','image/png','image/jpeg','image/webp'),
   'max_payload_mb',25,'target_entity_type','provider_asset','evidence_required',true,
   'freshness_sla_hours',2160,'schedule','90-day routine; monthly hash check',
   'shared_fetch_ttl_hours',24,'reuse_shared_fetch',true,
   'fanout_domains',jsonb_build_array('course_facts','scholarship','provider_asset'),
   'content_change_policy','reuse same-url Evidence inside TTL; hash before downstream extraction; no direct canonical mutation',
   'change_control_ref','CF-CHG-20260903-101');
  h:=encode(extensions.digest(cfg::text,'sha256'),'hex');
  val:=security.layer2_validate_profile_config(cfg);
  select coalesce(max(version_no),0)+1 into vno from pipeline.layer2_source_profile_versions where profile_id=r.id;
  insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref)
  values(r.id,vno,cfg,h,case when (val->>'valid')::boolean then 'valid' else 'invalid' end,val,'CF-CHG-20260903-101')
  on conflict(profile_id,configuration_hash) do update set validation_result=excluded.validation_result
  returning id into vid;
  update pipeline.layer2_source_profiles set current_version_id=vid,updated_at=now() where id=r.id;
 end loop;
end $$;

with ap as (
 select id,provider_key from pipeline.layer2_acquisition_providers where provider_key in('direct-http','firecrawl','zenrows')
), prof as (
 select id from pipeline.layer2_source_profiles
 where domain='provider_asset' and profile_key in(
    'au-provider-logo-de2201a1-69ee-40ff-b6aa-0e54e535e6c0',
    'au-provider-logo-8e1adb6c-e069-43db-9584-bd054255e702',
    'au-provider-logo-e55396d2-869a-46ef-9d17-841c7eab1313',
    'nz-provider-logo-e096aba7-e1eb-4903-9a63-2bfb71e9a8b8',
    'nz-provider-logo-39301fa8-bff2-4389-bbcd-32d8415fae04',
    'nz-provider-logo-248374d1-0629-41cd-a6f4-0804c422a4ff',
    'nz-provider-logo-ab12c7f8-e368-453d-9dfe-4ab8bd744829'
 )
)
insert into pipeline.layer2_profile_provider_routes(profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref)
select prof.id,ap.id,case ap.provider_key when 'direct-http' then 10 when 'firecrawl' then 40 else 50 end,true,'{}'::jsonb,'{}'::jsonb,
 case when ap.provider_key='firecrawl' then '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":true,"capture_screenshot_on_extraction_failure":true}'::jsonb else '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":false}'::jsonb end,
 '["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb,'CF-CHG-20260903-101'
from prof cross join ap
on conflict(profile_id,acquisition_provider_id) do update set priority=excluded.priority,enabled=true,evidence_policy=excluded.evidence_policy,fallback_on=excluded.fallback_on,change_control_ref=excluded.change_control_ref,updated_at=now();

-- One consistent automatic-approval threshold: only >=0.90 may be accepted/promoted.
update pipeline.provider_asset_candidates
set status='needs_review',
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('threshold_reconciled_at',now(),'threshold',0.90,'change_control_ref','CF-CHG-20260903-101')
where status='accepted' and coalesce(confidence,0)<0.90;

create or replace function public.layer2_provider_page_fanout_apply(
 p_shared_fetch_id uuid,
 p_logo_candidates jsonb default '[]'::jsonb,
 p_scholarship_links jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','pipeline','catalogue' as $$
declare v_ctx jsonb;v_logo jsonb;v_link jsonb;v_logo_count int:=0;v_sch_count int:=0;
begin
 select public.layer2_shared_fetch_fanout_context(p_shared_fetch_id) into v_ctx;
 if v_ctx is null or v_ctx='null'::jsonb then raise exception 'shared_fetch_not_found' using errcode='P0002'; end if;
 for v_logo in select value from jsonb_array_elements(coalesce(p_logo_candidates,'[]'::jsonb)) loop
   insert into pipeline.provider_asset_candidates(provider_id,profile_id,source_url,asset_url,asset_type,evidence_id,content_hash,confidence,status,metadata)
   values((v_ctx->>'provider_id')::uuid,nullif(v_ctx->>'logo_profile_id','')::uuid,v_ctx->>'source_url',v_logo->>'url','logo',
     (v_ctx->>'evidence_id')::uuid,null,nullif(v_logo->>'score','')::numeric,
     case when coalesce((v_logo->>'score')::numeric,0)>=0.90 then 'accepted'
          when coalesce((v_logo->>'score')::numeric,0)>=0.65 then 'needs_review' else 'discovered' end,
     jsonb_build_object('worker_version','layer2-provider-page-fanout-v1.3','kind',v_logo->>'kind','alt',v_logo->>'alt',
       'selector_hint',v_logo->>'selector_hint','canonical_mutation_authorised',false,'approval_threshold',0.90,'change_control_ref','CF-CHG-20260903-101'))
   on conflict(provider_id,asset_url) do update set profile_id=excluded.profile_id,source_url=excluded.source_url,evidence_id=excluded.evidence_id,
     confidence=excluded.confidence,status=excluded.status,metadata=excluded.metadata,discovered_at=now();
   v_logo_count:=v_logo_count+1;
 end loop;
 for v_link in select value from jsonb_array_elements(coalesce(p_scholarship_links,'[]'::jsonb)) loop
   insert into pipeline.layer2_scholarship_discovery_candidates(source_id,evidence_id,source_profile_version_id,scholarship_url,observed_title,status)
   values((v_ctx->>'source_id')::uuid,(v_ctx->>'evidence_id')::uuid,nullif(v_ctx->>'scholarship_profile_version_id','')::uuid,v_link->>'url',nullif(v_link->>'title',''),'discovered')
   on conflict(evidence_id,scholarship_url) do nothing;
   if found then v_sch_count:=v_sch_count+1; end if;
 end loop;
 update pipeline.layer2_fanout_tasks set status='completed',completed_at=now(),last_error=null,
   metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('worker_version','layer2-provider-page-fanout-v1.3','logo_candidates',jsonb_array_length(coalesce(p_logo_candidates,'[]'::jsonb)),'scholarship_links',jsonb_array_length(coalesce(p_scholarship_links,'[]'::jsonb)))
 where shared_fetch_id=p_shared_fetch_id and task_type in('provider_asset','scholarship_discovery');
 return jsonb_build_object('provider_id',v_ctx->>'provider_id','logo_rows_written',v_logo_count,'scholarship_rows_written',v_sch_count);
end $$;
revoke all on function public.layer2_provider_page_fanout_apply(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_provider_page_fanout_apply(uuid,jsonb,jsonb) to service_role;

commit;
