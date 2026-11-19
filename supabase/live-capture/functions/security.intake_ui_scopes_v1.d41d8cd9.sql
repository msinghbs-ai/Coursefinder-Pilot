CREATE OR REPLACE FUNCTION security.intake_ui_scopes_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'active_courses',n) order by n desc,md5(id::text)),'[]')
 from (select p.id,coalesce(p.display_name,p.canonical_name) name,count(c.id) n
 from catalogue.providers p join ref.countries co on co.id=p.country_id and co.iso_alpha2='AU'
 join ref.provider_types t on t.id=p.provider_type_id and t.code='university'
 join catalogue.courses c on c.provider_id=p.id and c.lifecycle_status='active'
 where p.lifecycle_status='active' group by p.id,2 order by count(c.id) desc,md5(p.id::text)
 limit security.pipeline_num_v1('run_now.cohort_top_au_universities',10)::int) u
$function$
