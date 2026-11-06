CREATE OR REPLACE FUNCTION security.website_sync_candidates_v1(p_entity text)
 RETURNS TABLE(item_key text, ref_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select k, max(r::text)::uuid from (
    select 'reference' k, null::uuid r where p_entity = 'reference'
    union all
    select p.stable_key, p.id from catalogue.providers p
     where p_entity in ('provider', 'logo', 'rankings') and p.stable_key is not null
       and p.id not in (select h.provider_id from security.provider_hidden_v1 h where h.provider_id is not null)
       and exists (select 1 from search.course_documents d where d.provider_id = p.id)
    union all
    select s.stable_key, s.id from scholarship.scholarships s where p_entity = 'scholarship' and s.stable_key is not null
    union all
    select d.course_stable_key, d.course_id from search.course_documents d where p_entity = 'course' and d.course_stable_key is not null
    union all
    select i.item_key, i.ref_id from pipeline.website_sync_items i where i.entity = p_entity and i.removed_at is null) z
  group by k
$function$
