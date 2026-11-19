create or replace function public.ui_course_completeness_list(p_limit int default 2000)
returns table(course_id uuid,canonical_title text,provider_name text,level_code text,field_of_study text,fee_amount numeric,fee_currency char(3),ielts_overall numeric,has_scholarship boolean,scholarship_status text,scholarship_count int,has_registration boolean,has_structure boolean,has_fee boolean,has_intake boolean,has_english boolean,has_description boolean,completeness_score_v2 numeric,completeness_score numeric)
language sql
stable
security definer
set search_path=public,catalogue,ref,search,scholarship,auth
as $$
select c.id,c.canonical_title,coalesce(p.display_name,p.canonical_name),sl.code,fos.name,
       f.amount,f.currency_code,e.overall_score,
       coalesce(d.has_scholarship,false),
       case when coalesce(d.has_scholarship,false) then 'linked' else 'unknown' end,
       (select count(*)::int from scholarship.scopes ss where ss.course_id=c.id or (ss.scope_type='provider' and ss.provider_id=c.provider_id)),
       exists(select 1 from catalogue.course_registrations r where r.course_id=c.id),
       (c.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=c.id)),
       coalesce(d.has_fee,false),coalesce(d.has_intake,false),coalesce(d.has_english,false),(c.description is not null and length(trim(c.description))>0),
       coalesce(d.completeness_score,0)::numeric,coalesce(d.completeness_score,0)::numeric
from catalogue.courses c join catalogue.providers p on p.id=c.provider_id
left join ref.study_levels sl on sl.id=c.study_level_id
left join ref.fields_of_study fos on fos.id=c.primary_field_id
left join search.course_documents d on d.course_id=c.id
left join lateral (select cf.amount,cf.currency_code from catalogue.course_fees cf where cf.course_id=c.id order by cf.fee_year desc nulls last,cf.created_at desc limit 1) f on true
left join lateral (select er.overall_score from catalogue.course_english_requirements er join ref.english_tests t on t.id=er.english_test_id where er.course_id=c.id and t.code='IELTS' limit 1) e on true
where auth.uid() is not null
order by coalesce(p.display_name,p.canonical_name),c.canonical_title
limit least(greatest(coalesce(p_limit,2000),1),5000)
$$;

create or replace function public.ui_evidence_list(p_limit int default 1000)
returns table(id uuid,entity_id uuid,evidence_type text,source_url text,storage_path text,content_hash text,mime_type text,captured_at timestamptz,supersedes_evidence_id uuid,metadata jsonb,created_at timestamptz)
language sql stable security definer
set search_path=public,pipeline,auth
as $$
select e.id,e.entity_id,e.evidence_type,e.source_url,e.storage_path,e.content_hash,e.mime_type,e.captured_at,e.supersedes_evidence_id,e.metadata,e.created_at
from pipeline.evidence_artifacts e where auth.uid() is not null order by e.captured_at desc limit least(greatest(coalesce(p_limit,1000),1),5000)
$$;

create or replace function public.ui_field_values_list(p_limit int default 2000)
returns table(id uuid,entity_id uuid,attribute_id uuid,value_text text,value_number numeric,value_boolean boolean,value_date date,value_datetime timestamptz,value_code text,value_json jsonb,confidence numeric,review_status text,created_at timestamptz,updated_at timestamptz)
language sql stable security definer
set search_path=public,pim,auth
as $$
select v.id,v.entity_id,v.attribute_id,v.value_text,v.value_number,v.value_boolean,v.value_date,v.value_datetime,v.value_code,v.value_json,v.confidence,v.review_status,v.created_at,v.updated_at
from pim.attribute_values v where auth.uid() is not null order by v.updated_at desc limit least(greatest(coalesce(p_limit,2000),1),5000)
$$;

revoke all on function public.ui_course_completeness_list(integer) from public,anon;
revoke all on function public.ui_evidence_list(integer) from public,anon;
revoke all on function public.ui_field_values_list(integer) from public,anon;
grant execute on function public.ui_course_completeness_list(integer) to authenticated,service_role;
grant execute on function public.ui_evidence_list(integer) to authenticated,service_role;
grant execute on function public.ui_field_values_list(integer) to authenticated,service_role;

drop view if exists public.catalogue_stats;
drop view if exists public.providers;
drop view if exists public.course_completeness_v2;
drop view if exists public.scholarship_catalogue_v2;
drop view if exists public.ingest_jobs;
drop view if exists public.review_queue;
drop view if exists public.evidence_artifacts;
drop view if exists public.pim_attribute_definitions;
drop view if exists public.field_values;

create view public.catalogue_stats with (security_invoker=true) as
select
  (d->>'courses')::bigint as courses,
  (d->>'providers')::bigint as providers,
  0::numeric as avg_completeness
from (select public.ui_dashboard() d) x;

create view public.providers with (security_invoker=true) as
select id,canonical_name,country_code,city,website,lifecycle_status as lifecycle,publication_status as publication,null::timestamptz as updated_at
from public.ui_providers_list(1000);

create view public.course_completeness_v2 with (security_invoker=true) as
select * from public.ui_course_completeness_list(5000);

create view public.scholarship_catalogue_v2 with (security_invoker=true) as
select id,stable_key,name as canonical_name,provider_name,academic_year,scholarship_type,audience,award_value_text,
       null::boolean as application_required,null::date as application_open_date,null::date as application_close_date,
       publication_status as publication,'active'::text as lifecycle,null::timestamptz as updated_at
from public.ui_scholarships_list(1000);

create view public.ingest_jobs with (security_invoker=true) as
select id,null::int as layer,job_type as job_kind,null::char(2) as country_code,status,created_at,started_at,completed_at,'{}'::jsonb as counters,error_text as error_message
from public.ui_jobs_list(1000);

create view public.review_queue with (security_invoker=true) as
select id,entity_id,status,null::int as source_layer,domain as review_type,field_code,priority,previous_review_id,reopen_reason,created_at,updated_at,null::timestamptz as closed_at
from public.ui_review_queue(1000);

create view public.evidence_artifacts with (security_invoker=true) as
select * from public.ui_evidence_list(5000);

create view public.pim_attribute_definitions with (security_invoker=true) as
select id,code,name,entity_type,data_type,'{}'::jsonb as validation_rules,false as is_required_default,false as is_unique,is_filterable,is_searchable,include_in_vector,1::numeric as vector_weight,false as is_localisable,false as is_channel_scoped,false as is_multivalue,is_bulk_editable,0::int as display_order,status,null::timestamptz as created_at,null::timestamptz as updated_at,group_name
from public.ui_attributes_list();

create view public.field_values with (security_invoker=true) as
select * from public.ui_field_values_list(5000);

grant select on public.catalogue_stats,public.providers,public.course_completeness_v2,public.scholarship_catalogue_v2,public.ingest_jobs,public.review_queue,public.evidence_artifacts,public.pim_attribute_definitions,public.field_values to authenticated;
revoke all on public.catalogue_stats,public.providers,public.course_completeness_v2,public.scholarship_catalogue_v2,public.ingest_jobs,public.review_queue,public.evidence_artifacts,public.pim_attribute_definitions,public.field_values from anon;
