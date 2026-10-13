CREATE OR REPLACE FUNCTION security.fc_search_stopped_v1()
 RETURNS TABLE(provider_id uuid, searches bigint, since timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with s as (
  with w as (select u.provider_id, greatest(now() - make_interval(days => security.fc_setting_num_v1('search_stop_window_days', 7)::int), coalesce(max(r.resumed_at), '-infinity'::timestamptz)) since
               from (select distinct x.provider_id from pipeline.coverage_vendor_usage x where x.purpose = 'course_link_search' and x.at > now() - make_interval(days => security.fc_setting_num_v1('search_stop_window_days', 7)::int)) u
               left join pipeline.firecrawl_search_resumes r on r.provider_id = u.provider_id group by u.provider_id)
  select w.provider_id, count(*) searches, w.since
    from w join pipeline.coverage_vendor_usage x on x.provider_id = w.provider_id and x.purpose = 'course_link_search' and x.at > w.since and x.at < now() - interval '1 hour' -- fixed: searches still in flight are not counted
   where not exists (select 1 from pipeline.coverage_course_pages pg where pg.provider_id = w.provider_id and pg.read_at > w.since and pg.status = 'bound' and pg.read_status = 'read')
   group by w.provider_id, w.since
  having count(*) >= security.fc_setting_num_v1('search_stop_after', 30))
  select s.provider_id, s.searches, s.since from s
  union all
  -- v2.15.265: held by the Platform Admin for an adapter check, until Search again
  select h.provider_id, 0::bigint, h.held_at from pipeline.firecrawl_search_holds h
   where not exists (select 1 from pipeline.firecrawl_search_resumes r where r.provider_id = h.provider_id and r.resumed_at > h.held_at)
     and h.provider_id not in (select s2.provider_id from s s2)
$function$
