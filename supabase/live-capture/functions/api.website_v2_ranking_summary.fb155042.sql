CREATE OR REPLACE FUNCTION api.website_v2_ranking_summary(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'ranking'
AS $function$
  with r as (
    select distinct on (s.code) s.code, e.edition_year, o.rank_display, o.rank_low, o.rank_exact
    from ranking.observation_provider_links l
    join ranking.observations o on o.id = l.observation_id
    join ranking.editions e on e.id = o.edition_id and e.status = 'accepted'
    join ranking.systems s on s.id = e.system_id
    where l.provider_id = p_provider_id
    order by s.code, e.edition_year desc, l.is_primary desc nulls last
  )
  select case when count(*) = 0 then null else jsonb_object_agg(r.code, jsonb_build_object(
    'edition_year', r.edition_year, 'rank_display', r.rank_display, 'rank_low', coalesce(r.rank_low, r.rank_exact),
    'terms_status', 'management_decision_pending')) end
  from r
$function$
