CREATE OR REPLACE FUNCTION public.ui_review_filter_options()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'workflow', 'auth'
AS $function$ select case when auth.uid() is null then null else jsonb_build_object('domains',(select coalesce(jsonb_agg(jsonb_build_object('code',x.domain,'name',x.domain) order by x.domain),'[]'::jsonb) from (select distinct domain from workflow.review_queue where domain is not null)x),'statuses',(select coalesce(jsonb_agg(jsonb_build_object('code',x.status,'name',x.status) order by x.status),'[]'::jsonb) from (select distinct status from workflow.review_queue where status is not null)x)) end $function$
