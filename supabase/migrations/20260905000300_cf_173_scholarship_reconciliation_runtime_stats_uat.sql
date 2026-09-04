create or replace function security.admin_scholarship_runtime_read(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','security','pipeline','scholarship','catalogue','ref','auth'
as $$
declare v_rank integer; v_country text:=upper(coalesce(nullif(p_args->>'country_code',''),'AU')); v_q text:=nullif(trim(coalesce(p_args->>'query','')),''); v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200); v_result jsonb;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 select jsonb_build_object(
   'settings',coalesce((select to_jsonb(s)-'updated_by' from pipeline.scholarship_runtime_settings s where s.country_code=v_country),jsonb_build_object('country_code',v_country,'enabled',true,'detail_batch_limit',25,'auto_dispatch',true,'catalogue_refresh_hours',168,'detail_refresh_hours',168)),
   'policy',jsonb_build_object('international_only',true,'canonical_mutation_authorised',false,'publication_authorised',false,'route_source','Administration / Scraper Config','reconciliation_rule','verified individual first-party detail only'),
   'summary',jsonb_build_object(
      'canonical',(select count(*) from scholarship.scholarships s join catalogue.providers p on p.id=s.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country),
      'published',(select count(*) from scholarship.scholarships s join catalogue.providers p on p.id=s.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and s.publication_status='published'),
      'international_canonical',(select count(*) from scholarship.scholarships s join catalogue.providers p on p.id=s.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and lower(coalesce(s.audience,''))='international'),
      'candidates',(select count(*) from pipeline.layer2_scholarship_discovery_candidates d join pipeline.sources src on src.id=d.source_id join catalogue.providers p on p.id=src.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country),
      'detail_ready',(select count(*) from pipeline.layer2_scholarship_discovery_candidates d join pipeline.sources src on src.id=d.source_id join catalogue.providers p on p.id=src.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and d.classification='detail_ready'),
      'needs_review',(select count(*) from pipeline.layer2_scholarship_discovery_candidates d join pipeline.sources src on src.id=d.source_id join catalogue.providers p on p.id=src.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and d.classification='needs_review'),
      'source_records',(select count(*) from pipeline.scholarship_source_records sr join pipeline.sources src on src.id=sr.source_id join catalogue.providers p on p.id=src.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country),
      'captured_source_records',(select count(*) from pipeline.scholarship_source_records sr join pipeline.sources src on src.id=sr.source_id join catalogue.providers p on p.id=src.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and sr.status='captured'),
      'applied_source_records',(select count(*) from pipeline.scholarship_source_records sr join pipeline.sources src on src.id=sr.source_id join catalogue.providers p on p.id=src.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and sr.status='applied'),
      'reconciliation_ready',(select count(*) from pipeline.scholarship_verified_detail_reconciliation_candidates x where x.country_code=v_country and x.reconciliation_state='ready'),
      'reconciled_unpublished',(select count(*) from pipeline.scholarship_acquisition_trace t join catalogue.providers p on p.id=t.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and t.metadata->>'reconciliation'='CF-171' and t.stage='canonical_unpublished'),
      'mapped_courses',(select count(distinct m.course_id) from scholarship.course_mappings m join scholarship.scholarships s on s.id=m.scholarship_id join catalogue.providers p on p.id=s.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and m.mapping_state='mapped'),
      'calculations',(select count(*) from scholarship.course_financial_calculations fc join catalogue.courses co on co.id=fc.course_id join catalogue.providers p on p.id=co.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and fc.calculation_status='calculated')
   ),
   'providers',coalesce((select jsonb_agg(to_jsonb(x) order by x.provider_name) from (select ps.* from pipeline.scholarship_provider_stats ps join catalogue.providers p on p.id=ps.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and (v_q is null or ps.provider_name ilike '%'||v_q||'%') order by ps.provider_name limit v_limit) x),'[]'::jsonb),
   'recent_runs',coalesce((select jsonb_agg(to_jsonb(x) order by x.requested_at desc) from (select r.id,r.country_code,r.scope_type,r.scope_id,r.provider_id,r.provider_count,r.status,r.requested_at,r.started_at,r.completed_at,r.metadata from pipeline.scholarship_scope_acquisition_requests r where r.country_code=v_country order by r.requested_at desc limit 20) x),'[]'::jsonb),
   'countries',coalesce((select jsonb_agg(jsonb_build_object('code',c.iso_alpha2::text,'name',c.name) order by c.name) from ref.countries c where exists(select 1 from catalogue.providers p where p.country_id=c.id)),'[]'::jsonb)
 ) into v_result;
 return v_result;
end $$;

create or replace function security.admin_scholarship_runtime_uat(p_country_code text default 'AU'::text)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','security','pipeline','scholarship','catalogue','ref','auth'
as $$
declare v_rank integer; v_country text:=upper(coalesce(nullif(p_country_code,''),'AU')); v_checks jsonb; v_pass integer; v_fail integer;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 with checks as (
  select * from (values
   ('settings_rls', (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='pipeline' and c.relname='scholarship_runtime_settings'), 'Runtime settings table is protected by RLS'),
   ('settings_browser_denied', not has_table_privilege('authenticated','pipeline.scholarship_runtime_settings','SELECT'), 'Browser roles cannot directly read private runtime settings'),
   ('international_only', coalesce((select (metadata->>'international_only')::boolean from pipeline.scholarship_runtime_settings where country_code=v_country),true), 'Automatic acquisition remains international-only'),
   ('publication_blocked', coalesce((select not coalesce((metadata->>'publication_authorised')::boolean,false) from pipeline.scholarship_runtime_settings where country_code=v_country),true), 'Runtime acquisition cannot publish Scholarships'),
   ('scope_service_country', to_regprocedure('public.scholarship_scope_acquisition_service(uuid,text,text,text,uuid)') is not null, 'Country/University catalogue scope service exists'),
   ('detail_batch_service', to_regprocedure('public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean)') is not null, 'International detail batching service exists'),
   ('reconciliation_service', to_regprocedure('scholarship.reconcile_verified_detail_records(uuid,text,text,uuid,integer)') is not null, 'Verified first-party detail reconciliation service exists'),
   ('reconciliation_browser_denied', not has_function_privilege('authenticated','scholarship.reconcile_verified_detail_records(uuid,text,text,uuid,integer)','EXECUTE'), 'Browser roles cannot invoke canonical reconciliation directly'),
   ('reconciled_stays_unpublished', not exists(select 1 from pipeline.scholarship_acquisition_trace t join scholarship.scholarships s on s.id=t.scholarship_id join catalogue.providers p on p.id=t.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and t.metadata->>'reconciliation'='CF-171' and s.publication_status='published'), 'Reconciled roots remain unpublished'),
   ('generic_records_not_applied', not exists(select 1 from pipeline.scholarship_source_records sr join pipeline.sources src on src.id=sr.source_id join catalogue.providers p on p.id=src.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and sr.status='applied' and coalesce(sr.payload->>'name','') ~* '^(eligibility|faq|guidelines?|menu|go to top|skip to main content|find a scholarship|scholarships? for international students|international student scholarships|all scholarship opportunities for international students|.*is blocked)$'), 'Navigation/catalogue fragments cannot become applied canonical records'),
   ('reconciliation_evidence', not exists(select 1 from pipeline.scholarship_acquisition_trace t join catalogue.providers p on p.id=t.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and t.metadata->>'reconciliation'='CF-171' and (t.verification_evidence_id is null or t.source_record_id is null)), 'Every reconciled root retains source record and Evidence links'),
   ('provider_cross_reference', to_regprocedure('security.admin_provider_scholarships(uuid)') is not null, 'Provider detail Scholarship cross-reference exists'),
   ('course_cross_reference', to_regprocedure('security.admin_course_scholarships(uuid)') is not null, 'Course detail Scholarship cross-reference exists'),
   ('financial_fail_closed', not exists(select 1 from scholarship.course_financial_calculations where calculation_status='calculated' and (course_fee_id is null or scholarship_saving_amount is null or net_fee_amount is null)), 'Calculated net fees require a concrete fee row and amounts'),
   ('source_evidence_present', exists(select 1 from pipeline.scholarship_source_records sr join pipeline.sources src on src.id=sr.source_id join catalogue.providers p on p.id=src.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and sr.evidence_id is not null), 'Scholarship source records retain Evidence'),
   ('catalogue_no_mass_publish', not exists(select 1 from pipeline.jobs j where j.domain='scholarship' and coalesce((j.payload->>'publication_authorised')::boolean,false)=true), 'Scholarship acquisition jobs have no publication authorisation')
  ) as x(code,passed,description)
 ), agg as (
   select coalesce(jsonb_agg(jsonb_build_object('code',code,'passed',passed,'description',description) order by code),'[]'::jsonb) items,
          count(*) filter(where passed)::int passed_count,count(*) filter(where not passed)::int failed_count from checks
 ) select items,passed_count,failed_count into v_checks,v_pass,v_fail from agg;
 return jsonb_build_object('country_code',v_country,'status',case when v_fail=0 then 'pass' else 'fail' end,'passed',v_pass,'failed',v_fail,'checks',v_checks,'tested_at',now());
end $$;

comment on function security.admin_scholarship_runtime_read(jsonb) is 'CF-173 guarded Scholarship runtime read includes reconciliation maturity statistics.';
comment on function security.admin_scholarship_runtime_uat(text) is 'CF-173 Scholarship UAT includes guarded reconciliation, Evidence and unpublished-only checks.';