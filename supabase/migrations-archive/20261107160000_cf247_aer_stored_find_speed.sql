-- CF-247 AER source discovery, speed fix to the stored-link step (found on the first live measurement after 20261107150000 was applied, 7 Nov 2026).
-- Guards: G1/G2 (no new job or setting; the step is still off and its job paused), G3 (no consumer API object is touched), Decision 260 (housekeeping),
--   "A passing qualification never switches anything on by itself" (nothing is switched on here).
-- Live measure of security.entry_source_stored_find_v1(3, false): 33 seconds for three providers, so a run of 200 could never finish. Two causes:
--   1. the eligibility rule security.entry_matrix_attach_allowed_v1 was called for every eligible provider (1,476 times, each rebuilding the eligible set): 12 s for the selection alone;
--   2. every stored link of a provider was scored three times (the biggest provider holds 18,663 links: 6.4 s for one pass).
-- Now: the rule is judged one provider at a time and only as far as the run needs; each link is scored once and only if it holds a word every page rule needs.
-- Outcomes, picks and the links count (distinct addresses) are unchanged: a link that cannot score never counted as a candidate.
-- Replaces: security.entry_source_stored_find_v1 (same name and result; faster)
-- Retires: nothing

create or replace function security.entry_source_stored_find_v1(p_limit integer default null, p_apply boolean default true) returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  v_limit int := coalesce(p_limit, security.pipeline_num_v1('batch.aer_source_stored_find', 200)::int);
  v_max int := security.pipeline_num_v1('entry.attach_per_provider', 3)::int;
  v_min numeric := greatest(security.pipeline_num_v1('central.min_suggest_score', 4), 3);  -- fixed: the worker never suggests a page that scores under 3
  v_days int := security.pipeline_num_v1('aer.source_stored_find_recheck_days', 14)::int;
  r record; v_c jsonb; v_links int; v_cands int; v_weak int; v_best_url text; v_best_score numeric; v_shared boolean; v_pick jsonb; v_att int; v_out text;
  v_tally jsonb := '{}'::jsonb; v_looked int := 0; v_sources int := 0; v_preview jsonb := '[]'::jsonb;
begin
  if p_apply and security.pipeline_num_v1('aer.source_stored_find_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  if security.pipeline_num_v1('entry.matrix_enabled', 0) < 1 then return jsonb_build_object('on', false, 'reason', 'the entry matrix reader is off (entry.matrix_enabled)'); end if;
  for r in
    select p.id provider_id, security.site_host_v1(p.website) ph
      from security.aer_eligible_v1() e join catalogue.providers p on p.id = e.provider_id
     where not exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = p.id)
       and coalesce(btrim(p.website), '') ~* '^https?://' and not security.third_party_host_v1(p.website)
       and not exists (select 1 from pipeline.aer_source_stored_find f where f.provider_id = p.id and (f.outcome = 'attached' or f.checked_at > now() - make_interval(days => v_days)))
     order by (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') desc, p.id
  loop
    -- the eligibility rule is judged one provider at a time, only as far as the run needs (it rebuilds the eligible set on every call)
    if v_looked >= v_limit then exit; end if;
    if not security.entry_matrix_attach_allowed_v1(r.provider_id) then continue; end if;
    v_looked := v_looked + 1;
    select count(distinct lower(regexp_replace(regexp_replace(u.url, '^https?://(www\.)?', ''), '/+$', ''))) into v_links
      from (select l.url from pipeline.coverage_provider_urls l where l.provider_id = r.provider_id
            union all select l.url from pipeline.provider_discovery_links l where l.provider_id = r.provider_id) u;
    -- only the links that can be an entry-requirements page are scored, each once (a provider can hold 18,000 links); own website host (or a sub-domain) only; one row an address
    select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) into v_c from (
      select distinct on (kk.k) u.url, u.title, u.src, u.pages, u.score,
             coalesce(security.site_host_v1(u.url) = r.ph or right(security.site_host_v1(u.url), length(r.ph) + 1) = '.' || r.ph, false) ownhost
        from (select z.*, security.entry_source_score_v1(z.url, z.title) score
                from (select l.url, l.title, 'coverage_provider_urls' src, 1 pages from pipeline.coverage_provider_urls l where l.provider_id = r.provider_id
                      union all select l.url, l.anchor_text, 'provider_discovery_links', coalesce(l.pages, 1) from pipeline.provider_discovery_links l where l.provider_id = r.provider_id) z
               where (z.url || ' ' || coalesce(z.title, '')) ~* 'entr|equivalen|qualif|academic|admission') u,  -- fixed: every page rule needs one of these words, so this only skips links that cannot score
             lateral (select lower(regexp_replace(regexp_replace(u.url, '^https?://(www\.)?', ''), '/+$', '')) k) kk
       where u.score is not null
       order by kk.k, u.score desc, u.pages desc, length(u.url), u.url) q;
    select count(*) filter (where x.score >= v_min and x.ownhost), count(*) filter (where x.score is not null and x.ownhost and x.score < v_min)
      into v_cands, v_weak from jsonb_to_recordset(v_c) as x(url text, title text, src text, pages int, score numeric, ownhost boolean);
    select x.url, x.score into v_best_url, v_best_score from jsonb_to_recordset(v_c) as x(url text, title text, src text, pages int, score numeric, ownhost boolean)
     where x.score is not null and x.ownhost order by x.score desc, length(x.url), x.url limit 1;
    v_shared := exists (select 1 from catalogue.providers o where o.id <> r.provider_id and o.lifecycle_status = 'active' and security.site_host_v1(o.website) = r.ph);
    v_att := 0; v_pick := '[]'::jsonb;
    v_out := case when v_links = 0 then 'no_link_material' when v_cands = 0 then 'no_entry_candidate' when v_shared then 'host_shared' else 'attached' end;
    if v_out = 'attached' then
      select coalesce(jsonb_agg(jsonb_build_object('url', t.url, 'title', t.title, 'score', t.score, 'source', t.src, 'pages', t.pages, 'rank', t.rn) order by t.rn), '[]'::jsonb) into v_pick
        from (select x.*, row_number() over (order by x.score desc, length(x.url), x.url) rn from jsonb_to_recordset(v_c) as x(url text, title text, src text, pages int, score numeric, ownhost boolean)
               where x.score >= v_min and x.ownhost) t where t.rn <= v_max;
      if p_apply then
        insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
        select r.provider_id, e->>'url', left(e->>'title', 200), (e->>'rank')::int, 'search' from jsonb_array_elements(v_pick) e
        on conflict (provider_id, url) do nothing;
        get diagnostics v_att = row_count;
        v_sources := v_sources + v_att;
      end if;
    end if;
    v_tally := jsonb_set(v_tally, array[v_out], to_jsonb(coalesce((v_tally->>v_out)::int, 0) + 1));
    if not p_apply and v_out = 'attached' then v_preview := v_preview || jsonb_build_object('provider_id', r.provider_id, 'pick', v_pick); end if;
    if p_apply then
      insert into pipeline.aer_source_stored_find(provider_id, checked_at, outcome, links, candidates, best_url, best_score, attached, detail)
      values (r.provider_id, now(), v_out, v_links, v_cands, v_best_url, v_best_score, v_att,
              jsonb_build_object('below_threshold', v_weak, 'host_shared', v_shared, 'min_score', v_min, 'picked', v_pick))
      on conflict (provider_id) do update set checked_at = excluded.checked_at, outcome = excluded.outcome, links = excluded.links, candidates = excluded.candidates,
        best_url = excluded.best_url, best_score = excluded.best_score, attached = excluded.attached, detail = excluded.detail;
    end if;
  end loop;
  return jsonb_build_object('on', true, 'apply', p_apply, 'looked_at', v_looked, 'sources_attached', v_sources, 'outcomes', v_tally) || case when p_apply then '{}'::jsonb else jsonb_build_object('would_attach', v_preview) end;
end $function$;
