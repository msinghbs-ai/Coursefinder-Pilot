#!/usr/bin/env bash
# Guards: Boost queue view (Platform Admin decision 18 Nov 2026 07:03) and G4 database-backed tests: migration 20261118080000 runs on an isolated PostgreSQL 16
# (fixtures only, never a Supabase project). It proves: the migration applies twice; the read is Curator and above and writes nothing; Priority score and Country
# tier follow the boost.matrix settings when they change (nothing is stored); the tier, country, lane and state filters, the sorts and the paging.
# The S2 - BOOST functions it calls are stood in for here by small copies that read the same settings; their own behaviour is guarded in S2 - BOOST's fixtures.
# Needs a scratch PostgreSQL 16: PGHOST/PGPORT/PGUSER point at it. Drops its database at the end (ABQ_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${ABQ_DB:-g_admin_boost_queue}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
M=supabase/migrations/20261118080000_cf247_admin_boost_queue_read.sql
trap '[ -n "${ABQ_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; end \$\$"
$P <<'SQL'
create schema pipeline; create schema security; create schema auth; create schema ref; create schema catalogue;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('fixture.uid', true), '')::uuid $$;
create function security.current_role_rank() returns int language sql stable as $$ select nullif(current_setting('fixture.rank', true), '')::int $$;
create table pipeline.platform_toolset_settings (toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric, unit text, sort int, reason text, section text, used_by text, primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$ select coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = p_key), p_default) $$;
create function security.pipeline_list_v1(p_key text, p_default jsonb default '[]'::jsonb) returns text[] language sql stable as $$
  select array(select jsonb_array_elements_text(coalesce((select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = p_key), p_default))) $$;
-- stand-ins for S2 - BOOST's two functions: the same settings, the same arithmetic (country weight x category weight, aliases applied; an unlisted cell is 0)
create function security.boost_lane_category_v1(p_lane text) returns text language sql stable as $$ select split_part(a, '=', 2) from unnest(security.pipeline_list_v1('boost.matrix.lane_categories')) a where split_part(a, '=', 1) = p_lane limit 1 $$;
create function security.boost_country_category_weight_v1(p_country text, p_category text) returns numeric language sql stable as $$
  select coalesce(security.pipeline_num_v1('boost.matrix.country_weight.' || coalesce((select split_part(a, '=', 2) from unnest(security.pipeline_list_v1('boost.matrix.country_aliases')) a where split_part(a, '=', 1) = upper(p_country) limit 1), upper(p_country)), null)
                * security.pipeline_num_v1('boost.matrix.category_weight.' || p_category, null), 0) $$;
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values
  ('pipeline', 'boost.matrix.tier_1', '["AU", "NZ", "CA"]'), ('pipeline', 'boost.matrix.tier_2', '["UK", "IE", "US"]'), ('pipeline', 'boost.matrix.country_aliases', '["GB=UK"]'),
  ('pipeline', 'boost.matrix.lane_categories', '["study_load=intakes_deadlines", "course_fees=fees"]'),
  ('pipeline', 'boost.matrix.country_weight.AU', '100'), ('pipeline', 'boost.matrix.country_weight.NZ', '95'), ('pipeline', 'boost.matrix.country_weight.UK', '50'),
  ('pipeline', 'boost.matrix.category_weight.intakes_deadlines', '0.80'), ('pipeline', 'boost.matrix.category_weight.fees', '0.90');
create table ref.enrichment_categories (category_key text primary key, label text);
insert into ref.enrichment_categories values ('intakes_deadlines', 'Intakes & deadlines'), ('fees', 'Fees');
create table catalogue.courses (id uuid primary key, canonical_title text, display_title text);
create table catalogue.providers (id uuid primary key, canonical_name text, display_name text);
create table pipeline.boost_extract_items (item_key text primary key, lane text, entity text, entity_id uuid, evidence_id uuid, country_code text, state text, batch_id text, result_path text, model_called boolean, cost numeric, note text, claimed_at timestamptz, done_at timestamptz);
create table pipeline.boost_inbound_staging (id bigserial primary key, batch_id text, item_key text, lane text, entity text, entity_id uuid, worker_status text, loaded_at timestamptz, promotion_state text);
create index on pipeline.boost_inbound_staging (entity_id);
insert into catalogue.courses select md5('c' || i)::uuid, 'Course ' || i, case when i = 1 then 'Bachelor of Design' end from generate_series(1, 130) i;
-- 120 Australian study-load items, 5 New Zealand fees items, 3 United Kingdom (as GB) study-load items, 2 from a country in no tier
insert into pipeline.boost_extract_items(item_key, lane, entity, entity_id, country_code, state, batch_id, model_called, cost, done_at)
select 'k' || i, case when i between 121 and 125 then 'course_fees' else 'study_load' end, 'course', md5('c' || i)::uuid,
       case when i <= 120 then 'AU' when i <= 125 then 'NZ' when i <= 128 then 'GB' else 'DE' end,
       case when i % 10 = 0 then 'rejected' else 'verified' end, 'b1', true, 0.001, case when i = 130 then null else now() - (i || ' minutes')::interval end from generate_series(1, 130) i;
insert into pipeline.boost_inbound_staging(batch_id, item_key, lane, entity, entity_id, worker_status, loaded_at, promotion_state)
values ('b0', 'k1', 'study_load', 'course', md5('c1')::uuid, 'failed', now() - interval '2 days', 'refused'), ('b1', 'k1', 'study_load', 'course', md5('c1')::uuid, 'verified', now(), 'shadow');
SQL
$P -1 -f $M >/dev/null; $P -1 -f $M >/dev/null
echo "migration: applied twice without error (post-check included)"
$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
do $t$ declare r jsonb; n0 bigint; begin
  perform pg_temp.ok(pg_temp.err($$select public.admin_boost_queue_read()$$) = 'authentication required', 'no session: refused');
  perform set_config('fixture.uid', '44444444-4444-4444-4444-444444444444', true); perform set_config('fixture.rank', '2', true);
  perform pg_temp.ok(pg_temp.err($$select public.admin_boost_queue_read()$$) like 'Curator (rank 3)%', 'a Counsellor cannot read the Boost queue');
  perform set_config('fixture.rank', '3', true);
  r := public.admin_boost_queue_read();
  perform pg_temp.ok((r->>'total')::int = 130 and (r->>'page_rows')::int = 50 and jsonb_array_length(r->'rows') = 50 and r#>'{tiers,tier_1}' = '["AU", "NZ", "CA"]'::jsonb, 'a Curator reads the queue: 50 rows a page from the setting, with the tier lists');
  -- NZ fees = 95 x 0.90 = 85.5 sorts above AU study load = 100 x 0.80 = 80, then UK (GB by alias) = 50 x 0.80 = 40, then the country in no tier = 0
  perform pg_temp.ok((r#>>'{rows,0,priority_score}')::numeric = 85.5 and r#>>'{rows,0,country_code}' = 'NZ' and (r#>>'{rows,0,country_tier}')::int = 1 and r#>>'{rows,0,category_label}' = 'Fees'
    and (r#>>'{rows,5,priority_score}')::numeric = 80 and r#>>'{rows,5,country_code}' = 'AU', 'Priority score is country weight x category weight; the default order is highest score first');
  r := public.admin_boost_queue_read('{"tier": "2"}');
  perform pg_temp.ok((r->>'total')::int = 3 and (r#>>'{rows,0,priority_score}')::numeric = 40 and r#>>'{rows,0,country_code}' = 'GB' and (r#>>'{rows,0,country_tier}')::int = 2, 'tier 2: GB counts as UK through the alias setting');
  r := public.admin_boost_queue_read('{"tier": "none"}');
  perform pg_temp.ok((r->>'total')::int = 2 and (r#>>'{rows,0,priority_score}')::numeric = 0 and r#>'{rows,0,country_tier}' = 'null'::jsonb, 'a country in neither list has no tier and a score of 0');
  perform pg_temp.ok((public.admin_boost_queue_read('{"tier": "1"}')->>'total')::int = 125 and (public.admin_boost_queue_read('{"country": "nz"}')->>'total')::int = 5
    and (public.admin_boost_queue_read('{"lane": "course_fees"}')->>'total')::int = 5 and (public.admin_boost_queue_read('{"state": "rejected", "tier": "1"}')->>'total')::int = 12, 'tier, country, lane and state filters narrow the queue and combine');
  r := public.admin_boost_queue_read('{"sort": "score", "direction": "asc"}');
  perform pg_temp.ok((r#>>'{rows,0,priority_score}')::numeric = 0 and (r#>>'{rows,2,priority_score}')::numeric = 40, 'the score sort runs both ways');
  perform pg_temp.ok(jsonb_array_length(public.admin_boost_queue_read('{"offset": 100}')->'rows') = 30, 'the last page holds the remainder');
  r := public.admin_boost_queue_read('{"country": "AU", "sort": "done"}');
  perform pg_temp.ok(r#>>'{rows,0,item_key}' = 'k1' and r#>>'{rows,0,title}' = 'Bachelor of Design' and r#>>'{rows,0,promotion_state}' = 'shadow' and r#>>'{rows,0,worker_status}' = 'verified',
    'an item carries its course title and its latest staged answer');
  r := public.admin_boost_queue_read();
  perform pg_temp.ok(jsonb_array_length(r->'summary') = 4 and (r#>>'{summary,0,priority_score}')::numeric = 85.5 and (r#>>'{summary,0,items}')::int = 5
    and (select (s->>'waiting')::int from jsonb_array_elements(r->'summary') s where s->>'country_code' = 'DE') = 1 and r#>'{filters,lanes}' = '["course_fees", "study_load"]'::jsonb,
    'the summary gives each lane and country its tier, score, items and items waiting; the filter values are returned');
  -- nothing is stored: changing a weight or a tier list changes the next read
  select count(*) into n0 from pipeline.boost_extract_items;
  update pipeline.platform_toolset_settings set value = '60' where key = 'boost.matrix.country_weight.UK';
  update pipeline.platform_toolset_settings set value = '["AU", "NZ", "CA", "UK"]' where key = 'boost.matrix.tier_1';
  r := public.admin_boost_queue_read('{"country": "GB"}');
  perform pg_temp.ok((r#>>'{rows,0,priority_score}')::numeric = 48 and (r#>>'{rows,0,country_tier}')::int = 1 and (select count(*) from pipeline.boost_extract_items) = n0, 'a changed weight and tier list show on the next read; the queue table is unchanged');
  update pipeline.platform_toolset_settings set value = to_jsonb(10) where key = 'admin.boost_queue_page_rows';
  perform pg_temp.ok(jsonb_array_length(public.admin_boost_queue_read()->'rows') = 10, 'the page size follows the setting');
  perform pg_temp.ok(pg_temp.err($$select public.admin_boost_queue_read('{"tier": "3"}')$$) = 'tier is 1, 2 or none', 'an unknown tier is refused');
  perform pg_temp.ok(not has_function_privilege('anon', 'public.admin_boost_queue_read(jsonb)', 'execute') and (select provolatile from pg_proc where proname = 'admin_boost_queue_read') = 's', 'anon cannot run it; the function is read-only (stable)');
end $t$;
SQL
echo "admin boost queue: all checks passed"
