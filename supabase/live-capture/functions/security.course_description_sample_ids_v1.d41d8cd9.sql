CREATE OR REPLACE FUNCTION security.course_description_sample_ids_v1()
 RETURNS TABLE(item_id uuid, country text, pick integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with strata as (select upper(x) code from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_sample_countries'), '[]'::jsonb)) x),
  ranked as (select el.item_id, el.country, row_number() over (partition by el.country order by md5(el.item_id::text)) rn
               from security.course_description_sample_pool_v1() el where el.country in (select code from strata))
  select ranked.item_id, ranked.country, ranked.rn::int from ranked
   where ranked.rn <= security.pipeline_num_v1('enrich.course_description_sample_' || lower(ranked.country), 0)
$function$
