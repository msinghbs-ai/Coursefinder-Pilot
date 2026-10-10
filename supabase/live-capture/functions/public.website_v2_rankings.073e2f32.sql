CREATE OR REPLACE FUNCTION public.website_v2_rankings(p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1, p_page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'ranking', 'catalogue', 'ref', 'search', 'security', 'api'
AS $function$
declare
  f jsonb := coalesce(p_filters,'{}'::jsonb);
  v_page int := coalesce(p_page,1); v_size int := coalesce(p_page_size,20);
  v_systems text[] := coalesce(api.website_text_array(f->'system_codes'), array['qs_wur','the_wur']);
  v_year int := nullif(f->>'edition_year','')::int;
  v_countries text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(coalesce(f->'country_codes',f->'country_code'))) x);
  v_providers text[] := api.website_text_array(f->'provider_ids');
  v_rank_max int := nullif(f->>'rank_max','')::int;
  v_known text[] := array['system_codes','edition_year','country_codes','country_code','provider_ids','rank_max'];
  v_not_applied jsonb; v_total bigint; v_items jsonb;
begin
  if v_page < 1 or v_size < 1 or v_size > 50 then raise exception 'INVALID_INPUT: page must be >= 1 and page_size 1-50' using errcode='22023'; end if;
  select coalesce(jsonb_agg(k),'[]'::jsonb) into v_not_applied from jsonb_object_keys(f) k where k <> all(v_known);
  with ed as (
    select e.id, e.edition_year, s.code, s.ranking_name, s.publisher_name, e.methodology_url, coalesce(e.source_url, s.official_url) source_url
    from ranking.editions e join ranking.systems s on s.id=e.system_id
    where e.status='accepted' and s.code = any(v_systems)
      and e.edition_year = coalesce(v_year, (select max(e2.edition_year) from ranking.editions e2 where e2.system_id=s.id and e2.status='accepted'))
  ), rows as (
    select distinct on (ed.id, l.provider_id) ed.*, o.id obs_id, o.rank_display, coalesce(o.rank_low,o.rank_exact) rank_low, coalesce(o.rank_high,o.rank_exact) rank_high,
           coalesce(o.is_tied,false) is_tied, o.overall_score_display, l.provider_id, p.stable_key provider_stable_key, coalesce(p.display_name,p.canonical_name) provider_name, c.iso_alpha2 country_code
    from ed join ranking.observations o on o.edition_id=ed.id
    join ranking.observation_provider_links l on l.observation_id=o.id
    join catalogue.providers p on p.id=l.provider_id join ref.countries c on c.id=p.country_id
    where (v_countries is null or trim(c.iso_alpha2::text) = any(v_countries))
      and (v_providers is null or p.stable_key = any(v_providers))
      and (v_rank_max is null or coalesce(o.rank_low,o.rank_exact) <= v_rank_max)
    order by ed.id, l.provider_id, l.is_primary desc nulls last
  ), ordered as (select *, count(*) over () total, row_number() over (order by code, rank_low nulls last, provider_name) rn from rows)
  select coalesce(max(total),0), coalesce(jsonb_agg(jsonb_build_object(
      'provider', jsonb_build_object('provider_id', o.provider_stable_key, 'name', security.provider_presentable_name(o.provider_name), 'country_code', trim(o.country_code::text), 'logo', api.website_v2_provider_logo(o.provider_id)),
      'system_code', o.code, 'system_name', o.ranking_name, 'publisher', o.publisher_name, 'edition_year', o.edition_year,
      'rank_display', o.rank_display, 'rank_low', o.rank_low, 'rank_high', o.rank_high, 'is_tied', o.is_tied, 'overall_score_display', o.overall_score_display,
      'indicators', (select coalesce(jsonb_agg(jsonb_build_object('code', io.indicator_code, 'label', io.indicator_label, 'value_display', io.value_display, 'rank_display', io.rank_display) order by io.indicator_code), '[]'::jsonb)
                     from ranking.indicator_observations io where io.observation_id=o.obs_id),
      'methodology_url', o.methodology_url, 'source_url', o.source_url,
      'attribution', o.publisher_name || ', ' || o.ranking_name || ' ' || o.edition_year,
      'terms_status', 'management_decision_pending') order by o.rn) filter (where o.rn > (v_page-1)*v_size and o.rn <= v_page*v_size), '[]'::jsonb)
  into v_total, v_items from ordered o;
  return jsonb_build_object('contract_version','website-search-v2','total',v_total,'page',v_page,'page_size',v_size,'filters_not_applied',v_not_applied,'items',v_items);
end $function$
