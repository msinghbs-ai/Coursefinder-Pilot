-- CF-CHG-20260904-149
-- Official QILT SES 2023 bounded reconciliation for the meeting comparison trio.
-- Preserves source/cohort/year grain; no Search/Publication/Zoho authority change.
begin;

with src as (
  select source_id
  from pipeline.evidence_artifacts
  where metadata->>'survey_code'='qilt_ses' and source_id is not null
  order by captured_at desc
  limit 1
), ins as (
  insert into pipeline.evidence_artifacts(
    source_id,evidence_type,source_url,mime_type,metadata,retention_class,review_state
  )
  select source_id,
         'qilt_public_report_reference',
         'https://www.qilt.edu.au/docs/default-source/default-document-library/2023-ses-national-report.pdf?sfvrsn=9ef8c86_2',
         'application/pdf',
         jsonb_build_object(
           'layer','1-statistics','publisher','QILT','survey_code','qilt_ses',
           'collection_version',2023,'identity_authority',false,
           'source_grain','institution x cohort x metric x collection year',
           'note','Bounded 2023 institution reconciliation from official QILT SES National Report tables; full workbook backfill remains separately operable.'
         ),
         'governed','verified_source_reference'
  from src
  where not exists (
    select 1 from pipeline.evidence_artifacts e
    where e.evidence_type='qilt_public_report_reference'
      and e.metadata->>'survey_code'='qilt_ses'
      and e.metadata->>'collection_version'='2023'
      and e.source_url like '%2023-ses-national-report%'
  )
  returning id
), ev as (
  select id from ins
  union all
  select e.id from pipeline.evidence_artifacts e
  where e.evidence_type='qilt_public_report_reference'
    and e.metadata->>'survey_code'='qilt_ses'
    and e.metadata->>'collection_version'='2023'
    and e.source_url like '%2023-ses-national-report%'
  order by id limit 1
), srcid as (
  select source_id from pipeline.evidence_artifacts
  where metadata->>'survey_code'='qilt_ses' and source_id is not null
  order by captured_at desc limit 1
), vals(provider_name,cohort,metric_code,metric_value,ci_low,ci_high,national_benchmark) as (
  values
  ('Monash University','UG','skills_development',80.6,80.1,81.1,80.8),
  ('Monash University','UG','peer_engagement',67.7,67.1,68.3,57.9),
  ('Monash University','UG','teaching_quality_engagement',78.7,78.2,79.3,80.4),
  ('Monash University','UG','student_support_services',66.9,66.1,67.6,70.6),
  ('Monash University','UG','learning_resources',84.5,84.1,85.0,84.3),
  ('Monash University','UG','overall_educational_experience',73.1,72.6,73.7,76.5),
  ('RMIT University (RMIT)','UG','skills_development',80.8,80.0,81.7,80.8),
  ('RMIT University (RMIT)','UG','peer_engagement',64.7,63.7,65.7,57.9),
  ('RMIT University (RMIT)','UG','teaching_quality_engagement',79.1,78.2,80.0,80.4),
  ('RMIT University (RMIT)','UG','student_support_services',70.5,69.2,71.6,70.6),
  ('RMIT University (RMIT)','UG','learning_resources',84.5,83.7,85.3,84.3),
  ('RMIT University (RMIT)','UG','overall_educational_experience',73.9,73.0,74.8,76.5),
  ('La Trobe University','UG','skills_development',79.7,79.0,80.5,80.8),
  ('La Trobe University','UG','peer_engagement',55.3,54.4,56.2,57.9),
  ('La Trobe University','UG','teaching_quality_engagement',78.5,77.7,79.2,80.4),
  ('La Trobe University','UG','student_support_services',68.5,67.3,69.5,70.6),
  ('La Trobe University','UG','learning_resources',81.8,81.0,82.6,84.3),
  ('La Trobe University','UG','overall_educational_experience',73.8,73.0,74.6,76.5),
  ('Monash University','PGC','skills_development',82.6,81.9,83.4,82.2),
  ('Monash University','PGC','peer_engagement',56.7,55.7,57.6,56.2),
  ('Monash University','PGC','teaching_quality_engagement',82.9,82.2,83.7,82.5),
  ('Monash University','PGC','student_support_services',74.1,72.9,75.2,74.8),
  ('Monash University','PGC','learning_resources',86.3,85.4,87.1,85.3),
  ('Monash University','PGC','overall_educational_experience',75.6,74.7,76.4,76.7),
  ('RMIT University (RMIT)','PGC','skills_development',83.9,82.7,85.1,82.2),
  ('RMIT University (RMIT)','PGC','peer_engagement',58.7,57.2,60.3,56.2),
  ('RMIT University (RMIT)','PGC','teaching_quality_engagement',84.5,83.3,85.6,82.5),
  ('RMIT University (RMIT)','PGC','student_support_services',75.6,73.8,77.3,74.8),
  ('RMIT University (RMIT)','PGC','learning_resources',85.9,84.5,87.1,85.3),
  ('RMIT University (RMIT)','PGC','overall_educational_experience',77.9,76.5,79.2,76.7),
  ('La Trobe University','PGC','skills_development',81.5,80.4,82.5,82.2),
  ('La Trobe University','PGC','peer_engagement',45.5,44.2,46.8,56.2),
  ('La Trobe University','PGC','teaching_quality_engagement',83.5,82.5,84.4,82.5),
  ('La Trobe University','PGC','student_support_services',78.3,76.8,79.8,74.8),
  ('La Trobe University','PGC','learning_resources',87.7,86.5,88.9,85.3),
  ('La Trobe University','PGC','overall_educational_experience',78.2,77.1,79.2,76.7)
), resolved as (
  select p.id provider_id,os.id survey_id,om.id metric_id,v.*
  from vals v
  join catalogue.providers p on coalesce(p.display_name,p.canonical_name)=v.provider_name
  join ref.outcome_surveys os on os.code='qilt_ses'
  join ref.outcome_metrics om on om.code=v.metric_code
)
insert into catalogue.provider_outcomes(
  provider_id,survey_id,metric_id,audience,collection_year_from,collection_year_to,
  metric_value,confidence_low,confidence_high,national_benchmark,source_id,evidence_id,
  source_institution_key,source_metric_code,source_cohort_code,status,metadata
)
select r.provider_id,r.survey_id,r.metric_id,'all',2023,2023,
       r.metric_value,r.ci_low,r.ci_high,r.national_benchmark,s.source_id,e.id,
       r.provider_name,r.metric_code,r.cohort,'current',
       jsonb_build_object('publisher','QILT','survey','SES','collection_year',2023,'cohort',r.cohort,'source_table','2023 SES National Report university tables','identity_authority',false)
from resolved r cross join srcid s cross join ev e
where not exists (
  select 1 from catalogue.provider_outcomes po
  where po.provider_id=r.provider_id and po.survey_id=r.survey_id and po.metric_id=r.metric_id
    and po.audience='all' and po.source_cohort_code=r.cohort
    and po.collection_year_from=2023 and po.collection_year_to=2023 and po.source_id=s.source_id
);

create or replace function security.admin_contextual_insights_v2(p_entity_type text,p_entity_id uuid)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','security','catalogue','scholarship','ref','auth'
as $function$
declare
  v_rank integer:=0; v_provider uuid; v_level uuid; v_country_code text;
  v_items jsonb:='[]'::jsonb; v_total integer:=0; v_base jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'catalogue reader role required' using errcode='42501'; end if;
  v_base:=security.admin_contextual_insights(p_entity_type,p_entity_id);
  if p_entity_type='provider' then
    select p.id,co.iso_alpha2 into v_provider,v_country_code from catalogue.providers p left join ref.countries co on co.id=p.country_id where p.id=p_entity_id;
  elsif p_entity_type='course' then
    select c.provider_id,c.study_level_id,co.iso_alpha2 into v_provider,v_level,v_country_code from catalogue.courses c join catalogue.providers p on p.id=c.provider_id left join ref.countries co on co.id=p.country_id where c.id=p_entity_id;
  else raise exception 'unsupported contextual entity type' using errcode='22023'; end if;
  if v_provider is null then return v_base; end if;
  select count(*) into v_total from catalogue.provider_outcomes po where po.provider_id=v_provider and coalesce(po.status,'current') in ('active','current') and (p_entity_type='provider' or po.study_level_id is null or v_level is null or po.study_level_id=v_level);
  select coalesce(jsonb_agg(jsonb_strip_nulls(to_jsonb(x)) order by x.level_match desc,x.collection_year_to desc nulls last,x.metric_name),'[]'::jsonb) into v_items
  from (
    select po.id,coalesce(os.source_family,case when v_country_code='AU' then 'QILT' else 'outcomes' end) source_family,
      coalesce(os.name,os.code,'Student outcomes') source_label,os.code survey_code,om.name metric_name,om.code metric_code,om.unit,
      po.metric_value,po.national_benchmark,po.response_count,po.confidence_low,po.confidence_high,po.audience,po.collection_year_from,po.collection_year_to,po.source_cohort_code,
      esa.name study_area,esa.external_code study_area_code,
      coalesce(sl.name,case po.source_cohort_code when 'UG' then 'Undergraduate' when 'PGC' then 'Postgraduate coursework' when 'PGR' then 'Postgraduate research' else null end) study_level,
      coalesce(sl.code,po.source_cohort_code) study_level_code,po.status,po.observed_at,po.evidence_id,
      case when p_entity_type='course' and po.study_level_id=v_level then true else false end level_match,
      case when p_entity_type='provider' then 'provider' else 'provider_context' end granularity
    from catalogue.provider_outcomes po
    left join ref.outcome_surveys os on os.id=po.survey_id left join ref.outcome_metrics om on om.id=po.metric_id
    left join ref.external_study_areas esa on esa.id=po.external_study_area_id left join ref.study_levels sl on sl.id=po.study_level_id
    where po.provider_id=v_provider and coalesce(po.status,'current') in ('active','current') and (p_entity_type='provider' or po.study_level_id is null or v_level is null or po.study_level_id=v_level)
    order by case when p_entity_type='course' and po.study_level_id=v_level then 1 else 0 end desc,po.collection_year_to desc nulls last,po.observed_at desc nulls last,om.name
    limit 60
  ) x;
  v_base:=jsonb_set(v_base,'{student_outcomes,items}',v_items,true);
  v_base:=jsonb_set(v_base,'{student_outcomes,total}',to_jsonb(v_total),true);
  v_base:=jsonb_set(v_base,'{student_outcomes,granularity}',to_jsonb(case when p_entity_type='provider' then 'provider' else 'provider_context' end),true);
  return v_base;
end
$function$;

grant execute on function security.admin_contextual_insights_v2(text,uuid) to authenticated,service_role;
revoke execute on function security.admin_contextual_insights_v2(text,uuid) from anon,public;
commit;
