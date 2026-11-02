CREATE OR REPLACE FUNCTION security.enrich_plan_priority_v1()
 RETURNS TABLE(provider_id uuid, name text, country text, courses bigint, missing bigint, best_rank integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select a.provider_id, max(coalesce(p.display_name, p.canonical_name)), max(a.country_code), count(distinct a.course_id),
         count(*) filter (where a.state <> 'admitted'),
         (select min(coalesce(o.rank_low, o.rank_exact)) from ranking.observation_provider_links l join ranking.observations o on o.id = l.observation_id where l.provider_id = a.provider_id)
    from pipeline.course_attribute_coverage a join pipeline.field_register r on r.field = a.attribute and r.reader in ('coverage', 'enrich')
    join catalogue.providers p on p.id = a.provider_id
   where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = a.provider_id)
   group by a.provider_id
  having count(*) filter (where a.state <> 'admitted') > 0
$function$
