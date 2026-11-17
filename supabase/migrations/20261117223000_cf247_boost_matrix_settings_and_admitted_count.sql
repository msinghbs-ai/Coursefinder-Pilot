-- CF-247 S2 - BOOST (Platform Admin 17 Nov 2026 21:18, decisions 2 to 5 on the Boost priority matrix and the promotion count).
-- What it does:
--   1. The Boost priority matrix moves to Settings › Pipeline settings (section Boost): one number setting per country weight
--      (boost.matrix.country_weight.<CC>), one per enrichment category weight (boost.matrix.category_weight.<category key>), and four list settings
--      (the two tiers, country aliases, the lane to category map). Each is changed on the screen with a reason, like every other setting.
--   2. The categories are the single list ref.enrichment_categories (migration 20261117213000): Course basics, Fees, Entry requirements,
--      Intakes & deadlines, Campus & location, Provider profile, Recognition & registration, Scholarships. The matrix holds no category list of
--      its own. Lanes: study_load is Intakes & deadlines, course_description is Course basics, course_fees is Fees, aer_entry is Entry
--      requirements, provider_accreditations is Recognition & registration.
--   3. security.boost_country_category_matrix_v1, _weight_v1 and _check_v1 read the settings and the category list. New:
--      security.boost_lane_category_v1(lane), and a deferred check on the settings table that refuses a change to a boost.matrix.* setting which
--      breaks the matrix (a weight below 0, or a tier that no longer outweighs the next).
--   4. The row country_category_boost in pipeline.environment_settings (migration 20261117183000) is kept and marked not applicable: it is no
--      longer read. Per-cell overrides ("cells", which held none) are not carried over.
--   5. security.boost_promote_v1: when one batch holds several verified rows that would fill the same course's study load, only the earliest is
--      admitted; the later ones are refused with a note. Before, each was marked admitted although only the first wrote, so the admitted count
--      overstated (experiment run-1: 352 admitted rows for 60 courses). What is written to the catalogue does not change.
-- The matrix orders Boost work only (decision 4): security.boost_promote_v1 does not read it. No model is qualified. No job changes.
-- G1: no new job. G2: every weight is a setting. G3: no consumer API object is read or changed.
-- Replaces: pipeline.environment_settings row country_category_boost as the store of the Boost priority matrix (kept, marked not applicable)
-- Retires: nothing

set local lock_timeout = '5s';

-- 0. The promotion function is replaced only if it is the one this change was written against
do $g$
begin
  if md5(pg_get_functiondef('security.boost_promote_v1(text,boolean,timestamptz)'::regprocedure)) <> '15be1ce6c5c3e4ae4a3bde0063f6f176' then
    raise exception 'security.boost_promote_v1 is not the definition of migration 20261117163500; re-read it before replacing';
  end if;
  if to_regclass('ref.enrichment_categories') is null then raise exception 'ref.enrichment_categories (migration 20261117213000) is not there'; end if;
end $g$;

-- 1. The settings (Settings › Pipeline settings › Boost)
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
select 'pipeline', 'boost.matrix.country_weight.' || c.cc, 'Boost priority: country weight, ' || c.name,
       'How far ahead Boost works ' || c.name || '. A cell''s weight is this times the category weight; 0 takes the country out of Boost work. Every cell of tier 1 must outweigh every cell of tier 2.',
       'number', to_jsonb(c.w), 0, 100, 'weight', 920 + c.n, 'CF-247 Boost, Platform Admin 17 Nov 2026 18:02 and 21:18', 'Boost',
       'security.boost_country_category_matrix_v1 (Boost queue order)'
  from (values ('AU', 'Australia', 100, 0), ('NZ', 'New Zealand', 95, 1), ('CA', 'Canada', 90, 2), ('UK', 'United Kingdom', 50, 3), ('IE', 'Ireland', 45, 4), ('US', 'United States', 40, 5)) c(cc, name, w, n)
on conflict (toolset_key, key) do nothing;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
select 'pipeline', 'boost.matrix.category_weight.' || k.category_key, 'Boost priority: category weight, ' || k.label,
       'How far ahead Boost works the category ' || k.label || ' within a country. A cell''s weight is the country weight times this; 0 takes the category out of Boost work.',
       'number', to_jsonb(w.w), 0, 1, 'weight (0 to 1)', 930 + (k.sort_order / 10)::int, 'CF-247 Boost, Platform Admin 17 Nov 2026 18:02 and 21:18', 'Boost',
       'security.boost_country_category_matrix_v1 (Boost queue order)'
  from ref.enrichment_categories k
  join (values ('recognition_registration', 1.00), ('campus_location', 0.95), ('fees', 0.90), ('entry_requirements', 0.85), ('intakes_deadlines', 0.80),
               ('course_basics', 0.75), ('provider_profile', 0.70), ('scholarships', 0.65)) w(category_key, w) on w.category_key = k.category_key
on conflict (toolset_key, key) do nothing;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
  ('pipeline', 'boost.matrix.tier_1', 'Boost priority: countries worked first (tier 1)',
   'Every (country, category) cell of these countries must outweigh every cell of the tier 2 countries. A change to a weight that breaks this is refused.',
   'list', '["AU", "NZ", "CA"]'::jsonb, 1, null, 'countries', 940, 'CF-247 Boost, Platform Admin 17 Nov 2026 18:02', 'Boost', 'security.boost_country_category_check_v1'),
  ('pipeline', 'boost.matrix.tier_2', 'Boost priority: countries worked after tier 1 (tier 2)',
   'The countries Boost works after every tier 1 cell.',
   'list', '["UK", "IE", "US"]'::jsonb, 0, null, 'countries', 941, 'CF-247 Boost, Platform Admin 17 Nov 2026 18:02', 'Boost', 'security.boost_country_category_check_v1'),
  ('pipeline', 'boost.matrix.country_aliases', 'Boost priority: country code aliases',
   'Other codes for a country in the matrix, written OTHER=CODE (GB=UK: a provider recorded under GB is weighted as UK). An empty list means no alias.',
   'list', '["GB=UK"]'::jsonb, 0, null, 'aliases', 942, 'CF-247 Boost, Platform Admin 17 Nov 2026 18:02', 'Boost', 'security.boost_country_category_weight_v1'),
  ('pipeline', 'boost.matrix.lane_categories', 'Boost priority: category of each Boost lane',
   'The enrichment category each Boost lane belongs to, written lane=category key. The category keys are those of the enrichment categories list.',
   'list', '["study_load=intakes_deadlines", "course_description=course_basics", "course_fees=fees", "aer_entry=entry_requirements", "provider_accreditations=recognition_registration"]'::jsonb,
   1, null, 'lane=category', 943, 'CF-247 Boost, Platform Admin 17 Nov 2026 21:18 (study_load is Intakes & deadlines; course_description is Course basics)', 'Boost',
   'security.boost_lane_category_v1 (Boost queue order)')
on conflict (toolset_key, key) do nothing;

-- 2. The matrix, in priority order: countries from the settings, categories from the single list
create or replace function security.boost_country_category_matrix_v1()
returns table (country_code text, enrichment_category text, country_weight numeric, category_weight numeric, weight numeric, tier int, priority_rank int)
language sql stable security definer set search_path to '' as $function$
  with st as (select s.key, s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key like 'boost.matrix.%'),
  countries as (select split_part(st.key, '.', 4) as cc, (st.value #>> '{}')::numeric as w from st
                 where st.key like 'boost.matrix.country\_weight.%' and jsonb_typeof(st.value) = 'number'),
  tiers as (select x.cc, min(replace(split_part(st.key, '.', 3), 'tier_', '')::int) as tier
              from st cross join lateral jsonb_array_elements_text(st.value) x(cc)
             where st.key ~ '^boost\.matrix\.tier_[0-9]+$' and jsonb_typeof(st.value) = 'array' group by x.cc),
  cats as (select k.category_key, k.sort_order,
                  coalesce((select (st.value #>> '{}')::numeric from st where st.key = 'boost.matrix.category_weight.' || k.category_key and jsonb_typeof(st.value) = 'number'), 0) as w  -- fixed: a category with no weight is not qualified
             from ref.enrichment_categories k where k.active)
  select c.cc, g.category_key, c.w, g.w, c.w * g.w, t.tier,
         (row_number() over (order by c.w * g.w desc, c.w desc, g.sort_order, c.cc))::int
    from countries c cross join cats g left join tiers t on t.cc = c.cc
   order by 7
$function$;
revoke all on function security.boost_country_category_matrix_v1() from public, anon, authenticated;
grant execute on function security.boost_country_category_matrix_v1() to service_role;
comment on function security.boost_country_category_matrix_v1() is
  'CF-247 Boost (Platform Admin 17 Nov 2026 18:02 and 21:18): every (country, enrichment category) cell with its weight (country weight x category weight), tier and priority rank (1 is worked first). Countries, weights and tiers are the boost.matrix.* settings (Settings › Pipeline settings › Boost); categories are ref.enrichment_categories. Orders Boost work only; admits nothing.';

-- 3. One cell
create or replace function security.boost_country_category_weight_v1(p_country text, p_category text)
returns numeric language sql stable security definer set search_path to '' as $function$
  select coalesce((
    select m.weight from security.boost_country_category_matrix_v1() m
     where m.enrichment_category = p_category
       and m.country_code = coalesce((select split_part(a, '=', 2) from unnest(security.pipeline_list_v1('boost.matrix.country_aliases')) a
                                       where split_part(a, '=', 1) = upper(p_country) limit 1), upper(p_country))), 0)  -- fixed: a cell that is not listed is not qualified
$function$;
revoke all on function security.boost_country_category_weight_v1(text, text) from public, anon, authenticated;
grant execute on function security.boost_country_category_weight_v1(text, text) to service_role;
comment on function security.boost_country_category_weight_v1(text, text) is
  'CF-247 Boost (Platform Admin 17 Nov 2026 18:02 and 21:18): the weight of one (country, enrichment category key) cell of the Boost priority matrix; 0 when the cell is not listed (not qualified for Boost). Country aliases come from the setting boost.matrix.country_aliases.';

-- 4. The category of a Boost lane
create or replace function security.boost_lane_category_v1(p_lane text)
returns text language sql stable security definer set search_path to '' as $function$
  select split_part(a, '=', 2) from unnest(security.pipeline_list_v1('boost.matrix.lane_categories')) a where split_part(a, '=', 1) = p_lane limit 1
$function$;
revoke all on function security.boost_lane_category_v1(text) from public, anon, authenticated;
grant execute on function security.boost_lane_category_v1(text) to service_role;
comment on function security.boost_lane_category_v1(text) is
  'CF-247 Boost (Platform Admin 17 Nov 2026 21:18): the enrichment category key (ref.enrichment_categories) of a Boost lane, from the setting boost.matrix.lane_categories; null when the lane has none.';

-- 5. The check
create or replace function security.boost_country_category_check_v1()
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare v_problems text[] := '{}'; v_notes text[] := '{}'; v_cells int; v_cats int; r record;
begin
  select count(*), count(distinct m.enrichment_category) into v_cells, v_cats from security.boost_country_category_matrix_v1() m;
  if v_cells = 0 then v_problems := v_problems || 'the matrix has no cell: no country weight or no active enrichment category'; end if;
  if exists (select 1 from security.boost_country_category_matrix_v1() m where m.weight < 0) then v_problems := v_problems || 'a weight is below 0'; end if;
  for r in select a.tier as ahead, b.tier as behind, min(a.weight) as lowest_ahead, max(b.weight) as highest_behind
             from security.boost_country_category_matrix_v1() a join security.boost_country_category_matrix_v1() b on a.tier < b.tier
            where a.weight > 0 and b.weight > 0
            group by a.tier, b.tier having min(a.weight) <= max(b.weight) loop
    v_problems := v_problems || format('tier %s (lowest cell %s) does not outweigh tier %s (highest cell %s)', r.ahead, r.lowest_ahead, r.behind, r.highest_behind);
  end loop;
  for r in select a from unnest(security.pipeline_list_v1('boost.matrix.lane_categories')) a
            where a !~ '^[a-z_]+=[a-z_]+$' or not exists (select 1 from ref.enrichment_categories k where k.category_key = split_part(a, '=', 2)) loop
    v_problems := v_problems || format('lane entry %s is not lane=category key of the enrichment categories list', r.a);
  end loop;
  for r in select a from unnest(security.pipeline_list_v1('boost.matrix.country_aliases')) a where a !~ '^[A-Z]{2}=[A-Z]{2}$' loop
    v_problems := v_problems || format('alias %s is not OTHER=CODE in two-letter codes', r.a);
  end loop;
  for r in select distinct m.enrichment_category as c from security.boost_country_category_matrix_v1() m where m.category_weight = 0 loop
    v_notes := v_notes || format('category %s has weight 0: not in Boost work', r.c);
  end loop;
  for r in select distinct m.country_code as c from security.boost_country_category_matrix_v1() m where m.tier is null loop
    v_notes := v_notes || format('country %s is in no tier', r.c);
  end loop;
  return jsonb_build_object('ok', cardinality(v_problems) = 0, 'cells', v_cells, 'categories', v_cats, 'problems', to_jsonb(v_problems), 'notes', to_jsonb(v_notes));
end $function$;
revoke all on function security.boost_country_category_check_v1() from public, anon, authenticated;
grant execute on function security.boost_country_category_check_v1() to service_role;
comment on function security.boost_country_category_check_v1() is
  'CF-247 Boost (Platform Admin 17 Nov 2026 18:02 and 21:18): checks the Boost priority matrix settings: no weight below 0, every cell of an earlier tier outweighing every cell of a later tier, and the lane and alias lists well formed. Returns ok, the cell and category counts, the problems and notes.';

-- 6. A change on the screen that breaks the matrix is refused (checked once, when the change is committed)
create or replace function security.boost_matrix_settings_guard_v1()
returns trigger language plpgsql security definer set search_path to '' as $function$
declare v jsonb := security.boost_country_category_check_v1();
begin
  if not (v->>'ok')::boolean then
    raise exception 'Boost priority matrix not saved: %', (select string_agg(x, '; ') from jsonb_array_elements_text(v->'problems') x) using errcode = '23514';
  end if;
  return null;
end $function$;
revoke all on function security.boost_matrix_settings_guard_v1() from public, anon, authenticated;
comment on function security.boost_matrix_settings_guard_v1() is
  'CF-247 Boost (Platform Admin 17 Nov 2026 21:18): trigger function of boost_matrix_check on pipeline.platform_toolset_settings. Refuses a change to a boost.matrix.* setting that security.boost_country_category_check_v1 does not pass.';
do $t$
begin
  if not exists (select 1 from pg_trigger where tgrelid = 'pipeline.platform_toolset_settings'::regclass and tgname = 'boost_matrix_check') then
    create constraint trigger boost_matrix_check after insert or update on pipeline.platform_toolset_settings
      deferrable initially deferred for each row
      when (new.toolset_key = 'pipeline' and new.key like 'boost.matrix.%')
      execute function security.boost_matrix_settings_guard_v1();
  end if;
end $t$;

-- 7. The old store is kept and marked: it is no longer read
update pipeline.environment_settings
   set status = 'not_applicable', updated_at = now(),
       description = 'No longer read (Platform Admin 17 Nov 2026 21:18). The Boost priority matrix is the boost.matrix.* settings on Settings › Pipeline settings › Boost, over the categories of ref.enrichment_categories (migration 20261117223000). This row keeps the first values of 17 Nov 2026 18:02 for the record.'
 where setting_key = 'country_category_boost';

-- 8. Promotion: one admitted row per course in a batch
create or replace function security.boost_promote_v1(p_batch text, p_dry boolean default true, p_now timestamptz default now())
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
  v_start int := security.pipeline_num_v1('boost.quiet_window_start_hour', 1)::int;
  v_end   int := security.pipeline_num_v1('boost.quiet_window_end_hour', 5)::int;
  v_rows  int := security.pipeline_num_v1('boost.promote_rows_per_run', 1000)::int;
  v_hour  int := extract(hour from (p_now at time zone 'Australia/Melbourne'))::int;
  v_out   jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' and security.current_role_rank() < 6 then
    raise exception 'Platform Admin or service role required';
  end if;
  if not p_dry and not (v_hour >= v_start and v_hour < v_end) then
    raise exception 'outside the Boost quiet window (% to % Melbourne time; now %)', v_start, v_end, v_hour;
  end if;
  perform pg_advisory_xact_lock(hashtext('cf247:boost_promote'));

  create temp table if not exists cf_boost_plan (id bigint primary key, lane text, entity_id uuid, evidence_id uuid, answer jsonb,
    state text, note text) on commit drop;
  truncate cf_boost_plan;

  insert into cf_boost_plan (id, lane, entity_id, evidence_id, answer, state, note)
  select s.id, s.lane, s.entity_id, s.evidence_id, s.answer,
    case
      when s.worker_status <> 'verified' then 'refused'
      when s.lane = 'aer_entry' then 'shadow'
      when q.model is null then 'shadow'
      when s.lane = 'study_load' and (c.study_load is not null
           or exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = s.entity_id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id')))
        then 'refused'
      when s.lane = 'study_load' and s.answer->>'study_load' is null then 'refused'
      when s.lane = 'study_load' then 'admitted'
      else 'proposed' end,
    case
      when s.worker_status <> 'verified' then 'worker: ' || coalesce((select string_agg(x, '; ') from jsonb_array_elements_text(s.verdict->'problems') x), s.worker_status)
      when s.lane = 'aer_entry' then 'AER shadow reading (admitted only by the AER rule after qualification)'
      when q.model is null then 'model not qualified for this lane: ' || coalesce(s.provider, '?') || ' / ' || coalesce(s.model, '?')
      when s.lane = 'study_load' and c.study_load is not null then 'course already holds a study load'
      when s.lane = 'study_load' and exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = s.entity_id
           and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id')) then 'a manual lock holds this course''s study load'
      when s.lane = 'study_load' and s.answer->>'study_load' is null then 'page does not state a study load'
      when s.lane = 'study_load' then null
      when s.lane = 'provider_accreditations' then 'check against the body''s official list (D-3, PR C)'
      else 'for the lane''s own admission rule' end
  from pipeline.boost_inbound_staging s
  left join pipeline.boost_model_qualifications q on q.lane = s.lane and q.provider = s.provider and q.model = s.model
  left join catalogue.courses c on s.lane = 'study_load' and c.id = s.entity_id
  where s.batch_id = p_batch and s.promotion_state = 'staged'
  order by s.id
  limit v_rows;

  -- one admitted row per course and lane: the earliest of the batch; later rows for the same course are refused, so the admitted count is the
  -- number of courses filled (Platform Admin 17 Nov 2026 21:18)
  update cf_boost_plan p
     set state = 'refused', note = 'an earlier row of this batch fills this course''s study load'
   where p.state = 'admitted'
     and exists (select 1 from cf_boost_plan f where f.state = 'admitted' and f.lane = p.lane and f.entity_id = p.entity_id and f.id < p.id);

  if not p_dry then
    -- study_load: only where null, one row per course (the earliest verified row of the batch), updated_at not touched
    update catalogue.courses c
       set study_load = p.answer->>'study_load', study_load_source = 'provider_page', study_load_evidence_id = p.evidence_id
      from (select distinct on (entity_id) * from cf_boost_plan where state = 'admitted' order by entity_id, id) p
     where c.id = p.entity_id and c.study_load is null;
    update pipeline.boost_inbound_staging s set promotion_state = p.state, promotion_note = p.note, promoted_at = p_now
      from cf_boost_plan p where s.id = p.id;
  end if;

  select jsonb_build_object('batch', p_batch, 'dry', p_dry, 'melbourne_hour', v_hour, 'window', jsonb_build_array(v_start, v_end),
           'rows', coalesce(sum(n), 0), 'by_state', coalesce(jsonb_object_agg(state, n) filter (where state is not null), '{}'::jsonb))
    into v_out
    from (select state, count(*) n from cf_boost_plan group by state) x;
  return v_out;
end $function$;

-- 9. The register
insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('function', 'security.boost_lane_category_v1', 'Layer 2', 'Boost', 'The enrichment category of a Boost lane', 'active', '{}', '20261117223000'),
  ('function', 'security.boost_matrix_settings_guard_v1', 'Layer 2', 'Boost', 'Refuses a Boost priority matrix setting change that breaks the matrix', 'active', '{}', '20261117223000')
on conflict do nothing;

-- 10. Post-checks
do $c$
declare v jsonb := security.boost_country_category_check_v1(); v_bad jsonb; v_uk jsonb;
begin
  if not (v->>'ok')::boolean then raise exception 'post-check: the matrix is not valid: %', v->'problems'; end if;
  if (v->>'cells')::int <> (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'boost.matrix.country\_weight.%')
                           * (select count(*) from ref.enrichment_categories where active) or (v->>'cells')::int = 0 then
    raise exception 'post-check: the matrix does not hold one cell for each country and active category (% cells)', v->>'cells';
  end if;
  if exists (select 1 from ref.enrichment_categories k where k.active
              and security.boost_country_category_weight_v1('AU', k.category_key) <= (select max(m.weight) from security.boost_country_category_matrix_v1() m where m.tier > 1)) then
    raise exception 'post-check: AU is not ahead of the second tier in every category';
  end if;
  if security.boost_country_category_weight_v1('GB', 'fees') <> security.boost_country_category_weight_v1('UK', 'fees')
     or security.boost_country_category_weight_v1('UK', 'fees') <= 0 or security.boost_country_category_weight_v1('ZZ', 'fees') <> 0
     or security.boost_country_category_weight_v1('AU', 'tuition_fees') <> 0 then
    raise exception 'post-check: the alias, the not-listed rule or the category keys are not as designed';
  end if;
  if security.boost_lane_category_v1('study_load') is distinct from 'intakes_deadlines' or security.boost_lane_category_v1('course_description') is distinct from 'course_basics'
     or security.boost_lane_category_v1('no_such_lane') is not null then
    raise exception 'post-check: the lane to category map is not as decided';
  end if;
  -- a weight that breaks the tiers is caught by the check (the value is put back at once, inside this transaction)
  select value into v_uk from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'boost.matrix.country_weight.UK';
  update pipeline.platform_toolset_settings set value = (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'boost.matrix.country_weight.AU')
   where toolset_key = 'pipeline' and key = 'boost.matrix.country_weight.UK';
  v_bad := security.boost_country_category_check_v1();
  update pipeline.platform_toolset_settings set value = v_uk where toolset_key = 'pipeline' and key = 'boost.matrix.country_weight.UK';
  if (v_bad->>'ok')::boolean then raise exception 'post-check: a tier 2 weight equal to a tier 1 weight was not caught'; end if;
  if not (security.boost_country_category_check_v1()->>'ok')::boolean then raise exception 'post-check: the matrix was not put back'; end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'pipeline.platform_toolset_settings'::regclass and tgname = 'boost_matrix_check' and tgdeferrable and tginitdeferred) then
    raise exception 'post-check: the deferred matrix check is not on the settings table';
  end if;
  if (select status from pipeline.environment_settings where setting_key = 'country_category_boost') is distinct from 'not_applicable' then
    raise exception 'post-check: the old store is not marked not applicable';
  end if;
  if pg_get_functiondef('security.boost_promote_v1(text,boolean,timestamptz)'::regprocedure) not like '%an earlier row of this batch fills this course%'
     or pg_get_functiondef('security.boost_promote_v1(text,boolean,timestamptz)'::regprocedure) like '%boost_country_category%' then
    raise exception 'post-check: the promotion function is not the corrected one, or it reads the matrix';
  end if;
  if exists (select 1 from pipeline.boost_model_qualifications) then raise exception 'post-check: no model may be qualified by this change'; end if;
  if has_function_privilege('anon', 'security.boost_lane_category_v1(text)', 'execute')
     or has_function_privilege('authenticated', 'security.boost_country_category_matrix_v1()', 'execute') then
    raise exception 'post-check: a Boost matrix function is open to anon or authenticated';
  end if;
end $c$;
