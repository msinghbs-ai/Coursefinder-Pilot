CREATE OR REPLACE FUNCTION api.courses_list(p_provider_id uuid DEFAULT NULL::uuid, p_country character DEFAULT NULL::bpchar, p_level_code text DEFAULT NULL::text, p_publication text DEFAULT NULL::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, stable_key text, provider_id uuid, provider_name text, canonical_title text, course_code text, level_code text, publication_status text, completeness_score numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'catalogue', 'ref', 'publishing', 'security'
AS $function$
select c.id,c.stable_key,c.provider_id,coalesce(p.display_name,p.canonical_name),c.canonical_title,c.course_code,sl.code,c.publication_status,max(es.completeness_score)
from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
left join ref.study_levels sl on sl.id=c.study_level_id left join publishing.entity_states es on es.entity_id=c.id
where security.current_role_rank()>=1
  and not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=c.id)
  and (p_provider_id is null or c.provider_id=p_provider_id)
  and (p_country is null or co.iso_alpha2=p_country)
  and (p_level_code is null or sl.code=p_level_code)
  and (p_publication is null or c.publication_status=p_publication)
group by c.id,p.canonical_name,p.display_name,sl.code
order by c.canonical_title
limit least(greatest(coalesce(p_limit,100),1),500) offset greatest(coalesce(p_offset,0),0)
$function$
