create table if not exists search.enrichment_source_gates (
  projection_code text not null,
  domain_code text not null,
  source_id uuid not null references pipeline.sources(id),
  gate_status text not null check (gate_status in ('approved','blocked')),
  approval_ref text not null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (projection_code,domain_code,source_id)
);
revoke all on search.enrichment_source_gates from public, anon, authenticated;
grant select,insert,update,delete on search.enrichment_source_gates to service_role;

insert into search.enrichment_gates(projection_code,domain_code,gate_status,approval_ref,approved_at)
values
 ('courses','regulatory_tuition','approved','CF-CHG-20260823-023: CRICOS regulatory tuition semantic split',now()),
 ('courses','provider_current_tuition','approved','CF-CHG-20260823-023: bounded RMIT/UQ Course Facts admission',now()),
 ('courses','official_course_url','approved','CF-CHG-20260823-023: bounded RMIT/UQ Course Facts admission',now()),
 ('courses','course_intake','approved','CF-CHG-20260823-023: bounded RMIT/UQ Course Facts admission',now()),
 ('courses','course_english','approved','CF-CHG-20260823-023: bounded RMIT/UQ Course Facts admission',now()),
 ('courses','qilt','blocked','CF-CHG-20260823-023: no accepted Course-grain observations; provider/outcome grain not coerced',null),
 ('courses','prisms','blocked','CF-CHG-20260823-023: no accepted Course-grain observations; flow grain not coerced',null)
on conflict (projection_code,domain_code) do update set
 gate_status=excluded.gate_status, approval_ref=excluded.approval_ref, approved_at=excluded.approved_at, updated_at=now();

update search.enrichment_gates
set gate_status='blocked', approval_ref='CF-CHG-20260823-023: legacy ambiguous course_fee gate superseded by regulatory_tuition/provider_current_tuition split', approved_at=null, updated_at=now()
where projection_code='courses' and domain_code='course_fee';

insert into search.enrichment_source_gates(projection_code,domain_code,source_id,gate_status,approval_ref,approved_at)
select 'courses',d.domain_code,q.source_id,'approved','CF-CHG-20260823-023; source qualification '||q.source_key,now()
from pipeline.course_fact_source_qualifications q
cross join (values ('provider_current_tuition'),('official_course_url'),('course_intake'),('course_english')) d(domain_code)
where q.qualification_status='qualified'
  and q.source_key in ('au_rmit_official_course_pages','au_uq_official_program_pages')
  and case d.domain_code
    when 'provider_current_tuition' then 'international_fee'=any(q.admitted_domains)
    when 'official_course_url' then 'official_course_url'=any(q.admitted_domains)
    when 'course_intake' then 'intake'=any(q.admitted_domains)
    when 'course_english' then 'english_requirement'=any(q.admitted_domains)
    else false end
on conflict (projection_code,domain_code,source_id) do update set
 gate_status=excluded.gate_status,approval_ref=excluded.approval_ref,approved_at=excluded.approved_at,updated_at=now();

alter table search.course_documents
  add column if not exists regulatory_tuition_state text,
  add column if not exists has_regulatory_tuition boolean not null default false,
  add column if not exists regulatory_tuition_amount numeric,
  add column if not exists regulatory_tuition_currency char(3),
  add column if not exists regulatory_tuition_basis text,
  add column if not exists has_provider_current_tuition boolean not null default false,
  add column if not exists provider_annual_tuition_amount numeric,
  add column if not exists provider_annual_tuition_currency char(3),
  add column if not exists provider_tuition_options jsonb not null default '[]'::jsonb,
  add column if not exists official_course_url text,
  add column if not exists intake_options jsonb not null default '[]'::jsonb,
  add column if not exists earliest_intake_date date,
  add column if not exists english_requirement_options jsonb not null default '[]'::jsonb,
  add column if not exists scholarship_options jsonb not null default '[]'::jsonb,
  add column if not exists enrichment_semantic_text text,
  add column if not exists enrichment_content_hash text;

create index if not exists course_documents_reg_tuition_idx on search.course_documents(country_code,regulatory_tuition_amount) where regulatory_tuition_state in ('present','zero');
create index if not exists course_documents_provider_annual_tuition_idx on search.course_documents(provider_annual_tuition_amount) where provider_annual_tuition_amount is not null;
create index if not exists course_documents_earliest_intake_idx on search.course_documents(earliest_intake_date) where earliest_intake_date is not null;
create index if not exists course_documents_provider_tuition_flag_idx on search.course_documents(has_provider_current_tuition);

create or replace function search.refresh_course_enrichment_v1(p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path=search,catalogue,scholarship,pipeline,ref,extensions,pg_temp
as $function$
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
    case when d.country_code='NZ' then 'not_applicable'
      when not (select regulatory_ok from global_gates) then 'not_admitted'
      when rf.fee_id is null then 'source_null'
      when rf.amount=0 then 'zero' else 'present' end as regulatory_tuition_state,
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
    concat_ws(' ',case when (select intake_ok from global_gates) then it.semantic_text end,case when (select english_ok from global_gates) then en.semantic_text end,case when (select scholarship_ok from global_gates) then sc.semantic_text end) as enrichment_semantic_text
  from search.course_documents d
  left join lateral (
    select f.id fee_id,f.amount,f.currency_code,f.basis
    from catalogue.course_fees f join pipeline.sources s on s.id=f.source_id
    where f.course_id=d.course_id and f.status='active' and f.audience in ('international','all') and f.fee_type='tuition' and f.basis='registered_total_course' and s.label='CRICOS Providers, Courses and Locations'
    order by f.updated_at desc nulls last,f.id limit 1
  ) rf on true
  left join lateral (
    select count(*) option_count,min(f.amount) filter(where f.basis in ('annual','indicative_annual')) annual_amount,min(f.currency_code) filter(where f.basis in ('annual','indicative_annual')) annual_currency,
      jsonb_agg(jsonb_build_object('fee_year',f.fee_year,'amount',f.amount,'currency',trim(f.currency_code),'basis',f.basis,'load_basis',f.load_basis,'campus_id',f.campus_id,'valid_from',f.valid_from,'valid_to',f.valid_to,'last_verified_at',f.last_verified_at) order by f.fee_year desc nulls last,f.basis,f.amount,f.id) options
    from catalogue.course_fees f join search.enrichment_source_gates sg on sg.projection_code='courses' and sg.domain_code='provider_current_tuition' and sg.source_id=f.source_id and sg.gate_status='approved'
    where f.course_id=d.course_id and f.status='active' and f.audience in ('international','all') and f.fee_type='provider_current_tuition' and (f.valid_from is null or f.valid_from<=current_date) and (f.valid_to is null or f.valid_to>=current_date)
  ) pf on true
  left join lateral (
    select l.url from catalogue.course_links l join search.enrichment_source_gates sg on sg.projection_code='courses' and sg.domain_code='official_course_url' and sg.source_id=l.source_id and sg.gate_status='approved'
    where l.course_id=d.course_id and l.status='active' and (l.valid_from is null or l.valid_from<=current_date) and (l.valid_to is null or l.valid_to>=current_date)
    order by l.is_primary desc,l.last_verified_at desc nulls last,l.updated_at desc nulls last,l.id limit 1
  ) lk on true
  left join lateral (
    select jsonb_agg(jsonb_build_object('year',i.intake_year,'label',i.intake_label,'start_date',i.start_date,'application_deadline',i.application_deadline,'campus_id',i.campus_id) order by i.start_date nulls last,i.intake_year,i.intake_label,i.id) options,
      min(i.start_date) filter(where i.start_date>=current_date) earliest_date,string_agg(distinct concat_ws(' ',i.intake_year::text,i.intake_label),' ' order by concat_ws(' ',i.intake_year::text,i.intake_label)) semantic_text
    from catalogue.course_intakes i join search.enrichment_source_gates sg on sg.projection_code='courses' and sg.domain_code='course_intake' and sg.source_id=i.source_id and sg.gate_status='approved'
    where i.course_id=d.course_id and i.status='active'
  ) it on true
  left join lateral (
    select jsonb_agg(jsonb_build_object('test_code',t.code,'test_name',t.name,'overall_score',er.overall_score,'component_scores',er.component_scores,'notes',er.notes,'valid_from',er.valid_from,'valid_to',er.valid_to,'last_verified_at',er.last_verified_at) order by t.code,er.overall_score,er.id) options,
      string_agg(distinct concat_ws(' ',t.name,t.code,er.overall_score::text),' ' order by concat_ws(' ',t.name,t.code,er.overall_score::text)) semantic_text
    from catalogue.course_english_requirements er join ref.english_tests t on t.id=er.english_test_id join search.enrichment_source_gates sg on sg.projection_code='courses' and sg.domain_code='course_english' and sg.source_id=er.source_id and sg.gate_status='approved'
    where er.course_id=d.course_id and er.status='active' and (er.valid_from is null or er.valid_from<=current_date) and (er.valid_to is null or er.valid_to>=current_date)
  ) en on true
  left join lateral (
    select jsonb_agg(distinct jsonb_build_object('scholarship_key',s.stable_key,'name',s.name,'award_value_text',s.award_value_text,'academic_year',s.academic_year,'application_close_date',s.application_close_date,'source_url',s.source_url)) options,string_agg(distinct s.name,' ' order by s.name) semantic_text
    from scholarship.scopes ss join scholarship.scholarships s on s.id=ss.scholarship_id
    where s.lifecycle_status='active' and s.publication_status in ('published','internal') and coalesce(ss.include_exclude,'include')='include' and ((ss.scope_type='course' and ss.course_id=d.course_id) or (ss.scope_type='provider' and ss.provider_id=d.provider_id))
  ) sc on true;

  alter table cf_search_enrichment_stage add column enrichment_content_hash text;
  update cf_search_enrichment_stage s set enrichment_content_hash=encode(extensions.digest(jsonb_build_object('regulatory_state',s.regulatory_tuition_state,'regulatory_amount',s.regulatory_tuition_amount,'regulatory_currency',s.regulatory_tuition_currency,'regulatory_basis',s.regulatory_tuition_basis,'has_provider_current_tuition',s.has_provider_current_tuition,'provider_annual_amount',s.provider_annual_tuition_amount,'provider_annual_currency',s.provider_annual_tuition_currency,'provider_options',s.provider_tuition_options,'official_url',s.official_course_url,'intakes',s.intake_options,'english',s.english_requirement_options,'scholarships',s.scholarship_options,'semantic_text',s.enrichment_semantic_text)::text,'sha256'),'hex');

  select count(*) into v_rows from cf_search_enrichment_stage;
  select count(*) into v_changed from cf_search_enrichment_stage s join search.course_documents d using(course_id) where d.enrichment_content_hash is distinct from s.enrichment_content_hash;
  select count(*) into v_unchanged from cf_search_enrichment_stage s join search.course_documents d using(course_id) where d.enrichment_content_hash is not distinct from s.enrichment_content_hash;
  select encode(extensions.digest(coalesce(string_agg(course_id::text||':'||enrichment_content_hash,'|' order by course_id::text),''),'sha256'),'hex') into v_stage_hash from cf_search_enrichment_stage;
  select jsonb_build_object('regulatory_present',count(*) filter(where regulatory_tuition_state='present'),'regulatory_zero',count(*) filter(where regulatory_tuition_state='zero'),'regulatory_source_null',count(*) filter(where regulatory_tuition_state='source_null'),'regulatory_not_applicable',count(*) filter(where regulatory_tuition_state='not_applicable'),'with_provider_current_tuition',count(*) filter(where has_provider_current_tuition),'with_provider_annual_tuition',count(*) filter(where provider_annual_tuition_amount is not null),'with_official_url',count(*) filter(where official_course_url is not null),'with_intake',count(*) filter(where jsonb_array_length(intake_options)>0),'with_english',count(*) filter(where jsonb_array_length(english_requirement_options)>0),'with_scholarship',count(*) filter(where jsonb_array_length(scholarship_options)>0)) into v_coverage from cf_search_enrichment_stage;

  if p_apply then
    update search.course_documents d set regulatory_tuition_state=s.regulatory_tuition_state,has_regulatory_tuition=s.has_regulatory_tuition,regulatory_tuition_amount=s.regulatory_tuition_amount,regulatory_tuition_currency=s.regulatory_tuition_currency,regulatory_tuition_basis=s.regulatory_tuition_basis,has_provider_current_tuition=s.has_provider_current_tuition,has_fee=s.has_provider_current_tuition,provider_annual_tuition_amount=s.provider_annual_tuition_amount,provider_annual_tuition_currency=s.provider_annual_tuition_currency,provider_tuition_options=s.provider_tuition_options,official_course_url=s.official_course_url,has_link=(s.official_course_url is not null),intake_options=s.intake_options,earliest_intake_date=s.earliest_intake_date,has_intake=(jsonb_array_length(s.intake_options)>0),english_requirement_options=s.english_requirement_options,has_english=(jsonb_array_length(s.english_requirement_options)>0),scholarship_options=s.scholarship_options,has_scholarship=(jsonb_array_length(s.scholarship_options)>0),enrichment_semantic_text=nullif(trim(s.enrichment_semantic_text),''),enrichment_content_hash=s.enrichment_content_hash,
      search_text=concat_ws(' ',d.course_title,d.provider_name,d.course_code,d.study_level_code,d.primary_field_name,array_to_string(d.collection_names,' '),array_to_string(d.academic_option_names,' '),d.description,nullif(trim(s.enrichment_semantic_text),'')),
      search_tsv=setweight(to_tsvector('english',coalesce(d.course_title,'')),'A') || setweight(to_tsvector('english',coalesce(d.provider_name,'')),'B') || setweight(to_tsvector('english',concat_ws(' ',coalesce(d.course_code,''),coalesce(d.study_level_code,''),coalesce(d.primary_field_name,''),coalesce(array_to_string(d.collection_names,' '),''),coalesce(array_to_string(d.academic_option_names,' '),''))),'B') || setweight(to_tsvector('english',concat_ws(' ',coalesce(d.description,''),coalesce(s.enrichment_semantic_text,''))),'C'),
      semantic_content_hash=encode(extensions.digest(jsonb_build_object('base',d.course_stable_key,'provider',d.provider_name,'title',d.course_title,'code',d.course_code,'level',d.study_level_code,'field',d.primary_field_code,'collections',d.collection_names,'academic_options',d.academic_option_names,'description',d.description,'enrichment',nullif(trim(s.enrichment_semantic_text),''))::text,'sha256'),'hex'),projection_version='course-v3',generated_at=now(),updated_at=now()
    from cf_search_enrichment_stage s where d.course_id=s.course_id;
  end if;
  return jsonb_build_object('projection_version','course-v3','apply',p_apply,'rows',v_rows,'changed',v_changed,'unchanged',v_unchanged,'stage_hash',v_stage_hash,'coverage',v_coverage);
end
$function$;
revoke all on function search.refresh_course_enrichment_v1(boolean) from public,anon,authenticated;
grant execute on function search.refresh_course_enrichment_v1(boolean) to service_role;

create or replace function search.refresh_course_documents_v3(p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path=search,pg_temp as $function$
declare v_base jsonb; v_enrichment jsonb;
begin v_base:=search.refresh_course_documents_v2(p_apply); v_enrichment:=search.refresh_course_enrichment_v1(p_apply); return jsonb_build_object('base',v_base,'enrichment',v_enrichment); end
$function$;
revoke all on function search.refresh_course_documents_v3(boolean) from public,anon,authenticated;
grant execute on function search.refresh_course_documents_v3(boolean) to service_role;

create or replace function api.website_course_search_v2(
  p_query text default null,p_country_codes text[] default null,p_subdivision_codes text[] default null,p_level_codes text[] default null,p_field_codes text[] default null,p_delivery_modes text[] default null,p_has_provider_tuition boolean default null,p_provider_annual_tuition_max numeric default null,p_has_intake boolean default null,p_has_english boolean default null,p_has_scholarship boolean default null,p_sort text default 'relevance',p_limit integer default 20,p_offset integer default 0
) returns jsonb language sql stable security definer set search_path=api,search as $function$
with params as (select greatest(1,least(coalesce(p_limit,20),50)) lim,greatest(coalesce(p_offset,0),0) off,websearch_to_tsquery('english',coalesce(nullif(trim(p_query),''),'')) tsq,case when p_sort in ('relevance','title','regulatory_tuition_asc','regulatory_tuition_desc','provider_annual_tuition_asc','provider_annual_tuition_desc','earliest_intake') then p_sort else 'relevance' end sort_code), ranked as (
 select d.*,case when coalesce(trim(p_query),'')='' then 0::real else ts_rank_cd(d.search_tsv,(select tsq from params))::real end score from search.course_documents d
 where d.publication_status='published' and (p_country_codes is null or d.country_code=any(p_country_codes)) and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes) and (p_level_codes is null or d.study_level_code=any(p_level_codes)) and (p_field_codes is null or d.primary_field_code=any(p_field_codes)) and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes) and (p_has_provider_tuition is null or d.has_provider_current_tuition=p_has_provider_tuition) and (p_provider_annual_tuition_max is null or d.provider_annual_tuition_amount<=p_provider_annual_tuition_max) and (p_has_intake is null or d.has_intake=p_has_intake) and (p_has_english is null or d.has_english=p_has_english) and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship) and (coalesce(trim(p_query),'')='' or d.search_tsv @@ (select tsq from params))
), paged as (
 select * from ranked order by case when (select sort_code from params)='relevance' then score end desc,case when (select sort_code from params)='title' then course_title end asc,case when (select sort_code from params)='regulatory_tuition_asc' then regulatory_tuition_amount end asc nulls last,case when (select sort_code from params)='regulatory_tuition_desc' then regulatory_tuition_amount end desc nulls last,case when (select sort_code from params)='provider_annual_tuition_asc' then provider_annual_tuition_amount end asc nulls last,case when (select sort_code from params)='provider_annual_tuition_desc' then provider_annual_tuition_amount end desc nulls last,case when (select sort_code from params)='earliest_intake' then earliest_intake_date end asc nulls last,course_title,course_stable_key limit (select lim from params) offset (select off from params)
)
select jsonb_build_object('contract_version','website-course-search-v2','meta',jsonb_build_object('mode','keyword','limit',(select lim from params),'offset',(select off from params),'projection_version','course-v3','sort',(select sort_code from params)),'items',coalesce(jsonb_agg(jsonb_build_object('course_key',course_stable_key,'title',course_title,'course_code',course_code,'provider',jsonb_build_object('provider_key',provider_stable_key,'name',provider_name),'country',country_code,'study_level',study_level_code,'field',case when primary_field_code is null then null else jsonb_build_object('code',primary_field_code,'name',primary_field_name) end,'states',to_jsonb(subdivision_codes),'delivery_modes',to_jsonb(delivery_modes),'regulatory_tuition',jsonb_build_object('state',regulatory_tuition_state,'amount',regulatory_tuition_amount,'currency',trim(regulatory_tuition_currency),'basis',regulatory_tuition_basis),'provider_current_tuition',jsonb_build_object('has_value',has_provider_current_tuition,'annual_amount',provider_annual_tuition_amount,'annual_currency',trim(provider_annual_tuition_currency),'options',provider_tuition_options),'official_course_url',official_course_url,'intakes',intake_options,'english_requirements',english_requirement_options,'scholarships',scholarship_options,'readiness',jsonb_build_object('has_state',has_state,'has_official_url',has_link,'has_provider_current_tuition',has_provider_current_tuition,'has_intake',has_intake,'has_english',has_english,'has_scholarship',has_scholarship),'match',jsonb_build_object('keyword_score',score)) order by case when (select sort_code from params)='relevance' then score end desc,case when (select sort_code from params)='title' then course_title end asc,case when (select sort_code from params)='regulatory_tuition_asc' then regulatory_tuition_amount end asc nulls last,case when (select sort_code from params)='regulatory_tuition_desc' then regulatory_tuition_amount end desc nulls last,case when (select sort_code from params)='provider_annual_tuition_asc' then provider_annual_tuition_amount end asc nulls last,case when (select sort_code from params)='provider_annual_tuition_desc' then provider_annual_tuition_amount end desc nulls last,case when (select sort_code from params)='earliest_intake' then earliest_intake_date end asc nulls last,course_title,course_stable_key),'[]'::jsonb)) from paged
$function$;
revoke all on function api.website_course_search_v2(text,text[],text[],text[],text[],text[],boolean,numeric,boolean,boolean,boolean,text,integer,integer) from public,anon,authenticated;
grant execute on function api.website_course_search_v2(text,text[],text[],text[],text[],text[],boolean,numeric,boolean,boolean,boolean,text,integer,integer) to service_role;
