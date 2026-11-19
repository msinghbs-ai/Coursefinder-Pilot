create or replace view public.catalogue_stats as
select
  (select count(*)::bigint from catalogue.courses) as courses,
  (select count(*)::bigint from catalogue.providers) as providers,
  coalesce((select round(avg(completeness_score),1) from search.course_documents where completeness_score is not null),0)::numeric as avg_completeness
where auth.uid() is not null;

create or replace view public.providers as
select p.id,p.canonical_name,c.iso_alpha2 as country_code,p.primary_city as city,p.website,p.lifecycle_status as lifecycle,p.publication_status as publication,p.updated_at
from catalogue.providers p join ref.countries c on c.id=p.country_id
where auth.uid() is not null;

create or replace view public.course_completeness_v2 as
select c.id as course_id,c.canonical_title,coalesce(p.display_name,p.canonical_name) as provider_name,sl.code as level_code,fos.name as field_of_study,
       f.amount as fee_amount,f.currency_code as fee_currency,e.overall_score as ielts_overall,
       coalesce(d.has_scholarship,false) as has_scholarship,
       case when coalesce(d.has_scholarship,false) then 'linked' else 'unknown' end as scholarship_status,
       (select count(*)::int from scholarship.scopes ss where ss.course_id=c.id or (ss.scope_type='provider' and ss.provider_id=c.provider_id)) as scholarship_count,
       exists(select 1 from catalogue.course_registrations r where r.course_id=c.id) as has_registration,
       (c.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=c.id)) as has_structure,
       coalesce(d.has_fee,false) as has_fee,coalesce(d.has_intake,false) as has_intake,coalesce(d.has_english,false) as has_english,(c.description is not null and length(trim(c.description))>0) as has_description,
       coalesce(d.completeness_score,0)::numeric as completeness_score_v2,
       coalesce(d.completeness_score,0)::numeric as completeness_score
from catalogue.courses c join catalogue.providers p on p.id=c.provider_id
left join ref.study_levels sl on sl.id=c.study_level_id
left join ref.fields_of_study fos on fos.id=c.primary_field_id
left join search.course_documents d on d.course_id=c.id
left join lateral (select cf.amount,cf.currency_code from catalogue.course_fees cf where cf.course_id=c.id order by cf.fee_year desc nulls last,cf.created_at desc limit 1) f on true
left join lateral (select er.overall_score from catalogue.course_english_requirements er join ref.english_tests t on t.id=er.english_test_id where er.course_id=c.id and t.code='IELTS' limit 1) e on true
where auth.uid() is not null;

create or replace view public.scholarship_catalogue_v2 as
select s.id,s.stable_key,s.name as canonical_name,coalesce(p.display_name,p.canonical_name) as provider_name,s.academic_year,s.scholarship_type,s.audience,s.award_value_text,s.application_required,s.application_open_date,s.application_close_date,s.publication_status as publication,s.lifecycle_status as lifecycle,s.updated_at
from scholarship.scholarships s left join catalogue.providers p on p.id=s.provider_id
where auth.uid() is not null;

create or replace view public.ingest_jobs as
select j.id,
       case when j.job_type ilike '%layer1%' then 1 when j.job_type ilike '%layer2%' then 2 when j.job_type ilike '%layer3%' then 3 when j.job_type ilike '%layer4%' then 4 else null end as layer,
       j.job_type as job_kind,c.iso_alpha2 as country_code,j.status,j.created_at,j.started_at,j.completed_at,
       coalesce(j.result,'{}'::jsonb) as counters,j.error_text as error_message
from pipeline.jobs j left join catalogue.providers p on p.id=j.provider_id left join ref.countries c on c.id=p.country_id
where auth.uid() is not null;

create or replace view public.review_queue as
select r.id,r.entity_id,r.status,
       case when pc.layer is null then null else pc.layer end as source_layer,
       r.domain as review_type,r.field_code,r.priority,r.previous_review_id,r.reopen_reason,r.created_at,r.updated_at,r.closed_at
from workflow.review_queue r left join pipeline.claims pc on pc.id=r.candidate_claim_id
where auth.uid() is not null;

create or replace view public.evidence_artifacts as
select e.id,e.entity_id,e.evidence_type,e.source_url,e.storage_path,e.content_hash,e.mime_type,e.captured_at,e.supersedes_evidence_id,e.metadata,e.created_at
from pipeline.evidence_artifacts e where auth.uid() is not null;

create or replace view public.pim_attribute_definitions as
select a.id,a.code,a.name,a.entity_type,a.data_type,a.validation_rules,a.is_required_default,a.is_unique,a.is_filterable,a.is_searchable,a.include_in_vector,a.vector_weight,a.is_localisable,a.is_channel_scoped,a.is_multivalue,a.is_bulk_editable,a.display_order,a.status,a.created_at,a.updated_at,g.name as group_name
from pim.attribute_definitions a left join pim.attribute_groups g on g.id=a.group_id
where auth.uid() is not null;

create or replace view public.field_values as
select v.id,v.entity_id,v.attribute_id,v.value_text,v.value_number,v.value_boolean,v.value_date,v.value_datetime,v.value_code,v.value_json,v.confidence,v.review_status,v.created_at,v.updated_at
from pim.attribute_values v where auth.uid() is not null;

grant select on public.catalogue_stats,public.providers,public.course_completeness_v2,public.scholarship_catalogue_v2,public.ingest_jobs,public.review_queue,public.evidence_artifacts,public.pim_attribute_definitions,public.field_values to authenticated;
revoke all on public.catalogue_stats,public.providers,public.course_completeness_v2,public.scholarship_catalogue_v2,public.ingest_jobs,public.review_queue,public.evidence_artifacts,public.pim_attribute_definitions,public.field_values from anon;
