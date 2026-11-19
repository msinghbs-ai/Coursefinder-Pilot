CREATE OR REPLACE FUNCTION security.layer4_boost_study_load_inbox_counts_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with o as (select * from pipeline.boost_study_load_reviews where status = 'open')
  select jsonb_build_object('kind', 'boost_study_load', 'n', (select count(*) from o), 'oldest', (select min(o.opened_at) from o),
    'late', (select count(*) from o where o.opened_at < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int)),
    'by_provider', coalesce((select jsonb_agg(jsonb_build_object('provider_id', z.provider_id, 'n', z.n, 'oldest', z.oldest) order by z.oldest)
                               from (select o.provider_id, count(*) n, min(o.opened_at) oldest from o group by 1) z), '[]'::jsonb))
$function$
