CREATE OR REPLACE FUNCTION security.provider_description_quality_counts_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with q as (select * from security.provider_description_quality_v1(null, true)),
       c as (select coalesce(quality_class, 'unknown') k, count(*) n from q group by 1),
       s as (select count(*) n, min(computed_at) oldest, max(computed_at) newest from pipeline.provider_description_quality)
  select jsonb_build_object('as_at', now(), 'total', (select count(*) from q),
    'classes', coalesce((select jsonb_object_agg(k, n) from c), '{}'::jsonb),
    'with_description', (select count(*) from q where description_filled),
    'website_publication', coalesce((select jsonb_object_agg(coalesce(website_publication, 'none'), n) from (select website_publication, count(*) n from q where description_filled group by 1) w), '{}'::jsonb),
    'zoho_publication', coalesce((select jsonb_object_agg(coalesce(zoho_publication, 'none'), n) from (select zoho_publication, count(*) n from q where description_filled group by 1) z), '{}'::jsonb),
    'snapshot', (select jsonb_build_object('rows', s.n, 'oldest', s.oldest, 'newest', s.newest) from s))
$function$
