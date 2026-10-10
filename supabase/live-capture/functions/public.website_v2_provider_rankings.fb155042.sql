CREATE OR REPLACE FUNCTION public.website_v2_provider_rankings(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'ranking'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
      'system_code', s.code, 'system_name', s.ranking_name, 'publisher', s.publisher_name, 'edition_year', e.edition_year,
      'rank_display', o.rank_display, 'rank_low', coalesce(o.rank_low,o.rank_exact), 'rank_high', coalesce(o.rank_high,o.rank_exact), 'is_tied', coalesce(o.is_tied,false),
      'overall_score_display', o.overall_score_display,
      'indicators', (select coalesce(jsonb_agg(jsonb_build_object('code', io.indicator_code, 'label', io.indicator_label, 'value_display', io.value_display, 'rank_display', io.rank_display) order by io.indicator_code), '[]'::jsonb)
                     from ranking.indicator_observations io where io.observation_id=o.id),
      'methodology_url', e.methodology_url, 'source_url', coalesce(e.source_url, s.official_url),
      'attribution', s.publisher_name || ', ' || s.ranking_name || ' ' || e.edition_year,
      'terms_status', 'management_decision_pending')
    order by s.code, e.edition_year desc), '[]'::jsonb)
  from (select distinct on (o2.edition_id) o2.* from ranking.observation_provider_links l join ranking.observations o2 on o2.id=l.observation_id
        where l.provider_id=p_provider_id order by o2.edition_id, l.is_primary desc nulls last) o
  join ranking.editions e on e.id=o.edition_id and e.status='accepted' join ranking.systems s on s.id=e.system_id
$function$
