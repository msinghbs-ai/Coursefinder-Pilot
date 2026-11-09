-- SELECT-only (no writes), HELD, NOT A MIGRATION: run once after migration 20261110030000 is applied, from a Supabase SQL session (project fxcwkweaxjtknorudmwp) as the
-- database owner. It signs in as a Platform Admin for the length of the statement only (set_config is local to it), then checks the Fill fields change against the live data:
--   1  the Provider Catalogue's filter counts equal the classification counts: for every level, security.admin_providers_page_v3 with the quality filter answers a total equal to
--      security.provider_description_quality_counts_v1, and the four groups (basic, enriched, missing, held) equal the sum of their levels;
--   2  the levels add up to every provider (no provider is left without a level);
--   3  a page with no quality argument still answers the earlier keys of every item (the four earlier pdesc keys are untouched) and the same total as a page asked for all providers;
--   4  the Description sort and the Missing fields sort answer a page, and the whole-set filter and sort each answer in well under 8 seconds (the elapsed milliseconds are reported).
-- The block always ends in an exception that carries the result, so nothing persists. Expected: "mismatches":0 and every "ms" under 8000.
-- Replace the user id below with any current Platform Admin's auth.users id if needed.
do $eq$
declare
  v_counts jsonb; v_classes jsonb; v_out jsonb := '[]'; v_bad int := 0; v_k text; v_tot bigint; v_exp bigint; v_t0 timestamptz; v_ms numeric; v_page jsonb; v_all jsonb;
  v_levels text[] := array['missing','queued','processing','waiting_decision','held','basic_registry','unrecorded','enriched_admitted','consumer_pending','verified_published'];
  v_groups jsonb := '{"basic":["basic_registry"],"enriched":["enriched_admitted","consumer_pending","verified_published"],"missing":["missing"],"held":["held"]}';
  v_g text; v_sum bigint; v_l text;
begin
  perform set_config('request.jwt.claim.sub', 'c2882478-8a06-4cb5-9856-407d29e2fadb', true);
  perform set_config('request.jwt.claims', '{"sub":"c2882478-8a06-4cb5-9856-407d29e2fadb","role":"authenticated"}', true);
  if security.current_role_rank() < 6 then raise exception 'sign in as a Platform Admin: rank is %', security.current_role_rank(); end if;
  v_counts := security.provider_description_quality_counts_v1();
  v_classes := v_counts->'classes';
  -- 1. every level: the page's total equals the count
  foreach v_k in array v_levels loop
    v_t0 := clock_timestamp();
    v_page := security.admin_providers_page_v3(jsonb_build_object('quality', v_k, 'limit', 1));
    v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
    v_tot := (v_page->>'total')::bigint; v_exp := coalesce((v_classes->>v_k)::bigint, 0);
    if v_tot <> v_exp then v_bad := v_bad + 1; end if;
    v_out := v_out || jsonb_build_object('check', 'level', 'quality', v_k, 'page_total', v_tot, 'count', v_exp, 'same', v_tot = v_exp, 'ms', round(v_ms));
  end loop;
  -- the four groups
  for v_g in select jsonb_object_keys(v_groups) loop
    select coalesce(sum(coalesce((v_classes->>x)::bigint, 0)), 0) into v_sum from jsonb_array_elements_text(v_groups->v_g) x;
    v_page := security.admin_providers_page_v3(jsonb_build_object('quality', v_g, 'limit', 1));
    if (v_page->>'total')::bigint <> v_sum then v_bad := v_bad + 1; end if;
    v_out := v_out || jsonb_build_object('check', 'group', 'quality', v_g, 'page_total', (v_page->>'total')::bigint, 'count', v_sum, 'same', (v_page->>'total')::bigint = v_sum);
  end loop;
  -- 2. the levels add up to every provider
  select coalesce(sum(value::bigint), 0) into v_sum from jsonb_each_text(v_classes);
  v_tot := (select count(*) from catalogue.providers);
  if v_sum <> v_tot or (v_counts->>'total')::bigint <> v_tot then v_bad := v_bad + 1; end if;
  v_out := v_out || jsonb_build_object('check', 'all_providers_have_a_level', 'levels_sum', v_sum, 'providers', v_tot, 'same', v_sum = v_tot);
  -- 3. a page with no quality argument keeps the earlier keys and the same total as one asked for everything
  v_page := security.admin_providers_page_v3('{"limit":5}'::jsonb);
  v_all := security.admin_providers_page_v3('{"limit":5,"lifecycle_status":""}'::jsonb);
  if (v_page->>'total') is distinct from (v_all->>'total')
     or exists (select 1 from jsonb_array_elements(v_page->'items') i where not (i->'pdesc' ?& array['description_filled','admission_state','source_tier','reader_state'])) then v_bad := v_bad + 1; end if;
  v_out := v_out || jsonb_build_object('check', 'earlier_keys', 'total', v_page->>'total', 'same', true);
  -- 4. the two new sorts and the whole-set timings
  foreach v_k in array array['quality','missing_fields'] loop
    foreach v_g in array array['asc','desc'] loop
      v_t0 := clock_timestamp();
      v_page := security.admin_providers_page_v3(jsonb_build_object('sort', v_k, 'direction', v_g, 'limit', 50));
      v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
      if jsonb_array_length(v_page->'items') = 0 or v_ms >= 8000 then v_bad := v_bad + 1; end if;
      v_out := v_out || jsonb_build_object('check', 'sort', 'sort', v_k, 'direction', v_g, 'rows', jsonb_array_length(v_page->'items'), 'ms', round(v_ms), 'same', v_ms < 8000);
    end loop;
  end loop;
  raise exception 'EQUIVALENCE {"checks":%, "mismatches":%, "counts":%, "rows":%}', jsonb_array_length(v_out), v_bad, v_counts::text, v_out::text;
end $eq$;
