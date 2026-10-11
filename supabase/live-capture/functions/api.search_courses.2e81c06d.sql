CREATE OR REPLACE FUNCTION api.search_courses(p_query text, p_country character DEFAULT NULL::bpchar, p_level_code text DEFAULT NULL::text, p_has_scholarship boolean DEFAULT NULL::boolean, p_limit integer DEFAULT 20)
 RETURNS TABLE(course_id uuid, provider_name text, course_title text, level_code text, rank real, has_fee boolean, has_intake boolean, has_english boolean, has_scholarship boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'search', 'ref', 'security'
AS $function$
select d.course_id,d.provider_name,d.course_title,sl.code,
       ts_rank_cd(d.search_tsv,websearch_to_tsquery('english',coalesce(p_query,'')))::real,
       d.has_fee,d.has_intake,d.has_english,d.has_scholarship
from search.course_documents d left join ref.study_levels sl on sl.id=d.study_level_id join ref.countries co on co.id=d.country_id
where security.current_role_rank()>=1 and not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id) and d.publication_status in ('published','internal')
 and (p_country is null or co.iso_alpha2=p_country)
 and (p_level_code is null or sl.code=p_level_code)
 and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
 and (coalesce(trim(p_query),'')='' or d.search_tsv @@ websearch_to_tsquery('english',p_query))
order by ts_rank_cd(d.search_tsv,websearch_to_tsquery('english',coalesce(p_query,''))) desc,d.course_title
limit least(greatest(coalesce(p_limit,20),1),50)
$function$
