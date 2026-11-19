begin;

create table if not exists pipeline.provider_directory_observations(
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references pipeline.sources(id),
  evidence_id uuid not null references pipeline.evidence_artifacts(id),
  directory_name text not null,
  directory_id text,
  observed_name text not null,
  country_code text,
  institution_url text,
  logo_url text,
  matched_provider_id uuid references catalogue.providers(id),
  match_method text,
  match_confidence numeric(5,4),
  observed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique(source_id,evidence_id,observed_name,institution_url)
);
alter table pipeline.provider_directory_observations enable row level security;
revoke all on pipeline.provider_directory_observations from public,anon,authenticated;

with x(code,label,url) as (values
 ('AU','Hotcourses Abroad — Australia university directory','https://www.hotcoursesabroad.com/study/australia/international/schools-colleges-university/9/list.html'),
 ('NZ','Hotcourses Abroad — New Zealand university directory','https://www.hotcoursesabroad.com/study/newzealand/international/schools-colleges-university/134/list.html')
)
insert into pipeline.sources(source_type,country_id,url,label,trust_rank,status,metadata)
select 'third_party_directory',c.id,x.url,x.label,30,'active',
 jsonb_build_object(
   'directory','hotcourses_abroad',
   'purpose','provider_directory_logo_reconciliation',
   'canonical_identity_authority',false,
   'operator_fallback_reuse_approved',true,
   'change_control_ref','CF-CHG-20260904-102'
 )
from x join ref.countries c on c.iso_alpha2=x.code
where not exists(
  select 1 from pipeline.sources s
  where s.source_type='third_party_directory'
    and s.url=x.url
    and s.provider_id is null
);

with s as (
 select s.id source_id,c.iso_alpha2 code,s.url
 from pipeline.sources s join ref.countries c on c.id=s.country_id
 where s.source_type='third_party_directory'
   and s.provider_id is null
   and s.metadata->>'directory'='hotcourses_abroad'
   and s.url in(
    'https://www.hotcoursesabroad.com/study/australia/international/schools-colleges-university/9/list.html',
    'https://www.hotcoursesabroad.com/study/newzealand/international/schools-colleges-university/134/list.html'
   )
)
insert into pipeline.layer2_source_profiles(
 source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,
 enabled,paused,operational_owner,freshness_sla_hours,schedule_text
)
select source_id,lower(code)||'-hotcourses-provider-directory','provider_asset','website','provider_asset','third_party_discovery',
 true,false,'PIM/Data Operations',720,'monthly directory reconciliation; manual on demand'
from s
on conflict(profile_key) do update set source_id=excluded.source_id,enabled=true,paused=false,updated_at=now();

do $$
declare r record;cfg jsonb;h text;val jsonb;vid uuid;vno int;
begin
 for r in
   select p.*,s.url
   from pipeline.layer2_source_profiles p join pipeline.sources s on s.id=p.source_id
   where p.profile_key in('au-hotcourses-provider-directory','nz-hotcourses-provider-directory')
 loop
   cfg:=jsonb_build_object(
     'acquisition_method','website',
     'base_domain','https://www.hotcoursesabroad.com',
     'discovery_url',r.url,
     'url_patterns',jsonb_build_array(r.url),
     'headers',jsonb_build_object('user_agent','CourseFinder Provider Directory Reconciliation/1.0'),
     'rate_limit_per_minute',10,
     'concurrency',1,
     'timeout_seconds',90,
     'retry',jsonb_build_object('max_attempts',1,'backoff','fixed'),
     'robots_policy','respect',
     'allowed_mime_types',jsonb_build_array('text/html','application/json'),
     'max_payload_mb',25,
     'target_entity_type','provider_asset',
     'evidence_required',true,
     'freshness_sla_hours',720,
     'schedule','monthly directory reconciliation; manual on demand',
     'shared_fetch_ttl_hours',0,
     'reuse_shared_fetch',false,
     'fanout_domains','[]'::jsonb,
     'content_change_policy','retain each directory Evidence revision; parser produces reconciliation observations only',
     'change_control_ref','CF-CHG-20260904-102'
   );
   h:=encode(extensions.digest(cfg::text,'sha256'),'hex');
   val:=security.layer2_validate_profile_config(cfg);
   select coalesce(max(version_no),0)+1 into vno
   from pipeline.layer2_source_profile_versions where profile_id=r.id;
   insert into pipeline.layer2_source_profile_versions(
     profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref
   ) values(
     r.id,vno,cfg,h,case when (val->>'valid')::boolean then 'valid' else 'invalid' end,val,'CF-CHG-20260904-102'
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
 select id from pipeline.layer2_source_profiles
 where profile_key in('au-hotcourses-provider-directory','nz-hotcourses-provider-directory')
)
insert into pipeline.layer2_profile_provider_routes(
 profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,
 evidence_policy,fallback_on,change_control_ref
)
select prof.id,ap.id,case ap.provider_key when 'direct-http' then 10 else 40 end,true,
 '{}'::jsonb,'{}'::jsonb,
 case when ap.provider_key='firecrawl'
   then '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":true}'::jsonb
   else '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":false}'::jsonb
 end,
 '["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb,
 'CF-CHG-20260904-102'
from prof cross join ap
on conflict(profile_id,acquisition_provider_id) do update set
 priority=excluded.priority,enabled=true,evidence_policy=excluded.evidence_policy,
 fallback_on=excluded.fallback_on,change_control_ref=excluded.change_control_ref,updated_at=now();

create or replace function public.layer2_hotcourses_directory_apply(
 p_evidence_id uuid,
 p_rows jsonb
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline','catalogue','ref','public'
as $$
declare
 v_source uuid;
 v_country text;
 v_row jsonb;
 v_provider uuid;
 v_inserted integer:=0;
 v_matched integer:=0;
 v_dir_id text;
begin
 select e.source_id,c.iso_alpha2 into v_source,v_country
 from pipeline.evidence_artifacts e
 join pipeline.sources s on s.id=e.source_id
 left join ref.countries c on c.id=s.country_id
 where e.id=p_evidence_id
   and s.source_type='third_party_directory'
   and s.metadata->>'directory'='hotcourses_abroad';
 if v_source is null then raise exception 'hotcourses_directory_evidence_required' using errcode='22023'; end if;
 if jsonb_typeof(coalesce(p_rows,'[]'::jsonb))<>'array' then raise exception 'rows must be array' using errcode='22023'; end if;

 for v_row in select value from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb))
 loop
   v_provider:=null;
   select p.id into v_provider
   from catalogue.providers p
   join ref.countries c on c.id=p.country_id
   where c.iso_alpha2=v_country
     and coalesce(p.lifecycle_status,'active')='active'
     and regexp_replace(lower(coalesce(p.display_name,p.canonical_name,'')),'[^a-z0-9]+','','g')
         =regexp_replace(lower(coalesce(v_row->>'name','')),'[^a-z0-9]+','','g')
   order by p.id limit 1;

   v_dir_id:=coalesce(v_row->>'directory_id',
     substring(coalesce(v_row->>'institution_url','') from '/([0-9]+)/international(?:\.html)?'));

   insert into pipeline.provider_directory_observations(
     source_id,evidence_id,directory_name,directory_id,observed_name,country_code,
     institution_url,logo_url,matched_provider_id,match_method,match_confidence,metadata
   ) values(
     v_source,p_evidence_id,'hotcourses_abroad',nullif(v_dir_id,''),
     v_row->>'name',v_country,nullif(v_row->>'institution_url',''),nullif(v_row->>'logo_url',''),
     v_provider,case when v_provider is not null then 'country_exact_normalised_name' else 'unmatched' end,
     case when v_provider is not null then 1.0 else null end,
     jsonb_build_object('parser_version','hotcourses-directory-v1','change_control_ref','CF-CHG-20260904-102','canonical_identity_mutation',false)
   )
   on conflict(source_id,evidence_id,observed_name,institution_url) do update set
     directory_id=excluded.directory_id,logo_url=excluded.logo_url,matched_provider_id=excluded.matched_provider_id,
     match_method=excluded.match_method,match_confidence=excluded.match_confidence,metadata=excluded.metadata,observed_at=now();

   v_inserted:=v_inserted+1;
   if v_provider is not null then
     v_matched:=v_matched+1;
     insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,status,metadata)
     select 'third_party_directory',v_provider,p.country_id,nullif(v_row->>'institution_url',''),
       coalesce(p.display_name,p.canonical_name)||' — Hotcourses Abroad reconciliation',30,'active',
       jsonb_build_object(
         'directory','hotcourses_abroad','directory_id',nullif(v_dir_id,''),
         'purpose','provider_logo_discovery_and_reconciliation_only',
         'canonical_asset_authority',false,'operator_fallback_reuse_approved',true,
         'rights_owner_basis','university_provider_mark',
         'source_host_role','aggregator_transport_copy',
         'change_control_ref','CF-CHG-20260904-102'
       )
     from catalogue.providers p where p.id=v_provider
     on conflict do nothing;
   end if;
 end loop;

 return jsonb_build_object('evidence_id',p_evidence_id,'country_code',v_country,'rows',v_inserted,'matched',v_matched,'unmatched',v_inserted-v_matched);
end $$;

revoke all on function public.layer2_hotcourses_directory_apply(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_hotcourses_directory_apply(uuid,jsonb) to service_role;

commit;
