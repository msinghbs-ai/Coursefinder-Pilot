-- CF-186 — replay-safe current definition of the hardened international Scholarship detail batch service.
-- This replaces the historical marker so a clean environment receives the same safety boundary as Pilot.
create or replace function public.scholarship_international_detail_batch_service(
 p_actor uuid,p_action text,p_country_code text,p_scope_type text,p_scope_id uuid default null,p_limit integer default 40,p_dispatch boolean default true
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog','public','security','pipeline','catalogue','ref','scholarship'
as $$
declare
 v_rank integer:=0; v_limit integer:=least(greatest(coalesce(p_limit,40),1),100); v_scope_type text:=lower(coalesce(p_scope_type,'')); v_action text:=lower(coalesce(p_action,'')); v_scope_name text; v_candidates integer:=0; v_ready integer:=0; v_review integer:=0; v_catalogue integer:=0; v_queued integer:=0; v_dispatch jsonb:='{}'::jsonb; r record; v_source uuid; v_profile uuid; v_version uuid; v_cfg jsonb; v_provider_key text; route_rec record;
begin
 if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select coalesce(max(ro.rank),0) into v_rank from security.user_roles ur join security.roles ro on ro.code=ur.role_code where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and ro.status='active';
 if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 if v_action not in('preview','start') then raise exception 'unsupported action' using errcode='22023'; end if;
 if v_scope_type not in('country','state','university') then raise exception 'invalid scope type' using errcode='22023'; end if;
 if v_scope_type in('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;
 if v_scope_type='state' then select name into v_scope_name from ref.subdivisions where id=p_scope_id; elsif v_scope_type='university' then select canonical_name into v_scope_name from catalogue.providers where id=p_scope_id; else v_scope_name:=upper(p_country_code); end if;

 if v_action='preview' then
  with scoped_providers as (
   select distinct p.id from catalogue.providers p join ref.countries c on c.id=p.country_id where upper(c.iso_alpha2::text)=upper(p_country_code) and (v_scope_type='country' or (v_scope_type='state' and (p.subdivision_id=p_scope_id or exists(select 1 from catalogue.campuses ca where ca.provider_id=p.id and ca.subdivision_id=p_scope_id))) or (v_scope_type='university' and p.id=p_scope_id))
  ),x as (
   select c.classification,count(*) n from pipeline.layer2_scholarship_discovery_candidates c join pipeline.sources s on s.id=c.source_id join scoped_providers sp on sp.id=s.provider_id where c.status='discovered' group by c.classification
  ) select coalesce(sum(n),0),coalesce(sum(n) filter(where classification='detail_ready'),0),coalesce(sum(n) filter(where classification='needs_review'),0),coalesce(sum(n) filter(where classification='catalogue_or_filter'),0) into v_candidates,v_ready,v_review,v_catalogue from x;
  return jsonb_build_object('ok',true,'action','preview','scope_type',v_scope_type,'scope_id',p_scope_id,'scope_name',v_scope_name,'country_code',upper(p_country_code),'candidate_total',v_candidates,'detail_ready',v_ready,'needs_review',v_review,'catalogue_or_filter',v_catalogue,'max_jobs',v_limit,'publication_changed',false,'preview_mutated',false);
 end if;

 with scoped_providers as (
  select distinct p.id from catalogue.providers p join ref.countries c on c.id=p.country_id where upper(c.iso_alpha2::text)=upper(p_country_code) and (v_scope_type='country' or (v_scope_type='state' and (p.subdivision_id=p_scope_id or exists(select 1 from catalogue.campuses ca where ca.provider_id=p.id and ca.subdivision_id=p_scope_id))) or (v_scope_type='university' and p.id=p_scope_id))
 ),target as (
  select c.id,c.observed_title,c.scholarship_url,c.detail_target_url,s.url catalogue_url,s.metadata,
    regexp_replace(lower(coalesce(substring(coalesce(c.detail_target_url,c.scholarship_url) from '^https?://([^/]+)'),'')),'^www\.','') target_host,
    regexp_replace(lower(coalesce(substring(s.url from '^https?://([^/]+)'),'')),'^www\.','') catalogue_host,
    lower(coalesce(c.observed_title,'')) title_l,lower(coalesce(c.detail_target_url,c.scholarship_url,'')) url_l
  from pipeline.layer2_scholarship_discovery_candidates c join pipeline.sources s on s.id=c.source_id join scoped_providers sp on sp.id=s.provider_id
  where c.status='discovered' and coalesce(c.classification,'') not in('external_or_out_of_scope','support_or_navigation','catalogue_or_filter')
 ),classified as (
  select *,
    (target_host<>'' and catalogue_host<>'' and (target_host=catalogue_host or target_host like '%.'||catalogue_host or catalogue_host like '%.'||target_host)) same_first_party_host,
    (title_l ~ '(scholarship|award|grant|bursar|fellowship|discount)' or url_l ~ '(scholarship|award|grant|bursar|fellowship|discount)') scholarship_semantic,
    (title_l ~ '^(skip to|menu$|home$|apply$|contact|financial aid|student loans?|sponsor|fees? and|how to apply|international students?$|academic scholarships$|external scholarships$|scholarships and fees$|home country sponsored scholarships$)' or title_l ~ '(student loan|financial aid|sponsor students|study loan)') support_semantic,
    (scholarship.normalise_first_party_url(coalesce(detail_target_url,scholarship_url))=scholarship.normalise_first_party_url(catalogue_url)) same_as_catalogue,
    (coalesce(metadata->>'audience','')='international' or title_l ~ '(international|overseas|global|asean|south[ -]?east asia|southeast asia|india|indonesia|vietnam|malaysia|singapore|thailand|china|pakistan|bangladesh|sri lanka|nepal|africa|latin america|middle east)') international_qualified,
    (url_l ~ '/search\?' or url_l ~ '[?&](query|collection|form|num_ranks|f\.)=' or url_l ~ 'residency[^#]*international') filter_page
  from target
 )
 update pipeline.layer2_scholarship_discovery_candidates c set
  classification=case when not x.same_first_party_host then 'external_or_out_of_scope' when x.same_as_catalogue or x.filter_page then 'catalogue_or_filter' when x.support_semantic then 'support_or_navigation' when x.scholarship_semantic and x.international_qualified then 'detail_ready' else 'needs_review' end,
  classification_reason=case when not x.same_first_party_host then 'CF-186 external domain; not first-party Scholarship detail' when x.same_as_catalogue or x.filter_page then 'CF-186 catalogue/filter Evidence; not individual Scholarship' when x.support_semantic then 'CF-186 support/finance/navigation page; not individual Scholarship' when x.scholarship_semantic and x.international_qualified then 'CF-186 first-party individual Scholarship semantic with international qualification' else 'CF-186 first-party page not sufficiently qualified for automatic detail firing' end,
  classified_at=now()
 from classified x where c.id=x.id and c.status='discovered';

 with scoped_providers as (
  select distinct p.id from catalogue.providers p join ref.countries c on c.id=p.country_id where upper(c.iso_alpha2::text)=upper(p_country_code) and (v_scope_type='country' or (v_scope_type='state' and (p.subdivision_id=p_scope_id or exists(select 1 from catalogue.campuses ca where ca.provider_id=p.id and ca.subdivision_id=p_scope_id))) or (v_scope_type='university' and p.id=p_scope_id))
 ),x as (
  select c.classification,count(*) n from pipeline.layer2_scholarship_discovery_candidates c join pipeline.sources s on s.id=c.source_id join scoped_providers sp on sp.id=s.provider_id where c.status='discovered' group by c.classification
 ) select coalesce(sum(n),0),coalesce(sum(n) filter(where classification='detail_ready'),0),coalesce(sum(n) filter(where classification='needs_review'),0),coalesce(sum(n) filter(where classification='catalogue_or_filter'),0) into v_candidates,v_ready,v_review,v_catalogue from x;

 for r in
  with scoped_providers as (
   select distinct p.id,p.country_id from catalogue.providers p join ref.countries c on c.id=p.country_id where upper(c.iso_alpha2::text)=upper(p_country_code) and (v_scope_type='country' or (v_scope_type='state' and (p.subdivision_id=p_scope_id or exists(select 1 from catalogue.campuses ca where ca.provider_id=p.id and ca.subdivision_id=p_scope_id))) or (v_scope_type='university' and p.id=p_scope_id))
  )
  select c.id candidate_id,s.provider_id,sp.country_id,coalesce(nullif(c.detail_target_url,''),nullif(c.scholarship_url,'')) target_url,coalesce(nullif(c.observed_title,''),'International scholarship detail') observed_title
  from pipeline.layer2_scholarship_discovery_candidates c join pipeline.sources s on s.id=c.source_id join scoped_providers sp on sp.id=s.provider_id
  where c.status='discovered' and c.classification='detail_ready' and coalesce(nullif(c.detail_target_url,''),nullif(c.scholarship_url,'')) is not null
    and not exists(select 1 from pipeline.scholarship_source_records sr where rtrim(lower(sr.source_record_url),'/')=rtrim(lower(coalesce(nullif(c.detail_target_url,''),nullif(c.scholarship_url,''))),'/') and sr.status in('captured','applied') and sr.payload->>'international_gate_status' is distinct from 'review_required')
    and not exists(select 1 from pipeline.jobs j where j.domain='scholarship' and j.payload->>'candidate_id'=c.id::text and j.status in('queued','running') and j.payload->>'acquisition_stage' in('first_party_detail','first_party_detail_extraction'))
  order by s.provider_id,c.created_at,c.id limit v_limit
 loop
  v_source:=null;v_profile:=null;v_version:=null;
  select id into v_source from pipeline.sources where provider_id=r.provider_id and source_type='scholarship_detail' and rtrim(lower(url),'/')=rtrim(lower(r.target_url),'/') order by created_at desc limit 1;
  if v_source is null then insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,status,metadata) values('scholarship_detail',r.provider_id,r.country_id,r.target_url,left(r.observed_title,180),100,'active',jsonb_build_object('authority','first_party','change_control_ref','CF-186','candidate_id',r.candidate_id)) returning id into v_source; end if;
  select id,current_version_id into v_profile,v_version from pipeline.layer2_source_profiles where source_id=v_source and domain='scholarship' and acquisition_method='website' order by created_at desc limit 1;
  if v_profile is null then v_provider_key:='au-scholarship-detail-'||replace(r.provider_id::text,'-','')||'-'||substr(md5(r.target_url),1,10); insert into pipeline.layer2_source_profiles(source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,enabled,paused,operational_owner,freshness_sla_hours,schedule_text) values(v_source,v_provider_key,'scholarship','website','scholarship','first_party',true,false,'CourseFinder PIM',168,'weekly; international-only governed detail acquisition') returning id into v_profile; end if;
  select current_version_id into v_version from pipeline.layer2_source_profiles where id=v_profile;
  if v_version is null then
   v_cfg:=jsonb_build_object('retry',jsonb_build_object('backoff','exponential','max_attempts',2),'headers',jsonb_build_object('user_agent','CourseFinder deterministic Layer 2 Scholarship detail acquisition'),'schedule','weekly; international-only governed detail acquisition','base_domain',regexp_replace(r.target_url,'^(https?://[^/]+).*','\1'),'concurrency',1,'url_patterns',jsonb_build_array(r.target_url),'discovery_url',r.target_url,'robots_policy','respect','fanout_domains',jsonb_build_array('scholarship'),'max_payload_mb',20,'timeout_seconds',60,'evidence_required',true,'acquisition_method','website','allowed_mime_types',jsonb_build_array('text/html','application/json'),'change_control_ref','CF-186','reuse_shared_fetch',true,'target_entity_type','scholarship','freshness_sla_hours',168,'content_change_policy','hash before extraction; no direct publication','rate_limit_per_minute',20,'shared_fetch_ttl_hours',24);
   insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref,created_by) values(v_profile,1,v_cfg,encode(extensions.digest(v_cfg::text,'sha256'),'hex'),'valid',jsonb_build_object('international_only',true,'candidate_id',r.candidate_id),'CF-186',p_actor) returning id into v_version;
   update pipeline.layer2_source_profiles set current_version_id=v_version,updated_at=now() where id=v_profile;
  end if;
  for route_rec in select id,provider_key,priority from pipeline.layer2_acquisition_providers where enabled and provider_key in('direct-http','parsebot','firecrawl','zenrows') order by case provider_key when 'direct-http' then 10 when 'parsebot' then 20 when 'firecrawl' then 40 else 50 end loop
   if not exists(select 1 from pipeline.layer2_profile_provider_routes where profile_id=v_profile and acquisition_provider_id=route_rec.id) then
    insert into pipeline.layer2_profile_provider_routes(profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref) values(v_profile,route_rec.id,case route_rec.provider_key when 'direct-http' then 10 when 'parsebot' then 20 when 'firecrawl' then 40 else 50 end,true,'{}'::jsonb,'{}'::jsonb,jsonb_build_object('capture_raw',true,'capture_html',true,'capture_screenshot_on_failure',route_rec.provider_key='firecrawl','capture_screenshot_on_extraction_failure',route_rec.provider_key='firecrawl'),'["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb,'CF-186');
   end if;
  end loop;
  insert into pipeline.jobs(job_type,domain,provider_id,status,requested_by,payload) values('scholarship_scope_acquisition','scholarship',r.provider_id,'queued',p_actor,jsonb_build_object('profile_id',v_profile,'target_url',r.target_url,'candidate_id',r.candidate_id,'acquisition_stage','first_party_detail','international_only',true,'publication_authorised',false,'scope_type',v_scope_type,'scope_id',p_scope_id,'change_control_ref','CF-186')); v_queued:=v_queued+1;
 end loop;
 if p_dispatch and v_queued>0 then v_dispatch:=security.scholarship_scope_scheduler_tick_impl(now(),least(v_queued,20),true); else v_dispatch:=jsonb_build_object('ok',true,'dispatched',0,'dispatch_enabled',false); end if;
 return jsonb_build_object('ok',true,'action','start','scope_type',v_scope_type,'scope_id',p_scope_id,'scope_name',v_scope_name,'country_code',upper(p_country_code),'candidate_total',v_candidates,'detail_ready',v_ready,'needs_review',v_review,'catalogue_or_filter',v_catalogue,'jobs_queued',v_queued,'dispatch',v_dispatch,'publication_changed',false,'canonical_mutation_authorised',false);
end $$;

revoke all on function public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean) from public,anon,authenticated;
grant execute on function public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean) to service_role;
comment on function public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean) is 'CF-186 replay-safe current detail service: discovered-only, first-party, international, individual-Scholarship semantic qualification; captured/applied source-record reuse; no publication.';
