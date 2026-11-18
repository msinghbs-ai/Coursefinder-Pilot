-- CF-247 (16 Oct 2026): two data faults found in the Zoho API review (Platform Admin 07:58: "Review zoho api v1 and updates on website v2
-- apis"), fixed before Zoho API v2 is built (Platform Admin 09:55, decisions: Creator + CRM sync keys, CSV seed + sync feed, public + named
-- contacts).
-- 1 The search projection's provider annual fee was the lowest annual fee of any year, so 441 courses at 11 universities with a 2026 and a
--   2027 fee showed the older 2026 fee in Zoho (search, lookup and the tuition range filters); fee_used and the website already used 2027.
-- 2 The website sync change check hashed each item with its freshness timestamps, so every projection refresh marked unchanged courses as
--   changed (29,952 of 37,300 courses "changed" in 24 hours; 11,896 in one hour after a refresh).
-- Replaces: the lowest annual fee of any year (now the latest year's annual fee, the lowest of that year when there are several); the item
--   hash with freshness (now without the freshness timestamps, which are still returned)
-- Retires: nothing
-- 1 Projection fee  2 Sync hash without freshness (stored hashes recomputed the same way, so nothing is marked changed by this change)
-- Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"search.refresh_course_enrichment_core_v1(boolean)": "0ff0bef5b45eb2ca08e1284cf159698d", "search.refresh_course_enrichment_core_scoped_v1(uuid[],boolean)": "18b15be58101b981c3a8d095cfe90425", "security.website_sync_check_v1(integer)": "5c4ed59ddaf352126a6fa13a09a5690a"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION search.refresh_course_enrichment_core_v1(p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'search', 'catalogue', 'scholarship', 'pipeline', 'ref', 'extensions', 'pg_temp'
AS $function$
declare
  v_rows bigint;
  v_changed bigint;
  v_unchanged bigint;
  v_stage_hash text;
  v_coverage jsonb;
begin
  drop table if exists pg_temp.cf_search_enrichment_stage;
  create temp table cf_search_enrichment_stage on commit drop as
  with global_gates as (
    select
      bool_or(domain_code='regulatory_tuition' and gate_status='approved') regulatory_ok,
      bool_or(domain_code='provider_current_tuition' and gate_status='approved') provider_fee_ok,
      bool_or(domain_code='official_course_url' and gate_status='approved') link_ok,
      bool_or(domain_code='course_intake' and gate_status='approved') intake_ok,
      bool_or(domain_code='course_english' and gate_status='approved') english_ok,
      bool_or(domain_code='scholarship' and gate_status='approved') scholarship_ok
    from search.enrichment_gates where projection_code='courses'
  )
  select d.course_id,
    case
      when d.country_code='NZ' then 'not_applicable'
      when not (select regulatory_ok from global_gates) then 'not_admitted'
      when rf.fee_id is null then 'source_null'
      when rf.amount=0 then 'zero'
      else 'present'
    end as regulatory_tuition_state,
    ((select regulatory_ok from global_gates) and rf.fee_id is not null) as has_regulatory_tuition,
    case when (select regulatory_ok from global_gates) then rf.amount end as regulatory_tuition_amount,
    case when (select regulatory_ok from global_gates) then rf.currency_code end as regulatory_tuition_currency,
    case when (select regulatory_ok from global_gates) then rf.basis end as regulatory_tuition_basis,
    ((select provider_fee_ok from global_gates) and pf.option_count>0) as has_provider_current_tuition,
    case when (select provider_fee_ok from global_gates) then pf.annual_amount end as provider_annual_tuition_amount,
    case when (select provider_fee_ok from global_gates) then pf.annual_currency end as provider_annual_tuition_currency,
    case when (select provider_fee_ok from global_gates) then coalesce(pf.options,'[]'::jsonb) else '[]'::jsonb end as provider_tuition_options,
    case when (select link_ok from global_gates) then lk.url end as official_course_url,
    case when (select intake_ok from global_gates) then coalesce(it.options,'[]'::jsonb) else '[]'::jsonb end as intake_options,
    case when (select intake_ok from global_gates) then it.earliest_date end as earliest_intake_date,
    case when (select english_ok from global_gates) then coalesce(en.options,'[]'::jsonb) else '[]'::jsonb end as english_requirement_options,
    case when (select scholarship_ok from global_gates) then coalesce(sc.options,'[]'::jsonb) else '[]'::jsonb end as scholarship_options,
    concat_ws(' ',
      case when (select intake_ok from global_gates) then it.semantic_text end,
      case when (select english_ok from global_gates) then en.semantic_text end,
      case when (select scholarship_ok from global_gates) then sc.semantic_text end
    ) as enrichment_semantic_text
  from search.course_documents d
  left join lateral (
    select f.id fee_id,f.amount,f.currency_code,f.basis
    from catalogue.course_fees f join pipeline.sources s on s.id=f.source_id
    where f.course_id=d.course_id and f.status='active' and f.audience in ('international','all')
      and f.fee_type='tuition' and f.basis='registered_total_course'
      and s.label='CRICOS Providers, Courses and Locations'
    order by f.updated_at desc nulls last,f.id limit 1
  ) rf on true
  left join lateral (
    select count(*) option_count,
      -- CF-247 16 Oct 2026: the latest year's annual fee (was the lowest of any year)
      (array_agg(f.amount order by f.fee_year desc nulls last, f.amount) filter(where f.basis in ('annual','indicative_annual')))[1] annual_amount,
      (array_agg(f.currency_code order by f.fee_year desc nulls last, f.amount) filter(where f.basis in ('annual','indicative_annual')))[1] annual_currency,
      jsonb_agg(jsonb_build_object('fee_year',f.fee_year,'amount',f.amount,'currency',trim(f.currency_code),'basis',f.basis,'load_basis',f.load_basis,'campus_id',f.campus_id,'valid_from',f.valid_from,'valid_to',f.valid_to,'last_verified_at',f.last_verified_at) order by f.fee_year desc nulls last,f.basis,f.amount,f.id) options
    from catalogue.course_fees f
    join search.enrichment_source_gates sg on sg.projection_code='courses' and sg.domain_code='provider_current_tuition' and sg.source_id=f.source_id and sg.gate_status='approved'
    where f.course_id=d.course_id and f.status='active' and f.audience in ('international','all') and f.fee_type='provider_current_tuition'
      and (f.valid_from is null or f.valid_from<=current_date) and (f.valid_to is null or f.valid_to>=current_date)
  ) pf on true
  left join lateral (
    select l.url
    from catalogue.course_links l
    join search.enrichment_source_gates sg on sg.projection_code='courses' and sg.domain_code='official_course_url' and sg.source_id=l.source_id and sg.gate_status='approved'
    where l.course_id=d.course_id and l.status='active'
      and (l.valid_from is null or l.valid_from<=current_date) and (l.valid_to is null or l.valid_to>=current_date)
    order by l.is_primary desc,l.last_verified_at desc nulls last,l.updated_at desc nulls last,l.id limit 1
  ) lk on true
  left join lateral (
    select jsonb_agg(jsonb_build_object('year',i.intake_year,'label',i.intake_label,'start_date',i.start_date,'application_deadline',i.application_deadline,'campus_id',i.campus_id) order by i.start_date nulls last,i.intake_year,i.intake_label,i.id) options,
      min(i.start_date) filter(where i.start_date>=current_date) earliest_date,
      string_agg(distinct concat_ws(' ',i.intake_year::text,i.intake_label), ' ' order by concat_ws(' ',i.intake_year::text,i.intake_label)) semantic_text
    from catalogue.course_intakes i
    join search.enrichment_source_gates sg on sg.projection_code='courses' and sg.domain_code='course_intake' and sg.source_id=i.source_id and sg.gate_status='approved'
    where i.course_id=d.course_id and i.status='active'
  ) it on true
  left join lateral (
    select jsonb_agg(jsonb_build_object('test_code',t.code,'test_name',t.name,'overall_score',er.overall_score,'component_scores',er.component_scores,'notes',er.notes,'valid_from',er.valid_from,'valid_to',er.valid_to,'last_verified_at',er.last_verified_at) order by t.code,er.overall_score,er.id) options,
      string_agg(distinct concat_ws(' ',t.name,t.code,er.overall_score::text), ' ' order by concat_ws(' ',t.name,t.code,er.overall_score::text)) semantic_text
    from catalogue.course_english_requirements er
    join ref.english_tests t on t.id=er.english_test_id
    join search.enrichment_source_gates sg on sg.projection_code='courses' and sg.domain_code='course_english' and sg.source_id=er.source_id and sg.gate_status='approved'
    where er.course_id=d.course_id and er.status='active'
      and (er.valid_from is null or er.valid_from<=current_date) and (er.valid_to is null or er.valid_to>=current_date)
  ) en on true
  left join lateral (
    select jsonb_agg(jsonb_build_object('scholarship_key',s.stable_key,'name',s.name,'award_value_text',scholarship.value_label(s.id),'academic_year',s.academic_year,'application_close_date',s.application_close_date,'source_url',s.source_url,
             'audience',s.audience,'nationalities',s.nationalities,'is_maximum',s.award_value_is_maximum,
             'saving_per_year',fc.scholarship_saving_amount,'saving_currency',fc.currency_code,'saving_basis',fc.fee_basis)
             order by fc.scholarship_saving_amount desc nulls last, s.name) options,
      string_agg(s.name,' ' order by s.name) semantic_text
    from scholarship.course_mappings cm join scholarship.scholarships s on s.id=cm.scholarship_id
    left join scholarship.course_financial_calculations fc on fc.mapping_id=cm.id and fc.calculation_status='calculated'
    where cm.course_id=d.course_id and cm.mapping_state='mapped'
      and s.lifecycle_status='active' and s.publication_status in ('published','internal')
      and s.audience in ('international','international_and_domestic')
  ) sc on true;

  alter table cf_search_enrichment_stage add column enrichment_content_hash text;
  update cf_search_enrichment_stage s set enrichment_content_hash=encode(extensions.digest(jsonb_build_object(
    'regulatory_state',s.regulatory_tuition_state,'regulatory_amount',s.regulatory_tuition_amount,'regulatory_currency',s.regulatory_tuition_currency,'regulatory_basis',s.regulatory_tuition_basis,
    'has_provider_current_tuition',s.has_provider_current_tuition,'provider_annual_amount',s.provider_annual_tuition_amount,'provider_annual_currency',s.provider_annual_tuition_currency,'provider_options',s.provider_tuition_options,
    'official_url',s.official_course_url,'intakes',s.intake_options,'english',s.english_requirement_options,'scholarships',s.scholarship_options,'semantic_text',s.enrichment_semantic_text
  )::text,'sha256'),'hex') where true;

  select count(*) into v_rows from cf_search_enrichment_stage;
  select count(*) into v_changed from cf_search_enrichment_stage s join search.course_documents d using(course_id) where d.enrichment_content_hash is distinct from s.enrichment_content_hash;
  select count(*) into v_unchanged from cf_search_enrichment_stage s join search.course_documents d using(course_id) where d.enrichment_content_hash is not distinct from s.enrichment_content_hash;
  select encode(extensions.digest(coalesce(string_agg(course_id::text||':'||enrichment_content_hash,'|' order by course_id::text),''),'sha256'),'hex') into v_stage_hash from cf_search_enrichment_stage;
  select jsonb_build_object(
    'regulatory_present',count(*) filter(where regulatory_tuition_state='present'),
    'regulatory_zero',count(*) filter(where regulatory_tuition_state='zero'),
    'regulatory_source_null',count(*) filter(where regulatory_tuition_state='source_null'),
    'regulatory_not_applicable',count(*) filter(where regulatory_tuition_state='not_applicable'),
    'with_provider_current_tuition',count(*) filter(where has_provider_current_tuition),
    'with_provider_annual_tuition',count(*) filter(where provider_annual_tuition_amount is not null),
    'with_official_url',count(*) filter(where official_course_url is not null),
    'with_intake',count(*) filter(where jsonb_array_length(intake_options)>0),
    'with_english',count(*) filter(where jsonb_array_length(english_requirement_options)>0),
    'with_scholarship',count(*) filter(where jsonb_array_length(scholarship_options)>0)
  ) into v_coverage from cf_search_enrichment_stage;

  if p_apply then
    update search.course_documents d set
      regulatory_tuition_state=s.regulatory_tuition_state,
      has_regulatory_tuition=s.has_regulatory_tuition,
      regulatory_tuition_amount=s.regulatory_tuition_amount,
      regulatory_tuition_currency=s.regulatory_tuition_currency,
      regulatory_tuition_basis=s.regulatory_tuition_basis,
      has_provider_current_tuition=s.has_provider_current_tuition,
      has_fee=s.has_provider_current_tuition,
      provider_annual_tuition_amount=s.provider_annual_tuition_amount,
      provider_annual_tuition_currency=s.provider_annual_tuition_currency,
      provider_tuition_options=s.provider_tuition_options,
      official_course_url=s.official_course_url,
      has_link=(s.official_course_url is not null),
      intake_options=s.intake_options,
      earliest_intake_date=s.earliest_intake_date,
      has_intake=(jsonb_array_length(s.intake_options)>0),
      english_requirement_options=s.english_requirement_options,
      has_english=(jsonb_array_length(s.english_requirement_options)>0),
      scholarship_options=s.scholarship_options,
      has_scholarship=(jsonb_array_length(s.scholarship_options)>0),
      enrichment_semantic_text=nullif(trim(s.enrichment_semantic_text),''),
      enrichment_content_hash=s.enrichment_content_hash,
      search_text=concat_ws(' ',d.course_title,d.provider_name,d.course_code,d.study_level_code,d.primary_field_name,array_to_string(d.collection_names,' '),array_to_string(d.academic_option_names,' '),d.description,nullif(trim(s.enrichment_semantic_text),'')),
      search_tsv=setweight(to_tsvector('english',coalesce(d.course_title,'')),'A') || setweight(to_tsvector('english',coalesce(d.provider_name,'')),'B') || setweight(to_tsvector('english',concat_ws(' ',coalesce(d.course_code,''),coalesce(d.study_level_code,''),coalesce(d.primary_field_name,''),coalesce(array_to_string(d.collection_names,' '),''),coalesce(array_to_string(d.academic_option_names,' '),''))),'B') || setweight(to_tsvector('english',concat_ws(' ',coalesce(d.description,''),coalesce(s.enrichment_semantic_text,''))),'C'),
      semantic_content_hash=encode(extensions.digest(jsonb_build_object('base',d.course_stable_key,'provider',d.provider_name,'title',d.course_title,'code',d.course_code,'level',d.study_level_code,'field',d.primary_field_code,'collections',d.collection_names,'academic_options',d.academic_option_names,'description',d.description,'enrichment',nullif(trim(s.enrichment_semantic_text),''))::text,'sha256'),'hex'),
      projection_version='course-v3',
      generated_at=now(),
      updated_at=now()
    from cf_search_enrichment_stage s where d.course_id=s.course_id and (d.enrichment_content_hash is distinct from s.enrichment_content_hash or d.projection_version is distinct from 'course-v3' or d.updated_at = now());
  end if;

  return jsonb_build_object('projection_version','course-v3','apply',p_apply,'rows',v_rows,'changed',v_changed,'unchanged',v_unchanged,'stage_hash',v_stage_hash,'coverage',v_coverage);
end
$function$;

CREATE OR REPLACE FUNCTION search.refresh_course_enrichment_core_scoped_v1(p_course_ids uuid[], p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'search', 'catalogue', 'scholarship', 'pipeline', 'ref', 'extensions', 'pg_temp'
AS $function$
declare
  v_rows bigint;
  v_changed bigint;
  v_unchanged bigint;
  v_stage_hash text;
  v_coverage jsonb;
begin
  drop table if exists pg_temp.cf_search_enrichment_stage;
  create temp table cf_search_enrichment_stage on commit drop as
  with global_gates as (
    select
      bool_or(domain_code='regulatory_tuition' and gate_status='approved') regulatory_ok,
      bool_or(domain_code='provider_current_tuition' and gate_status='approved') provider_fee_ok,
      bool_or(domain_code='official_course_url' and gate_status='approved') link_ok,
      bool_or(domain_code='course_intake' and gate_status='approved') intake_ok,
      bool_or(domain_code='course_english' and gate_status='approved') english_ok,
      bool_or(domain_code='scholarship' and gate_status='approved') scholarship_ok
    from search.enrichment_gates where projection_code='courses'
  )
  select d.course_id,
    case
      when d.country_code='NZ' then 'not_applicable'
      when not (select regulatory_ok from global_gates) then 'not_admitted'
      when rf.fee_id is null then 'source_null'
      when rf.amount=0 then 'zero'
      else 'present'
    end as regulatory_tuition_state,
    ((select regulatory_ok from global_gates) and rf.fee_id is not null) as has_regulatory_tuition,
    case when (select regulatory_ok from global_gates) then rf.amount end as regulatory_tuition_amount,
    case when (select regulatory_ok from global_gates) then rf.currency_code end as regulatory_tuition_currency,
    case when (select regulatory_ok from global_gates) then rf.basis end as regulatory_tuition_basis,
    ((select provider_fee_ok from global_gates) and pf.option_count>0) as has_provider_current_tuition,
    case when (select provider_fee_ok from global_gates) then pf.annual_amount end as provider_annual_tuition_amount,
    case when (select provider_fee_ok from global_gates) then pf.annual_currency end as provider_annual_tuition_currency,
    case when (select provider_fee_ok from global_gates) then coalesce(pf.options,'[]'::jsonb) else '[]'::jsonb end as provider_tuition_options,
    case when (select link_ok from global_gates) then lk.url end as official_course_url,
    case when (select intake_ok from global_gates) then coalesce(it.options,'[]'::jsonb) else '[]'::jsonb end as intake_options,
    case when (select intake_ok from global_gates) then it.earliest_date end as earliest_intake_date,
    case when (select english_ok from global_gates) then coalesce(en.options,'[]'::jsonb) else '[]'::jsonb end as english_requirement_options,
    case when (select scholarship_ok from global_gates) then coalesce(sc.options,'[]'::jsonb) else '[]'::jsonb end as scholarship_options,
    concat_ws(' ',
      case when (select intake_ok from global_gates) then it.semantic_text end,
      case when (select english_ok from global_gates) then en.semantic_text end,
      case when (select scholarship_ok from global_gates) then sc.semantic_text end
    ) as enrichment_semantic_text
  from search.course_documents d
  left join lateral (
    select f.id fee_id,f.amount,f.currency_code,f.basis
    from catalogue.course_fees f join pipeline.sources s on s.id=f.source_id
    where f.course_id=d.course_id and f.status='active' and f.audience in ('international','all')
      and f.fee_type='tuition' and f.basis='registered_total_course'
      and s.label='CRICOS Providers, Courses and Locations'
    order by f.updated_at desc nulls last,f.id limit 1
  ) rf on true
  left join lateral (
    select count(*) option_count,
      -- CF-247 16 Oct 2026: the latest year's annual fee (was the lowest of any year)
      (array_agg(f.amount order by f.fee_year desc nulls last, f.amount) filter(where f.basis in ('annual','indicative_annual')))[1] annual_amount,
      (array_agg(f.currency_code order by f.fee_year desc nulls last, f.amount) filter(where f.basis in ('annual','indicative_annual')))[1] annual_currency,
      jsonb_agg(jsonb_build_object('fee_year',f.fee_year,'amount',f.amount,'currency',trim(f.currency_code),'basis',f.basis,'load_basis',f.load_basis,'campus_id',f.campus_id,'valid_from',f.valid_from,'valid_to',f.valid_to,'last_verified_at',f.last_verified_at) order by f.fee_year desc nulls last,f.basis,f.amount,f.id) options
    from catalogue.course_fees f
    join search.enrichment_source_gates sg on sg.projection_code='courses' and sg.domain_code='provider_current_tuition' and sg.source_id=f.source_id and sg.gate_status='approved'
    where f.course_id=d.course_id and f.status='active' and f.audience in ('international','all') and f.fee_type='provider_current_tuition'
      and (f.valid_from is null or f.valid_from<=current_date) and (f.valid_to is null or f.valid_to>=current_date)
  ) pf on true
  left join lateral (
    select l.url
    from catalogue.course_links l
    join search.enrichment_source_gates sg on sg.projection_code='courses' and sg.domain_code='official_course_url' and sg.source_id=l.source_id and sg.gate_status='approved'
    where l.course_id=d.course_id and l.status='active'
      and (l.valid_from is null or l.valid_from<=current_date) and (l.valid_to is null or l.valid_to>=current_date)
    order by l.is_primary desc,l.last_verified_at desc nulls last,l.updated_at desc nulls last,l.id limit 1
  ) lk on true
  left join lateral (
    select jsonb_agg(jsonb_build_object('year',i.intake_year,'label',i.intake_label,'start_date',i.start_date,'application_deadline',i.application_deadline,'campus_id',i.campus_id) order by i.start_date nulls last,i.intake_year,i.intake_label,i.id) options,
      min(i.start_date) filter(where i.start_date>=current_date) earliest_date,
      string_agg(distinct concat_ws(' ',i.intake_year::text,i.intake_label), ' ' order by concat_ws(' ',i.intake_year::text,i.intake_label)) semantic_text
    from catalogue.course_intakes i
    join search.enrichment_source_gates sg on sg.projection_code='courses' and sg.domain_code='course_intake' and sg.source_id=i.source_id and sg.gate_status='approved'
    where i.course_id=d.course_id and i.status='active'
  ) it on true
  left join lateral (
    select jsonb_agg(jsonb_build_object('test_code',t.code,'test_name',t.name,'overall_score',er.overall_score,'component_scores',er.component_scores,'notes',er.notes,'valid_from',er.valid_from,'valid_to',er.valid_to,'last_verified_at',er.last_verified_at) order by t.code,er.overall_score,er.id) options,
      string_agg(distinct concat_ws(' ',t.name,t.code,er.overall_score::text), ' ' order by concat_ws(' ',t.name,t.code,er.overall_score::text)) semantic_text
    from catalogue.course_english_requirements er
    join ref.english_tests t on t.id=er.english_test_id
    join search.enrichment_source_gates sg on sg.projection_code='courses' and sg.domain_code='course_english' and sg.source_id=er.source_id and sg.gate_status='approved'
    where er.course_id=d.course_id and er.status='active'
      and (er.valid_from is null or er.valid_from<=current_date) and (er.valid_to is null or er.valid_to>=current_date)
  ) en on true
  left join lateral (
    select jsonb_agg(jsonb_build_object('scholarship_key',s.stable_key,'name',s.name,'award_value_text',scholarship.value_label(s.id),'academic_year',s.academic_year,'application_close_date',s.application_close_date,'source_url',s.source_url,
             'audience',s.audience,'nationalities',s.nationalities,'is_maximum',s.award_value_is_maximum,
             'saving_per_year',fc.scholarship_saving_amount,'saving_currency',fc.currency_code,'saving_basis',fc.fee_basis)
             order by fc.scholarship_saving_amount desc nulls last, s.name) options,
      string_agg(s.name,' ' order by s.name) semantic_text
    from scholarship.course_mappings cm join scholarship.scholarships s on s.id=cm.scholarship_id
    left join scholarship.course_financial_calculations fc on fc.mapping_id=cm.id and fc.calculation_status='calculated'
    where cm.course_id=d.course_id and cm.mapping_state='mapped'
      and s.lifecycle_status='active' and s.publication_status in ('published','internal')
      and s.audience in ('international','international_and_domestic')
  ) sc on true
  where d.course_id = any(p_course_ids);

  alter table cf_search_enrichment_stage add column enrichment_content_hash text;
  update cf_search_enrichment_stage s set enrichment_content_hash=encode(extensions.digest(jsonb_build_object(
    'regulatory_state',s.regulatory_tuition_state,'regulatory_amount',s.regulatory_tuition_amount,'regulatory_currency',s.regulatory_tuition_currency,'regulatory_basis',s.regulatory_tuition_basis,
    'has_provider_current_tuition',s.has_provider_current_tuition,'provider_annual_amount',s.provider_annual_tuition_amount,'provider_annual_currency',s.provider_annual_tuition_currency,'provider_options',s.provider_tuition_options,
    'official_url',s.official_course_url,'intakes',s.intake_options,'english',s.english_requirement_options,'scholarships',s.scholarship_options,'semantic_text',s.enrichment_semantic_text
  )::text,'sha256'),'hex')
  where s.course_id is not null;

  select count(*) into v_rows from cf_search_enrichment_stage;
  select count(*) into v_changed from cf_search_enrichment_stage s join search.course_documents d using(course_id) where d.enrichment_content_hash is distinct from s.enrichment_content_hash;
  select count(*) into v_unchanged from cf_search_enrichment_stage s join search.course_documents d using(course_id) where d.enrichment_content_hash is not distinct from s.enrichment_content_hash;
  select encode(extensions.digest(coalesce(string_agg(course_id::text||':'||enrichment_content_hash,'|' order by course_id::text),''),'sha256'),'hex') into v_stage_hash from cf_search_enrichment_stage;
  select jsonb_build_object(
    'regulatory_present',count(*) filter(where regulatory_tuition_state='present'),
    'regulatory_zero',count(*) filter(where regulatory_tuition_state='zero'),
    'regulatory_source_null',count(*) filter(where regulatory_tuition_state='source_null'),
    'regulatory_not_applicable',count(*) filter(where regulatory_tuition_state='not_applicable'),
    'with_provider_current_tuition',count(*) filter(where has_provider_current_tuition),
    'with_provider_annual_tuition',count(*) filter(where provider_annual_tuition_amount is not null),
    'with_official_url',count(*) filter(where official_course_url is not null),
    'with_intake',count(*) filter(where jsonb_array_length(intake_options)>0),
    'with_english',count(*) filter(where jsonb_array_length(english_requirement_options)>0),
    'with_scholarship',count(*) filter(where jsonb_array_length(scholarship_options)>0)
  ) into v_coverage from cf_search_enrichment_stage;

  if p_apply then
    update search.course_documents d set
      regulatory_tuition_state=s.regulatory_tuition_state,
      has_regulatory_tuition=s.has_regulatory_tuition,
      regulatory_tuition_amount=s.regulatory_tuition_amount,
      regulatory_tuition_currency=s.regulatory_tuition_currency,
      regulatory_tuition_basis=s.regulatory_tuition_basis,
      has_provider_current_tuition=s.has_provider_current_tuition,
      has_fee=s.has_provider_current_tuition,
      provider_annual_tuition_amount=s.provider_annual_tuition_amount,
      provider_annual_tuition_currency=s.provider_annual_tuition_currency,
      provider_tuition_options=s.provider_tuition_options,
      official_course_url=s.official_course_url,
      has_link=(s.official_course_url is not null),
      intake_options=s.intake_options,
      earliest_intake_date=s.earliest_intake_date,
      has_intake=(jsonb_array_length(s.intake_options)>0),
      english_requirement_options=s.english_requirement_options,
      has_english=(jsonb_array_length(s.english_requirement_options)>0),
      scholarship_options=s.scholarship_options,
      has_scholarship=(jsonb_array_length(s.scholarship_options)>0),
      enrichment_semantic_text=nullif(trim(s.enrichment_semantic_text),''),
      enrichment_content_hash=s.enrichment_content_hash,
      search_text=concat_ws(' ',d.course_title,d.provider_name,d.course_code,d.study_level_code,d.primary_field_name,array_to_string(d.collection_names,' '),array_to_string(d.academic_option_names,' '),d.description,nullif(trim(s.enrichment_semantic_text),'')),
      search_tsv=setweight(to_tsvector('english',coalesce(d.course_title,'')),'A') || setweight(to_tsvector('english',coalesce(d.provider_name,'')),'B') || setweight(to_tsvector('english',concat_ws(' ',coalesce(d.course_code,''),coalesce(d.study_level_code,''),coalesce(d.primary_field_name,''),coalesce(array_to_string(d.collection_names,' '),''),coalesce(array_to_string(d.academic_option_names,' '),''))),'B') || setweight(to_tsvector('english',concat_ws(' ',coalesce(d.description,''),coalesce(s.enrichment_semantic_text,''))),'C'),
      semantic_content_hash=encode(extensions.digest(jsonb_build_object('base',d.course_stable_key,'provider',d.provider_name,'title',d.course_title,'code',d.course_code,'level',d.study_level_code,'field',d.primary_field_code,'collections',d.collection_names,'academic_options',d.academic_option_names,'description',d.description,'enrichment',nullif(trim(s.enrichment_semantic_text),''))::text,'sha256'),'hex'),
      projection_version='course-v3',
      generated_at=now(),
      updated_at=now()
    from cf_search_enrichment_stage s where d.course_id=s.course_id;
  end if;

  return jsonb_build_object('projection_version','course-v3','scope','courses','requested_courses',coalesce(cardinality(p_course_ids),0),'apply',p_apply,'rows',v_rows,'changed',v_changed,'unchanged',v_unchanged,'stage_hash',v_stage_hash,'coverage',v_coverage);
end
$function$;

CREATE OR REPLACE FUNCTION security.website_sync_check_v1(p_items integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_left int := greatest(coalesce(p_items, 0), 1); e text; r record; v jsonb; h text; it pipeline.website_sync_items%rowtype;
        st pipeline.website_sync_scan%rowtype; v_lim int; v_cnt int; v_w int; v_out jsonb := '{}'::jsonb; v_new int; v_chg int; v_rem int; v_ren int; v_renew interval;
begin
  if not pg_try_advisory_xact_lock(hashtext('website-sync-check')) then return jsonb_build_object('skipped', 'another run is working'); end if;  -- fixed: one run at a time
  v_renew := make_interval(days => greatest(security.pipeline_num_v1('website.logo_link_days', 365) - security.pipeline_num_v1('website.logo_renew_before_days', 30), 1)::int);
  -- a pass walks the entities in order; each run carries on where the last stopped; a new pass starts when all are done
  if not exists (select 1 from pipeline.website_sync_scan where not done) then update pipeline.website_sync_scan set done = false; end if;
  foreach e in array array['reference', 'provider', 'logo', 'rankings', 'scholarship', 'course'] loop
    exit when v_left <= 0;
    select * into st from pipeline.website_sync_scan where entity = e for update;
    continue when st.done;
    v_w := case e when 'reference' then 200 when 'provider' then 8 else 1 end;  -- fixed: build cost relative to a course item, measured 14 Oct 2026
    v_lim := greatest(ceil(v_left::numeric / v_w)::int, 1); v_cnt := 0; v_new := 0; v_chg := 0; v_rem := 0; v_ren := 0;
    for r in select c.item_key, c.ref_id from security.website_sync_candidates_v1(e) c
              where st.after_key is null or c.item_key > st.after_key order by c.item_key limit v_lim loop
      v_cnt := v_cnt + 1; v_left := v_left - v_w;
      v := security.website_sync_item_v1(e, r.ref_id, r.item_key);
      h := case when v is null then null else md5((v - 'generated_at' - 'freshness')::text) end;  -- CF-247 16 Oct 2026: freshness timestamps are not a change
      select * into it from pipeline.website_sync_items where entity = e and item_key = r.item_key;
      if it.item_key is null then
        if v is not null then
          insert into pipeline.website_sync_items(entity, item_key, ref_id, hash, seq, item) values (e, r.item_key, r.ref_id, h, nextval('pipeline.website_sync_seq'), v);
          v_new := v_new + 1;
        end if;
      elsif v is null then
        if it.removed_at is null then
          update pipeline.website_sync_items set removed_at = now(), hash = null, item = null, seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
          v_rem := v_rem + 1;
        end if;
      elsif it.removed_at is not null then
        update pipeline.website_sync_items set removed_at = null, hash = h, item = v, ref_id = r.ref_id, seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
        v_new := v_new + 1;
      elsif it.hash is null then
        update pipeline.website_sync_items set hash = h, item = v, ref_id = r.ref_id where entity = e and item_key = r.item_key;  -- first check: not a change
      elsif it.hash <> h then
        update pipeline.website_sync_items set hash = h, item = v, ref_id = r.ref_id, seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
        v_chg := v_chg + 1;
      elsif e = 'logo' and it.seq_at < now() - v_renew then
        update pipeline.website_sync_items set item = v, seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
        v_ren := v_ren + 1;
      elsif it.item is null then
        update pipeline.website_sync_items set item = v where entity = e and item_key = r.item_key;  -- CF-247 15 Oct 2026: unchanged, stored for sync
      end if;
      st.after_key := r.item_key;
    end loop;
    if v_cnt < v_lim then
      update pipeline.website_sync_scan set after_key = null, done = true, cycles = cycles + 1, last_cycle_at = now(), last_run_at = now(),
             last_result = jsonb_build_object('checked', v_cnt, 'new', v_new, 'changed', v_chg, 'removed', v_rem, 'renewed', v_ren) where entity = e;
    else
      update pipeline.website_sync_scan set after_key = st.after_key, last_run_at = now(),
             last_result = jsonb_build_object('checked', v_cnt, 'new', v_new, 'changed', v_chg, 'removed', v_rem, 'renewed', v_ren) where entity = e;
    end if;
    v_out := v_out || jsonb_build_object(e, jsonb_build_object('checked', v_cnt, 'new', v_new, 'changed', v_chg, 'removed', v_rem, 'renewed', v_ren));
  end loop;
  return v_out;
end $function$;

-- 2 stored hashes recomputed the new way (the stored item is the item the old hash was taken from)
update pipeline.website_sync_items set hash = md5((item - 'generated_at' - 'freshness')::text) where item is not null and removed_at is null;
-- 1 rebuild the projection so Zoho reads the latest year's fee
insert into search.refresh_requests(requested_by) values ('CF-247 16 Oct 2026: provider annual fee is the latest year''s');

do $post$
declare v_expected jsonb := '{"search.refresh_course_enrichment_core_v1(boolean)": "ce80f74549625c23317aba5c737afda6", "search.refresh_course_enrichment_core_scoped_v1(uuid[],boolean)": "3f0b051fdc0e8c34f757f8c21ff5b7d3", "security.website_sync_check_v1(integer)": "f8095625ca8c09526900c78c73a21a91"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'api data fixes post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $post2$
begin
  if exists (select 1 from pipeline.website_sync_items where item is not null and removed_at is null and hash <> md5((item - 'generated_at' - 'freshness')::text)) then
    raise exception 'api data fixes post-check: a stored hash was not recomputed';
  end if;
end $post2$;
