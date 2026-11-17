-- CF-247 S2 - BOOST (Platform Admin 17 Nov 2026 18:02): the Boost country by category priority matrix.
-- What it adds: one row, country_category_boost, in pipeline.environment_settings. It holds a weight for each country and for each of the
-- eight Layer 2/3 enrichment categories (identity_registers, geo_localities, tuition_fees, admissions_entry, intakes_delivery, study_rules,
-- careers_outcomes, scholarships_accred). The weight of a (country, category) cell is country weight x category weight, unless the cell has
-- its own weight under "cells". A cell with weight 0, or a country or category that is not listed, is not qualified for Boost work.
-- Starting values: AU, NZ and CA ahead of UK, IE and US in every category ("tiers", checked by security.boost_country_category_check_v1).
-- What reads it: security.boost_country_category_matrix_v1() (the 48 cells in priority order) and
-- security.boost_country_category_weight_v1(country, category) (one cell). They are for the Boost queue exporter and the Boost experiments,
-- which order and limit their work by them. Nothing else changes: the promotion function security.boost_promote_v1, the gate
-- security.boost_ingest_gate_v1 and the job worker-boost-bulk-ingest are as migration 20261117163500 left them, and no model is qualified.
-- G1: no new job. G2: every weight is in the setting; the functions hold no weight. G3: no consumer API object is read or changed.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

-- 1. The setting
insert into pipeline.environment_settings (setting_key, category, display_name, setting_value, management_mode, environment_scope,
  required_for_production, status, description)
values ('country_category_boost', 'boost', 'Boost priority matrix: country by enrichment category',
  $json${
    "version": 1,
    "categories": ["identity_registers", "geo_localities", "tuition_fees", "admissions_entry", "intakes_delivery", "study_rules", "careers_outcomes", "scholarships_accred"],
    "country_weight": {"AU": 100, "NZ": 95, "CA": 90, "UK": 50, "IE": 45, "US": 40},
    "category_weight": {"identity_registers": 1.00, "geo_localities": 0.95, "tuition_fees": 0.90, "admissions_entry": 0.85,
                        "intakes_delivery": 0.80, "study_rules": 0.75, "careers_outcomes": 0.70, "scholarships_accred": 0.65},
    "cells": {},
    "tiers": [["AU", "NZ", "CA"], ["UK", "IE", "US"]],
    "country_alias": {"GB": "UK"},
    "lane_category": {"study_load": "intakes_delivery", "course_fees": "tuition_fees", "aer_entry": "admissions_entry",
                      "provider_accreditations": "scholarships_accred"}
  }$json$::jsonb,
  'admin_edit', 'per_environment', false, 'configured',
  'Boost (Platform Admin 17 Nov 2026 18:02): the order in which Boost works through (country, enrichment category) cells. Cell weight = country_weight x category_weight, or the cell''s own weight under "cells" (key COUNTRY.category). Weight 0 or not listed = not qualified for Boost. "tiers": every cell of an earlier tier must outweigh every cell of a later tier (security.boost_country_category_check_v1). Read by security.boost_country_category_matrix_v1 and security.boost_country_category_weight_v1. It orders work only: it admits nothing and qualifies no model.')
on conflict (setting_key) do nothing;

-- 2. The matrix, in priority order
create or replace function security.boost_country_category_matrix_v1()
returns table (country_code text, enrichment_category text, country_weight numeric, category_weight numeric, weight numeric, tier int, priority_rank int)
language sql stable security definer set search_path to '' as $function$
  with s as (select setting_value v from pipeline.environment_settings where setting_key = 'country_category_boost'),
  cells as (
    select c.key as country_code, g.category as enrichment_category, (c.value #>> '{}')::numeric as country_weight,
           coalesce((s.v->'category_weight'->>g.category)::numeric, 0) as category_weight,
           coalesce((s.v->'cells'->>(c.key || '.' || g.category))::numeric,
                    (c.value #>> '{}')::numeric * coalesce((s.v->'category_weight'->>g.category)::numeric, 0)) as weight,
           (select min(t.ord)::int from jsonb_array_elements(coalesce(s.v->'tiers', '[]'::jsonb)) with ordinality t(members, ord) where t.members ? c.key) as tier,
           g.ord as category_ord
      from s, jsonb_each(coalesce(s.v->'country_weight', '{}'::jsonb)) c,
           jsonb_array_elements_text(coalesce(s.v->'categories', '[]'::jsonb)) with ordinality g(category, ord))
  select country_code, enrichment_category, country_weight, category_weight, weight, tier,
         (row_number() over (order by weight desc, country_weight desc, category_ord, country_code))::int
    from cells
   order by 7
$function$;
revoke all on function security.boost_country_category_matrix_v1() from public, anon, authenticated;
grant execute on function security.boost_country_category_matrix_v1() to service_role;
comment on function security.boost_country_category_matrix_v1() is
  'CF-247 Boost (Platform Admin 17 Nov 2026 18:02): every (country, enrichment category) cell of the setting country_category_boost with its weight, tier and priority rank (1 is worked first). Orders Boost work only; admits nothing.';

-- 3. One cell
create or replace function security.boost_country_category_weight_v1(p_country text, p_category text)
returns numeric language sql stable security definer set search_path to '' as $function$
  select coalesce((
    select m.weight from security.boost_country_category_matrix_v1() m
     where m.enrichment_category = p_category
       and m.country_code = coalesce((select e.setting_value->'country_alias'->>upper(p_country) from pipeline.environment_settings e
                                       where e.setting_key = 'country_category_boost'), upper(p_country))), 0)  -- fixed: a cell that is not listed is not qualified
$function$;
revoke all on function security.boost_country_category_weight_v1(text, text) from public, anon, authenticated;
grant execute on function security.boost_country_category_weight_v1(text, text) to service_role;
comment on function security.boost_country_category_weight_v1(text, text) is
  'CF-247 Boost (Platform Admin 17 Nov 2026 18:02): the weight of one (country, enrichment category) cell of country_category_boost; 0 when the cell is not listed (not qualified for Boost). Country aliases (GB to UK) come from the setting.';

-- 4. The check of the setting (run by the post-check here and by anyone who edits the setting)
create or replace function security.boost_country_category_check_v1()
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare
  v jsonb; v_problems text[] := '{}'; v_need text[] := array['identity_registers', 'geo_localities', 'tuition_fees', 'admissions_entry',
    'intakes_delivery', 'study_rules', 'careers_outcomes', 'scholarships_accred'];  -- fixed: the eight Layer 2/3 enrichment categories
  v_have text[]; v_cells int; r record;
begin
  select setting_value into v from pipeline.environment_settings where setting_key = 'country_category_boost';
  if v is null then return jsonb_build_object('ok', false, 'problems', jsonb_build_array('the setting country_category_boost is missing')); end if;
  select coalesce(array_agg(x order by x), '{}') into v_have from jsonb_array_elements_text(coalesce(v->'categories', '[]'::jsonb)) x;
  if v_have <> (select array_agg(x order by x) from unnest(v_need) x) then v_problems := v_problems || 'categories are not the eight enrichment categories'; end if;
  if exists (select 1 from unnest(v_need) x where jsonb_typeof(v->'category_weight'->x) is distinct from 'number') then
    v_problems := v_problems || 'a category has no numeric weight'; end if;
  if exists (select 1 from jsonb_each(coalesce(v->'country_weight', '{}'::jsonb)) c where jsonb_typeof(c.value) <> 'number' or c.key !~ '^[A-Z]{2}$') then
    v_problems := v_problems || 'a country weight is not a number, or its code is not two capital letters'; end if;
  if exists (select 1 from jsonb_each(coalesce(v->'cells', '{}'::jsonb)) c where jsonb_typeof(c.value) <> 'number'
              or split_part(c.key, '.', 2) <> all (v_need) or not (coalesce(v->'country_weight', '{}'::jsonb) ? split_part(c.key, '.', 1))) then
    v_problems := v_problems || 'a cell override is not COUNTRY.category with a numeric weight'; end if;
  if cardinality(v_problems) = 0 then
    if exists (select 1 from security.boost_country_category_matrix_v1() m where m.weight < 0) then v_problems := v_problems || 'a weight is below 0'; end if;
    for r in select a.tier as ahead, b.tier as behind, min(a.weight) as lowest_ahead, max(b.weight) as highest_behind
               from security.boost_country_category_matrix_v1() a join security.boost_country_category_matrix_v1() b on a.tier < b.tier
              group by a.tier, b.tier having min(a.weight) <= max(b.weight) loop
      v_problems := v_problems || format('tier %s (lowest cell %s) does not outweigh tier %s (highest cell %s)', r.ahead, r.lowest_ahead, r.behind, r.highest_behind);
    end loop;
  end if;
  select count(*) into v_cells from security.boost_country_category_matrix_v1();
  return jsonb_build_object('ok', cardinality(v_problems) = 0, 'cells', v_cells, 'problems', to_jsonb(v_problems));
end $function$;
revoke all on function security.boost_country_category_check_v1() from public, anon, authenticated;
grant execute on function security.boost_country_category_check_v1() to service_role;
comment on function security.boost_country_category_check_v1() is
  'CF-247 Boost (Platform Admin 17 Nov 2026 18:02): checks the setting country_category_boost: the eight categories, numeric weights, none below 0, and every cell of an earlier tier outweighing every cell of a later tier. Returns ok, the cell count and the problems.';

-- 5. The register
insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('function', 'security.boost_country_category_matrix_v1', 'Layer 2', 'Boost', 'The Boost (country, enrichment category) cells in priority order', 'active', '{}', '20261117183000'),
  ('function', 'security.boost_country_category_weight_v1', 'Layer 2', 'Boost', 'The Boost weight of one (country, enrichment category) cell', 'active', '{}', '20261117183000'),
  ('function', 'security.boost_country_category_check_v1', 'Layer 2', 'Boost', 'Checks the Boost priority matrix setting', 'active', '{}', '20261117183000')
on conflict do nothing;

-- 6. Post-checks
do $c$
declare v jsonb := security.boost_country_category_check_v1();
begin
  if not (v->>'ok')::boolean then raise exception 'post-check: the matrix is not valid: %', v->'problems'; end if;
  if (v->>'cells')::int <> (select count(*) * 8 from jsonb_object_keys((select setting_value->'country_weight' from pipeline.environment_settings where setting_key = 'country_category_boost'))) then
    raise exception 'post-check: the matrix does not hold eight cells for each country';
  end if;
  if security.boost_country_category_weight_v1('AU', 'identity_registers') <= security.boost_country_category_weight_v1('UK', 'identity_registers')
     or security.boost_country_category_weight_v1('CA', 'scholarships_accred') <= security.boost_country_category_weight_v1('UK', 'identity_registers') then
    raise exception 'post-check: AU, NZ and CA are not ahead of UK, IE and US';
  end if;
  if security.boost_country_category_weight_v1('GB', 'tuition_fees') <> security.boost_country_category_weight_v1('UK', 'tuition_fees')
     or security.boost_country_category_weight_v1('ZZ', 'tuition_fees') <> 0 then
    raise exception 'post-check: the alias or the not-listed rule is not as designed';
  end if;
  if exists (select 1 from pipeline.boost_model_qualifications) then raise exception 'post-check: no model may be qualified by this change'; end if;
  if has_function_privilege('anon', 'security.boost_country_category_matrix_v1()', 'execute')
     or has_function_privilege('authenticated', 'security.boost_country_category_weight_v1(text, text)', 'execute') then
    raise exception 'post-check: a Boost matrix function is open to anon or authenticated';
  end if;
end $c$;
