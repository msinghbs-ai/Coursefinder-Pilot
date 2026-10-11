CREATE OR REPLACE FUNCTION api.providers_list(p_country character DEFAULT NULL::bpchar, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, stable_key text, canonical_name text, display_name text, country_code character, publication_status text, course_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'catalogue', 'ref', 'security'
AS $function$
select p.id,p.stable_key,p.canonical_name,p.display_name,c.iso_alpha2,p.publication_status,count(cr.id)::bigint
from catalogue.providers p join ref.countries c on c.id=p.country_id left join catalogue.courses cr on cr.provider_id=p.id and not exists (select 1 from security.layer4_search_blocked_courses cf_course_block where cf_course_block.course_id=cr.id)
where security.current_role_rank()>=1 and not exists (select 1 from security.layer4_search_blocked_providers cf_block where cf_block.provider_id=p.id) and (p_country is null or c.iso_alpha2=p_country)
group by p.id,c.iso_alpha2
order by coalesce(p.display_name,p.canonical_name)
limit least(greatest(coalesce(p_limit,100),1),500) offset greatest(coalesce(p_offset,0),0)
$function$
