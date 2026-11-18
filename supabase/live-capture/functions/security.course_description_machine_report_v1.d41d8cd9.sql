CREATE OR REPLACE FUNCTION security.course_description_machine_report_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object('contract', 'course-description-machine-report-v1', 'as_at', now(), 'switch_on', security.pipeline_num_v1('enrich.course_description_machine_on', 0) >= 1,
    'admitted', (select count(*) from pipeline.course_description_machine_admissions where outcome = 'admitted' and withdrawn_at is null),
    'admitted_24h', (select count(*) from pipeline.course_description_machine_admissions where outcome = 'admitted' and withdrawn_at is null and created_at > now() - make_interval(hours => 24)), -- fixed: report window
    'admitted_7d', (select count(*) from pipeline.course_description_machine_admissions where outcome = 'admitted' and withdrawn_at is null and created_at > now() - make_interval(days => 7)), -- fixed: report window
    'withdrawn', (select count(*) from pipeline.course_description_machine_admissions where outcome = 'admitted' and withdrawn_at is not null),
    'admitted_by_provider', (select count(distinct provider_id) from pipeline.course_description_machine_admissions where outcome = 'admitted' and withdrawn_at is null),
    'website', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select coalesce(consumer_check, 'unchecked') k, count(*) n from pipeline.course_description_machine_admissions where outcome = 'admitted' and withdrawn_at is null group by 1) z),
    'declined_by_reason', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select d.reason_code k, count(*) n from pipeline.course_description_machine_admissions d
                             join pipeline.layer4_review_items li on li.id = d.review_item_id and li.status = 'pending' where d.outcome = 'declined' group by 1) z),
    'waiting_items', (select count(*) from pipeline.layer4_review_items where field_code = 'course_description_first_read' and entity_type = 'course' and status = 'pending'))
$function$
