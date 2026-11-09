CREATE OR REPLACE FUNCTION security.layer4_pace_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Per kind: the median minutes between consecutive decisions of one reviewer, counting only gaps above layer4.pace_min_gap_seconds (closer ones
-- are bulk actions) and up to layer4.pace_gap_minutes (longer gaps are breaks); kinds with fewer than layer4.pace_min_decisions measured decisions use layer4.pace_default_minutes. {kind: {minutes, measured, basis}}.
  with d as (select r.field_code, extract(epoch from x.created_at - lag(x.created_at) over (partition by x.actor_id order by x.created_at)) / 60.0 gap
               from pipeline.layer4_decisions x join pipeline.layer4_review_items r on r.id = x.review_item_id
              where x.created_at > now() - make_interval(days => security.pipeline_num_v1('layer4.pace_window_days', 30)::int) and x.actor_id is not null),
       k as (select d.field_code, count(*) n, percentile_cont(0.5) within group (order by d.gap) p50 from d
              where d.gap > security.pipeline_num_v1('layer4.pace_min_gap_seconds', 20) / 60.0 and d.gap <= security.pipeline_num_v1('layer4.pace_gap_minutes', 15) group by d.field_code)
  select coalesce(jsonb_object_agg(k.field_code, jsonb_build_object(
           'minutes', case when k.n >= security.pipeline_num_v1('layer4.pace_min_decisions', 5) then round(k.p50::numeric, 2) else security.pipeline_num_v1('layer4.pace_default_minutes', 3) end,
           'measured', k.n, 'basis', case when k.n >= security.pipeline_num_v1('layer4.pace_min_decisions', 5) then 'measured' else 'default' end)), '{}'::jsonb)
    from k
$function$;
