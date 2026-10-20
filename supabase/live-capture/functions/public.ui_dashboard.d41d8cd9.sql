CREATE OR REPLACE FUNCTION public.ui_dashboard()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'catalogue', 'scholarship', 'pipeline', 'workflow', 'pim', 'search', 'auth'
AS $function$
select case when auth.uid() is null then '{}'::jsonb else jsonb_build_object(
 'providers',(select count(*) from catalogue.providers),
 'courses',(select count(*) from catalogue.courses),
 'campuses',(select count(*) from catalogue.campuses),
 'course_campus_links',(select count(*) from catalogue.course_campuses),
 'scholarships',(select count(*) from scholarship.scholarships),
 'jobs',(select count(*) from pipeline.jobs),
 'open_reviews',(select count(*) from workflow.review_queue where status in ('open','in_review')),
 'evidence',(select count(*) from pipeline.evidence_artifacts),
 'attributes',(select count(*) from pim.attribute_definitions),
 'search_documents',(select count(*) from search.course_documents),
 'search_generation',(select generation from search.projection_state where projection_code='courses')
) end
$function$
