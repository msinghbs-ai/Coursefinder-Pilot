#!/usr/bin/env bash
# Guards: UI audit Phase 5 first slice (Platform Admin 18 Nov 2026 09:30 and 10:09; decisions of 16 Nov 2026 05:12) and G4 database-backed tests:
# migration 20261118120000 runs on an isolated PostgreSQL 16 (fixtures only, never a Supabase project). It proves: the migration applies twice; the grid
# is Curator and above; the three shared views are seeded and only a Platform Admin changes them, with a reason; personal views are their owner's
# alone, capped by the setting, and archived (never deleted); the filters (kind, field code, hold reason, university, search, age), sorts and paging;
# the page size follows its setting; the drawer gives quote and value pairs, the evidence link and the decision history; the grid writes no item.
# security.layer4_inbox_items_v2 and security.layer4_inbox_kinds_v1 are stood in for by small copies with the same signature; their own behaviour is
# guarded by the Layer 4 Inbox fixtures.
# Needs a scratch PostgreSQL 16: PGHOST/PGPORT/PGUSER point at it. Drops its database at the end (P5G_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${P5G_DB:-g_phase5_review_grid}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
M=$(bash -c 'source tests/fixtures/lib/migration-path.sh; migpath 20261118120000_cf247_phase5_review_grid_saved_views')
trap '[ -n "${P5G_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; end \$\$"
$P <<'SQL'
create schema pipeline; create schema security; create schema auth; create schema catalogue; create schema fixture;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('fixture.uid', true), '')::uuid $$;
create function security.current_role_rank() returns int language sql stable as $$ select nullif(current_setting('fixture.rank', true), '')::int $$;
create table pipeline.platform_toolset_settings (toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric, unit text, sort int, reason text, section text, used_by text, primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$ select coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = p_key), p_default) $$;
create table pipeline.admin_control_events (id bigserial primary key, area text, action text, target text, detail jsonb, actor uuid, created_at timestamptz default now());
create table pipeline.component_register (kind text, name text, layer text, area text, purpose text, status text, replaces text[], introduced_in text);
create table pipeline.layer4_review_items (id uuid primary key, field_code text, status text, created_at timestamptz, decided_at timestamptz, claimed_at timestamptz);
create table catalogue.providers (id uuid primary key, canonical_name text, display_name text);
insert into catalogue.providers values (md5('p1')::uuid, 'University One', null), (md5('p2')::uuid, 'Zed Institute', 'Zed Institute of Technology');
create function security.layer4_inbox_kinds_v1() returns jsonb language sql stable as $$
  select '{"aer_review": {"label": "Entry requirements", "order": 1}, "course_link": {"label": "Course link", "order": 2}, "site_down": {"label": "Website not answering", "order": 9}, "website_needed": {"label": "Website needed", "order": 8}}'::jsonb $$;
create table fixture.items (kind text, ref text, provider_id uuid, subject text, why text, suggestion text, created_at timestamptz, detail jsonb);
-- 60 AER reads (20 held as the audit sample), 30 course links (12 official URL proposals), 3 provider blockers
insert into fixture.items select 'aer_review', md5('a' || i)::uuid::text, case when i % 2 = 0 then md5('p1')::uuid else md5('p2')::uuid end, 'Bachelor of Course ' || i,
  'Machine rule aer-machine-v1 did not admit this: ' || case when i <= 20 then 'audit_sample' else 'gate_incomplete' end || '. Course entry requirements first read',
  null, now() - (i || ' days')::interval,
  jsonb_build_object('field_code', 'course_entry_first_read', 'source_url', 'https://one.example/c' || i, 'evidence_id', md5('e' || i)::uuid,
    'proposed', jsonb_build_object('url', 'https://one.example/c' || i, 'rows', 2, 'sample', jsonb_build_array(
      jsonb_build_object('kind', 'minimum_grade', 'audience', 'domestic', 'description', 'ATAR 83.70', 'quote', 'Entry score: ATAR 83.70'),
      jsonb_build_object('kind', 'english', 'description', 'IELTS 6.5', 'quote', ''))))
  from generate_series(1, 60) i;
insert into fixture.items select 'course_link', md5('l' || i)::uuid::text, md5('p1')::uuid, 'Master of Link ' || i, 'Needs a decision', null, now() - (i || ' hours')::interval,
  jsonb_build_object('field_code', case when i <= 12 then 'official_course_url' else 'provider_current_tuition_validation' end, 'proposed', case when i <= 12 then jsonb_build_object('course_url', 'https://one.example/m' || i) else jsonb_build_object('amount', 250) end)
  from generate_series(1, 30) i;
insert into fixture.items values ('site_down', '101', md5('p2')::uuid, 'Zed Institute', 'Website not answering for 31 days', null, now() - interval '40 days', '{"flag_id": 101, "evidence": {"quote": "502 Bad Gateway"}}'),
  ('website_needed', '102', md5('p1')::uuid, 'University One', 'No website held', null, now() - interval '3 days', '{}'), ('fee_check', '103', md5('p1')::uuid, 'University One', 'Fee check', null, now(), '{}');
insert into pipeline.layer4_review_items select md5('a1')::uuid, 'course_entry_first_read', 'open', now() - interval '1 day', null, null;
insert into pipeline.admin_control_events(area, action, target, detail, actor, created_at) values
  ('layer4', 'rule_execute', md5('a1')::uuid::text, '{"rule": "aer-machine-v1", "note": "held: audit_sample"}', null, now() - interval '20 hours'),
  ('layer4', 'inbox_decide', 'aer_review:' || md5('a1')::uuid::text, '{"choice": "keep", "reason": "checked against the page"}', md5('u9')::uuid, now() - interval '2 hours'),
  ('layer4', 'inbox_decide', 'aer_review:' || md5('a2')::uuid::text, '{"choice": "keep"}', md5('u9')::uuid, now());
create function security.layer4_inbox_items_v2(p_provider_id uuid default null, p_kind text default null, p_keys text[] default null, p_detail boolean default true)
 returns table(kind text, ref text, provider_id uuid, subject text, why text, suggestion text, created_at timestamptz, detail jsonb) language sql stable as $$
  select i.kind, i.ref, i.provider_id, i.subject, i.why, i.suggestion, i.created_at, case when p_detail then i.detail end from fixture.items i
   where (p_provider_id is null or i.provider_id = p_provider_id) and (p_kind is null or i.kind = p_kind) and (p_keys is null or i.kind || ':' || i.ref = any (p_keys)) $$;
SQL
$P -1 -f $M >/dev/null; $P -1 -f $M >/dev/null
echo "migration: applied twice without error (post-check included)"
$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
do $t$ declare r jsonb; v jsonb; aer uuid; url uuid; blk uuid; mine uuid; n0 bigint; i int; begin
  perform pg_temp.ok(pg_temp.err($$select public.admin_review_grid('views')$$) = 'authentication required', 'no session: refused');
  perform set_config('fixture.uid', md5('u1')::uuid::text, true); perform set_config('fixture.rank', '2', true);
  perform pg_temp.ok(pg_temp.err($$select public.admin_review_grid('views')$$) like 'Curator (rank 3)%', 'below Curator: refused');
  perform set_config('fixture.rank', '3', true);
  v := public.admin_review_grid('views');
  perform pg_temp.ok(jsonb_array_length(v->'views') = 3 and v#>>'{views,0,name}' = 'AER Audit Samples' and v#>>'{views,1,name}' = 'Official URLs' and v#>>'{views,2,name}' = 'Provider Blockers'
    and (v->>'can_edit_shared')::boolean = false and (v->>'personal_max')::int = 25 and v#>>'{kinds,0,kind}' = 'aer_review', 'a Curator sees the three shared views in order, cannot edit them, and gets the kind labels');
  select (x->>'id')::uuid into aer from jsonb_array_elements(v->'views') x where x->>'view_key' = 'aer_audit_samples';
  select (x->>'id')::uuid into url from jsonb_array_elements(v->'views') x where x->>'view_key' = 'official_urls';
  select (x->>'id')::uuid into blk from jsonb_array_elements(v->'views') x where x->>'view_key' = 'provider_blockers';
  r := public.admin_review_grid('rows', jsonb_build_object('view_id', aer));
  perform pg_temp.ok((r->>'total')::int = 20 and jsonb_array_length(r->'rows') = 20 and r#>>'{rows,0,kind_label}' = 'Entry requirements' and (r#>>'{rows,0,quotes}')::int = 1
    and r#>>'{rows,0,source_url}' like 'https://one.example/c%' and r#>>'{rows,0,provider}' is not null, 'AER Audit Samples: only the 20 audit-sample reads, with label, quote count, source link and university');
  perform pg_temp.ok((r#>>'{rows,0,age_days}')::int >= (r#>>'{rows,19,age_days}')::int, 'the default order is oldest first');
  r := public.admin_review_grid('rows', jsonb_build_object('view_id', url));
  perform pg_temp.ok((r->>'total')::int = 12 and r#>>'{rows,0,field_code}' = 'official_course_url' and r->>'sort' = 'provider' and r#>>'{rows,0,source_url}' like 'https://one.example/m%', 'Official URLs: only the 12 official URL proposals, sorted by university as the view says');
  r := public.admin_review_grid('rows', jsonb_build_object('view_id', blk));
  perform pg_temp.ok((r->>'total')::int = 2 and r#>>'{rows,0,kind}' = 'site_down', 'Provider Blockers: the provider-level kinds only (a fee check is not a blocker)');
  r := public.admin_review_grid('rows');
  perform pg_temp.ok((r->>'total')::int = 93 and jsonb_array_length(r->'rows') = 50 and (r->>'page_rows')::int = 50, 'no filter: every item, 50 a page from the setting');
  perform pg_temp.ok(jsonb_array_length(public.admin_review_grid('rows', '{"offset": 50}')->'rows') = 43, 'the last page holds the remainder');
  perform pg_temp.ok((public.admin_review_grid('rows', '{"limit": 9999}')->>'page_rows')::int = 200, 'a page larger than the most allowed is cut to the setting');
  perform pg_temp.ok((public.admin_review_grid('rows', jsonb_build_object('filters', jsonb_build_object('provider_id', md5('p2')::uuid, 'kinds', jsonb_build_array('aer_review'))))->>'total')::int = 30, 'university and kind filters combine');
  perform pg_temp.ok((public.admin_review_grid('rows', '{"filters": {"q": "zed institute"}}')->>'total')::int = 31, 'search reads the title, the reason and the university name');
  perform pg_temp.ok((public.admin_review_grid('rows', '{"filters": {"older_than_days": 35}}')->>'total')::int = 27, 'age filter: items waiting more than the days given');
  perform pg_temp.ok((public.admin_review_grid('rows', '{"filters": {"kinds": ["no such kind!"], "junk": 1}}')->>'total')::int = 93
    and public.admin_review_grid('rows', '{"filters": {"kinds": ["no such kind!"], "junk": 1}}')->'filters' = '{}'::jsonb, 'unknown filter keys and malformed values are dropped, never run');
  r := public.admin_review_grid('rows', '{"sort": "subject", "direction": "desc", "filters": {"kinds": ["course_link"]}}');
  perform pg_temp.ok(r#>>'{rows,0,subject}' = 'Master of Link 9' and r->>'direction' = 'desc', 'sorting by title runs both ways');
  -- the drawer: quote beside value, evidence, history
  r := public.admin_review_grid('drawer', jsonb_build_object('kind', 'aer_review', 'ref', md5('a1')::uuid));
  perform pg_temp.ok(r#>>'{pairs,0,quote}' = 'Entry score: ATAR 83.70' and r#>>'{pairs,0,value}' = 'ATAR 83.70' and (r->>'pairs_total')::int = 1, 'drawer: the saved page quote beside the value taken from it; an empty quote is not shown as one');
  perform pg_temp.ok(r#>>'{evidence,source_url}' = 'https://one.example/c1' and r#>>'{evidence,evidence_id}' = md5('e1')::uuid::text and r#>>'{review,status}' = 'open', 'drawer: the evidence link and the review item state');
  perform pg_temp.ok(jsonb_array_length(r->'history') = 2 and r#>>'{history,0,by}' = 'person' and r#>>'{history,0,reason}' = 'checked against the page' and r#>>'{history,1,by}' = 'rule', 'drawer: the decision history, newest first, a person and a rule told apart, and no other item''s events');
  perform pg_temp.ok((public.admin_review_grid('drawer', '{"kind": "site_down", "ref": "101"}')#>>'{pairs,0,quote}') = '502 Bad Gateway', 'drawer: a flag''s saved evidence quote shows too');
  perform pg_temp.ok(pg_temp.err($$select public.admin_review_grid('drawer', '{"kind": "aer_review", "ref": "gone"}')$$) = 'that item no longer waits for a person', 'drawer: a decided item is reported, not guessed');
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where key = 'layer4.grid_history_rows';
  perform pg_temp.ok(jsonb_array_length(public.admin_review_grid('drawer', jsonb_build_object('kind', 'aer_review', 'ref', md5('a1')::uuid))->'history') = 1, 'drawer: history rows follow the setting');
  -- shared views: Platform Admin only, with a reason
  perform pg_temp.ok(pg_temp.err(format($$select public.admin_review_grid('view_save', '{"id": "%s", "name": "Mine now"}')$$, aer)) like 'only a Platform Admin%', 'a Curator cannot change a shared view');
  perform pg_temp.ok(pg_temp.err($$select public.admin_review_grid('view_save', '{"name": "New shared", "scope": "shared"}')$$) like 'shared views are the three defaults%', 'nobody adds a fourth shared view through the grid');
  perform set_config('fixture.rank', '6', true);
  perform pg_temp.ok(pg_temp.err(format($$select public.admin_review_grid('view_save', '{"id": "%s", "name": "Official URLs"}')$$, url)) = 'a reason is needed to change a shared view', 'a Platform Admin gives a reason');
  perform public.admin_review_grid('view_save', jsonb_build_object('id', url, 'name', 'Official URLs', 'reason', 'oldest first', 'filters', jsonb_build_object('kinds', jsonb_build_array('course_link'), 'field_codes', jsonb_build_array('official_course_url')), 'sort', jsonb_build_object('key', 'created_at', 'direction', 'asc')));
  perform pg_temp.ok((public.admin_review_grid('views')->>'can_edit_shared')::boolean and (select reason from pipeline.saved_views where id = url) = 'oldest first'
    and exists (select 1 from pipeline.admin_control_events where action = 'saved_view_save' and target = 'saved_view:' || url and detail->>'reason' = 'oldest first'), 'a Platform Admin changes a shared view with a reason, and the change is logged');
  -- personal views: the owner's alone, capped, archived not deleted
  perform set_config('fixture.rank', '3', true);
  mine := (public.admin_review_grid('view_save', '{"name": "My Zed reads", "filters": {"kinds": ["aer_review"], "q": "zed"}}')->>'id')::uuid;
  perform pg_temp.ok((public.admin_review_grid('rows', jsonb_build_object('view_id', mine))->>'total')::int = 30 and jsonb_array_length(public.admin_review_grid('views')->'views') = 4, 'a personal view is saved and filters the grid');
  perform pg_temp.ok(pg_temp.err($$select public.admin_review_grid('view_save', '{"name": "my zed READS"}')$$) = 'you already have a view with that name', 'personal view names are unique per person');
  perform set_config('fixture.uid', md5('u2')::uuid::text, true);
  perform pg_temp.ok(jsonb_array_length(public.admin_review_grid('views')->'views') = 3 and pg_temp.err(format($$select public.admin_review_grid('rows', '{"view_id": "%s"}')$$, mine)) = 'that view was not found'
    and pg_temp.err(format($$select public.admin_review_grid('view_archive', '{"id": "%s"}')$$, mine)) = 'that view was not found', 'another person neither sees, uses nor archives it');
  update pipeline.platform_toolset_settings set value = to_jsonb(2) where key = 'layer4.saved_views_per_user';
  perform public.admin_review_grid('view_save', '{"name": "a"}'); perform public.admin_review_grid('view_save', '{"name": "b"}');
  perform pg_temp.ok(pg_temp.err($$select public.admin_review_grid('view_save', '{"name": "c"}')$$) like 'you already keep the most personal views allowed%', 'personal views are capped by the setting');
  perform set_config('fixture.uid', md5('u1')::uuid::text, true);
  select count(*) into n0 from pipeline.saved_views;
  perform public.admin_review_grid('view_archive', jsonb_build_object('id', mine));
  perform pg_temp.ok((select count(*) from pipeline.saved_views) = n0 and (select archived_at is not null from pipeline.saved_views where id = mine) and jsonb_array_length(public.admin_review_grid('views')->'views') = 3, 'archiving keeps the row and hides the view');
  perform pg_temp.ok(pg_temp.err($$select public.admin_review_grid('view_save', '{"name": ""}')$$) like 'a view needs a name%' and pg_temp.err($$select public.admin_review_grid('nothing')$$) = 'unknown action nothing', 'empty names and unknown actions are refused');
  perform pg_temp.ok((select count(*) from fixture.items) = 93 and (select count(*) from pipeline.layer4_review_items) = 1, 'the grid wrote no item');
  perform pg_temp.ok(not has_function_privilege('anon', 'public.admin_review_grid(text,jsonb)', 'execute') and has_function_privilege('authenticated', 'public.admin_review_grid(text,jsonb)', 'execute')
    and not has_table_privilege('authenticated', 'pipeline.saved_views', 'select') and (select relrowsecurity from pg_class where oid = 'pipeline.saved_views'::regclass), 'saved views are reached only through the function; anon cannot run it');
  perform pg_temp.ok((select count(*) from pipeline.component_register where area = 'Review grid') = 4 and (select count(*) from pipeline.platform_toolset_settings where used_by = 'public.admin_review_grid') = 5, 'register rows and settings are present once');
end $t$;
SQL
echo "phase 5 review grid: all checks passed"
