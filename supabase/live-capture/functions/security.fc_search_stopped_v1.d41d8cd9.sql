CREATE OR REPLACE FUNCTION security.fc_search_stopped_v1()
 RETURNS TABLE(provider_id uuid, searches bigint, since timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with w as (select u.provider_id, greatest(now() - interval '7 days', coalesce(max(r.resumed_at), '-infinity'::timestamptz)) since
               from (select distinct x.provider_id from pipeline.coverage_vendor_usage x where x.purpose = 'course_link_search' and x.at > now() - interval '7 days') u
               left join pipeline.firecrawl_search_resumes r on r.provider_id = u.provider_id group by u.provider_id)
  select w.provider_id, count(*) searches, w.since
    from w join pipeline.coverage_vendor_usage x on x.provider_id = w.provider_id and x.purpose = 'course_link_search' and x.at > w.since and x.at < now() - interval '1 hour'
   where not exists (select 1 from pipeline.coverage_course_pages pg where pg.provider_id = w.provider_id and pg.read_at > w.since and pg.status = 'bound' and pg.read_status = 'read')
   group by w.provider_id, w.since
  having count(*) >= security.fc_setting_num_v1('search_stop_after', 30)
$function$
