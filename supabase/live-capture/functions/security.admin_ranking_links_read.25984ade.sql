CREATE OR REPLACE FUNCTION security.admin_ranking_links_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_system text := nullif(p_args->>'system_code', ''); v_year int := nullif(p_args->>'edition_year', '')::int;
        v_country text := nullif(p_args->>'country', ''); v_provider uuid := nullif(p_args->>'provider_id', '')::uuid; v_query text := nullif(btrim(p_args->>'query'), '');
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  if p_operation = 'ranking_filter_options' then
    return (with base as (
        select pi.country_text, o.provider_id, coalesce(p.display_name, p.canonical_name) provider_name, sd.code state_code, sd.name state_name
          from ranking.observations o join ranking.editions e on e.id = o.edition_id join ranking.systems s on s.id = e.system_id
          join ranking.publisher_institutions pi on pi.id = o.publisher_institution_id
          left join catalogue.providers p on p.id = o.provider_id left join ref.subdivisions sd on sd.id = p.subdivision_id
         where e.status = 'accepted' and (v_system is null or s.code = v_system) and (v_year is null or e.edition_year = v_year))
      select jsonb_build_object(
        'can_link', v_rank >= 3,
        'countries', coalesce((select jsonb_agg(jsonb_build_object('value', country_text, 'count', n,
                        'in_catalogue', exists (select 1 from catalogue.providers p2 where p2.country_id = security.ranking_country_id(q.country_text) and p2.lifecycle_status = 'active')) order by n desc, country_text)
                        from (select country_text, count(*) n from base where country_text is not null group by 1) q), '[]'::jsonb),
        'states', coalesce((select jsonb_agg(jsonb_build_object('value', state_code, 'label', state_name, 'count', n) order by state_name)
                        from (select state_code, state_name, count(*) n from base where state_code is not null and (v_country is null or country_text = v_country) group by 1, 2) q), '[]'::jsonb),
        'providers', coalesce((select jsonb_agg(jsonb_build_object('value', provider_id, 'label', provider_name) order by provider_name)
                        from (select distinct provider_id, provider_name from base where provider_id is not null and (v_country is null or country_text = v_country)) q), '[]'::jsonb),
        'linked', (select count(*) from base where provider_id is not null and (v_country is null or country_text = v_country)),
        'not_linked', (select count(*) from base where provider_id is null and (v_country is null or country_text = v_country)),
        'not_linked_in_catalogue_countries', (select count(*) from base b where b.provider_id is null and (v_country is null or b.country_text = v_country)
                        and exists (select 1 from catalogue.providers p2 where p2.country_id = security.ranking_country_id(b.country_text) and p2.lifecycle_status = 'active'))));
  elsif p_operation = 'ranking_link_candidates' then
    return jsonb_build_object('can_link', v_rank >= 3, 'items', coalesce((select jsonb_agg(jsonb_build_object('provider_id', m.provider_id,
             'provider_name', coalesce(p.display_name, p.canonical_name), 'state', sd.code, 'confidence', m.confidence) order by m.confidence desc)
             from ranking.provider_mappings m join catalogue.providers p on p.id = m.provider_id left join ref.subdivisions sd on sd.id = p.subdivision_id
            where m.publisher_institution_id = nullif(p_args->>'publisher_institution_id', '')::uuid and m.status = 'candidate'), '[]'::jsonb));
  elsif p_operation = 'ranking_provider_search' then
    if v_query is null or length(v_query) < 3 then return jsonb_build_object('items', '[]'::jsonb); end if;
    return jsonb_build_object('items', coalesce((select jsonb_agg(x) from (
             select jsonb_build_object('provider_id', p.id, 'provider_name', coalesce(p.display_name, p.canonical_name), 'state', sd.code) x
               from catalogue.providers p left join ref.subdivisions sd on sd.id = p.subdivision_id
              where p.lifecycle_status = 'active' and (v_country is null or p.country_id = security.ranking_country_id(v_country))
                and (coalesce(p.display_name, p.canonical_name) ilike '%' || v_query || '%'
                     or exists (select 1 from catalogue.provider_aliases a where a.provider_id = p.id and a.valid_to is null and a.alias ilike '%' || v_query || '%'))
              order by length(coalesce(p.display_name, p.canonical_name)) limit 20) q), '[]'::jsonb));
  elsif p_operation = 'provider_ranking_history' then
    return jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('system_code', s.code, 'ranking_name', s.ranking_name, 'edition_year', e.edition_year,
             'rank_display', o.rank_display, 'rank_exact', o.rank_exact, 'overall_score', o.overall_score, 'publisher_name', pi.institution_name,
             'evidence_artifact_id', o.evidence_artifact_id) order by s.code, e.edition_year desc)
             from ranking.observation_provider_links l join ranking.observations o on o.id = l.observation_id
             join ranking.editions e on e.id = o.edition_id and e.status = 'accepted' join ranking.systems s on s.id = e.system_id
             join ranking.publisher_institutions pi on pi.id = o.publisher_institution_id
            where l.provider_id = v_provider), '[]'::jsonb));
  end if;
  raise exception 'unsupported ranking link read: %', p_operation using errcode = '22023';
end $function$
