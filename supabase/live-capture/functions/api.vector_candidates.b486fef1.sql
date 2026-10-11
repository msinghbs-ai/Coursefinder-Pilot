CREATE OR REPLACE FUNCTION api.vector_candidates(p_embedding extensions.vector, p_profile_code text, p_country character DEFAULT NULL::bpchar, p_level_code text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS TABLE(course_id uuid, distance double precision)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'search', 'ref', 'security', 'extensions'
AS $function$
select e.course_id,(e.embedding<=>p_embedding)::double precision
from search.course_embeddings e join search.profiles sp on sp.id=e.profile_id join search.course_documents d on d.course_id=e.course_id
join ref.countries co on co.id=d.country_id left join ref.study_levels sl on sl.id=d.study_level_id
where security.current_role_rank()>=1 and not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id) and sp.code=p_profile_code and (p_country is null or co.iso_alpha2=p_country) and (p_level_code is null or sl.code=p_level_code)
order by e.embedding<=>p_embedding limit least(greatest(coalesce(p_limit,50),1),100)
$function$
