CREATE OR REPLACE FUNCTION security.layer4_boost_study_load_inbox_page_v1(p_args jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with o as (select r.* from pipeline.boost_study_load_reviews r
              where r.status = 'open' and (nullif(p_args->>'provider_id', '') is null or r.provider_id = (p_args->>'provider_id')::uuid)),
  x as (select o.* from o
         where nullif(p_args->>'after_ref', '') is null or (o.opened_at, o.id::text) > ((p_args->>'after_at')::timestamptz, p_args->>'after_ref')
         order by o.opened_at, o.id::text
         limit least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200))  -- fixed: page size bounds, as the Inbox's own
  select jsonb_build_object('kind', 'boost_study_load',
    'before', case when nullif(p_args->>'after_ref', '') is not null then
                (select count(*) from o where (o.opened_at, o.id::text) <= ((p_args->>'after_at')::timestamptz, p_args->>'after_ref')) end,
    'items', coalesce((select jsonb_agg(jsonb_build_object('kind', 'boost_study_load', 'ref', x.id::text, 'provider_id', x.provider_id,
           'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = x.provider_id),
           'subject', coalesce((select c.display_title from catalogue.courses c where c.id = x.course_id), 'Course') || ' · study load',
           'why', 'The page check refused the reading: ' || coalesce(x.problems->>0, 'no reason recorded'),
           'suggestion', case when x.answer->>'study_load' is not null then 'The model read ' || replace(x.answer->>'study_load', '_', '-') || '; check it against the page' end,
           'created_at', x.opened_at, 'course_id', x.course_id, 'source_url', x.source_url,
           'late', x.opened_at < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int)) order by x.opened_at, x.id::text) from x), '[]'::jsonb))
$function$
