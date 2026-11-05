-- Guards: Platform Admin mandate 5 Nov 2026 17:31, Course Catalogue columns: database cases of mandate §10 on the production-representative fixture.
-- Every call runs as role authenticated with the person's JWT subject, the way PostgREST runs it. Each case prints PASS or stops the run.
\set ON_ERROR_STOP on
create or replace function pg_temp.u(text) returns uuid language sql immutable as $$ select md5($1)::uuid $$;
create or replace function pg_temp.ok(c boolean, msg text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL %', msg; end if; raise notice 'PASS %', msg; end $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.u(text) to authenticated;
-- as(person): PostgREST's role and JWT subject for the rest of the transaction
create or replace function pg_temp.page(p_user text, p_args jsonb) returns jsonb language plpgsql as $$
declare r jsonb; begin
  perform set_config('request.jwt.claim.sub', md5(p_user)::uuid::text, true); set local role authenticated;
  r := public.admin_read('courses_page', p_args); reset role; return r; end $$;
create or replace function pg_temp.layout(p_user text, p_action text, p_args jsonb) returns jsonb language plpgsql as $$
declare r jsonb; begin
  perform set_config('request.jwt.claim.sub', coalesce(md5(p_user)::uuid::text, ''), true); set local role authenticated;
  r := public.admin_table_layout(p_action, p_args); reset role; return r; end $$;
create or replace function pg_temp.item(p jsonb, p_id uuid) returns jsonb language sql as $$ select e from jsonb_array_elements(p -> 'items') e where e ->> 'id' = p_id::text $$;
create or replace function pg_temp.fails(p_sql text, p_code text, p_like text) returns boolean language plpgsql as $$
begin execute p_sql; return false; exception when others then return sqlstate = p_code and sqlerrm ilike p_like; end $$;

begin;
-- 1, 4, 5: show and hide, reset, reorder and resize are a saved layout; 2: persisted; 12: any assigned role, own row only
select pg_temp.ok((pg_temp.layout('viewer', 'read', '{"screen": "courses"}') -> 'layout') = 'null'::jsonb, 'a person with no saved layout reads none (default applies)');
select pg_temp.ok(jsonb_array_length(pg_temp.layout('viewer', 'read', '{"screen": "courses"}') -> 'registry') = 40, 'the registry lists the 40 Course catalogue columns');
select pg_temp.ok((pg_temp.layout('viewer', 'read', '{"screen": "courses"}') -> 'limits' ->> 'max_columns')::int = 60, 'limits come from the catalogue_layout settings');
select pg_temp.ok((pg_temp.layout('viewer', 'save', '{"screen": "courses", "layout": {"version": 1, "columns": ["canonical_title", "last_admitted_at", "adapter_state", "city_names"], "widths": {"canonical_title": 280, "city_names": 200}, "sort": "admitted", "direction": "desc"}}') ->> 'saved')::boolean,
  'a Viewer (read-only role) saves its own layout: hidden columns, new order, widths, sort');
select pg_temp.ok(pg_temp.layout('viewer', 'read', '{"screen": "courses"}') -> 'layout' -> 'columns' = '["canonical_title", "last_admitted_at", "adapter_state", "city_names"]', 'the saved order is read back exactly');
select pg_temp.ok((pg_temp.layout('admin', 'read', '{"screen": "courses"}') -> 'layout') = 'null'::jsonb, 'another person''s layout is untouched by the Viewer''s save');
select pg_temp.ok((pg_temp.layout('admin', 'save', '{"screen": "courses", "layout": {"columns": ["canonical_title", "provider_name"], "sort": "course", "direction": "asc"}}') ->> 'saved')::boolean, 'the Platform Admin saves a different layout');
select pg_temp.ok(pg_temp.layout('viewer', 'read', '{"screen": "courses"}') -> 'layout' ->> 'sort' = 'admitted', 'the Viewer''s layout is unchanged by the Platform Admin''s save');
select pg_temp.ok(pg_temp.layout('viewer', 'reset', '{"screen": "courses"}') -> 'layout' = 'null'::jsonb, 'Reset to default clears the layout');
select pg_temp.ok((pg_temp.layout('viewer', 'read', '{"screen": "courses"}') ->> 'has_previous')::boolean, 'after Reset the last saved layout is kept for restore');
select pg_temp.ok(pg_temp.layout('viewer', 'restore', '{"screen": "courses"}') -> 'layout' ->> 'sort' = 'admitted', 'Restore last saved brings the layout back');
select pg_temp.ok(pg_temp.layout('admin', 'read', '{"screen": "courses"}') -> 'layout' -> 'columns' = '["canonical_title", "provider_name"]', 'reset and restore of one person never touch another''s');
-- refusals: registry, always-shown, widths, sort, size, unknown keys, roles
select pg_temp.ok(pg_temp.fails($q$select pg_temp.layout('viewer', 'save', '{"screen": "courses", "layout": {"columns": ["canonical_title", "salary"]}}')$q$, '22023', '%unknown columns%salary%'), 'a column outside the registry is refused');
select pg_temp.ok(pg_temp.fails($q$select pg_temp.layout('viewer', 'save', '{"screen": "courses", "layout": {"columns": ["provider_name"]}}')$q$, '22023', '%always shown%canonical_title%'), 'the course title cannot be hidden');
select pg_temp.ok(pg_temp.fails($q$select pg_temp.layout('viewer', 'save', '{"screen": "courses", "layout": {"columns": ["canonical_title"], "widths": {"canonical_title": 20}}}')$q$, '22023', '%between 160 and 1200%'), 'a width below the column''s readable minimum is refused');
select pg_temp.ok(pg_temp.fails($q$select pg_temp.layout('viewer', 'save', '{"screen": "courses", "layout": {"columns": ["canonical_title", "canonical_title"]}}')$q$, '22023', '%twice%'), 'a column named twice is refused');
select pg_temp.ok(pg_temp.fails($q$select pg_temp.layout('viewer', 'save', '{"screen": "courses", "layout": {"columns": ["canonical_title"], "sort": "salary"}}')$q$, '22023', '%not a sort%'), 'a sort the list does not have is refused');
select pg_temp.ok(pg_temp.fails(format($q$select pg_temp.layout('viewer', 'save', %L)$q$, jsonb_build_object('screen', 'courses', 'layout', jsonb_build_object('columns', '["canonical_title"]'::jsonb, 'version', repeat('x', 17000)))::text), '22023', '%largest size%'), 'a layout over the size setting is refused');
select pg_temp.ok(pg_temp.fails($q$select pg_temp.layout('viewer', 'save', '{"screen": "courses", "layout": {"columns": ["canonical_title"], "owner": "admin"}}')$q$, '22023', '%unknown keys%owner%'), 'a layout cannot carry other keys (no user can be named)');
select pg_temp.ok(pg_temp.fails($q$select pg_temp.layout('viewer', 'read', '{"screen": "providers"}')$q$, '22023', '%unknown screen%'), 'an unknown screen is refused');
select pg_temp.ok(pg_temp.fails($q$select pg_temp.layout('norole', 'read', '{"screen": "courses"}')$q$, '42501', '%role required%'), 'a signed-in person with no role is refused');
select pg_temp.ok(pg_temp.fails($q$select pg_temp.layout(null, 'read', '{"screen": "courses"}')$q$, '42501', '%authentication required%'), 'no session is refused');
select pg_temp.ok(not has_function_privilege('anon', 'public.admin_table_layout(text,jsonb)', 'execute'), 'anon cannot call the layout function');
create or replace function pg_temp.direct_read() returns boolean language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', md5('viewer')::uuid::text, true); set local role authenticated;
  perform count(*) from pipeline.admin_table_layouts; reset role; return false;
exception when insufficient_privilege then reset role; return true; end $$;
select pg_temp.ok(pg_temp.direct_read(), 'the layouts table cannot be read directly, even by a signed-in person');
select pg_temp.ok((select count(*) from pipeline.admin_table_layouts) = 2 and (select count(*) from pipeline.admin_table_layouts where user_id = pg_temp.u('viewer')) = 1, 'one row a person and screen; every row is the caller''s own');
commit;

begin;
-- 7: several cities; never the provider headquarters (Geelong)
select pg_temp.ok(jsonb_array_length(pg_temp.item(pg_temp.page('viewer', '{"query": "Multi-Campus", "lifecycle_status": "active"}'), pg_temp.u('k_multi')) -> 'cities') = 3, 'a course on three campuses lists three campus cities (no repeat for a second delivery mode)');
select pg_temp.ok((select string_agg((c ->> 'city') || ' ' || (c ->> 'subdivision_code'), ', ') from jsonb_array_elements(pg_temp.item(pg_temp.page('viewer', '{"query": "Multi-Campus"}'), pg_temp.u('k_multi')) -> 'cities') c) = 'Melbourne AU-VIC, Richmond AU-NSW, Richmond AU-VIC', 'the same city in two states keeps its state');
select pg_temp.ok(position('Geelong' in pg_temp.page('viewer', '{"query": "Kestrel", "limit": 50}')::text) = 0, 'the provider''s headquarters city is never shown as a course city');
select pg_temp.ok(pg_temp.item(pg_temp.page('viewer', '{"query": "Never Admitted"}'), pg_temp.u('k_unknown')) -> 'cities' = '[]'::jsonb, 'a course with no campus has no city (not the provider''s)');
-- 8: adapter status from the lifecycle and results; Completed never inferred
select pg_temp.ok((select string_agg(e ->> 'stable_key' || '=' || (e -> 'adapter' ->> 'state'), ' ' order by e ->> 'stable_key') from jsonb_array_elements(pg_temp.page('viewer', '{"query": "course:k_", "limit": 50}') -> 'items') e)
  = 'course:k_completed=completed course:k_failed=failed course:k_fresh=completed course:k_held_nopage=held course:k_held_testing=held course:k_multi=held course:k_newest=held course:k_notcfg=not_configured course:k_oldest=held course:k_processing=processing course:k_ready=ready course:k_unknown=held',
  'adapter status per course: completed, failed, held (no page, testing adapter), not configured, processing, ready');
select pg_temp.ok(pg_temp.item(pg_temp.page('viewer', '{"query": "Tern"}'), pg_temp.u('k_held_testing')) -> 'adapter' ->> 'reason' = 'The adapter is testing: its values are not admitted', 'a testing adapter''s course is Held with the reason, even with a result row');
select pg_temp.ok(pg_temp.item(pg_temp.page('viewer', '{"query": "Ready Course"}'), pg_temp.u('k_ready')) -> 'adapter' ->> 'state' = 'ready', 'an admitting adapter with a page and no result yet is Ready, not Completed');
-- 9, 10: last modified and last admitted are separate; nothing fabricated
select pg_temp.ok((pg_temp.item(pg_temp.page('viewer', '{"query": "Modified After"}'), pg_temp.u('k_fresh')) ->> 'last_modified_at')::timestamptz = '2026-11-04 10:00+11', 'Last modified is the record''s own persisted change');
select pg_temp.ok((pg_temp.item(pg_temp.page('viewer', '{"query": "Modified After"}'), pg_temp.u('k_fresh')) ->> 'last_admitted_at')::timestamptz = '2026-10-01 09:00+10',
  'Last data admitted ignores a later skip, review item, retracted fill, unchanged Layer 2 row, unchanged overwrite and scheduled read');
select pg_temp.ok(pg_temp.item(pg_temp.page('viewer', '{"query": "Modified After"}'), pg_temp.u('k_fresh')) -> 'last_admitted' ->> 'field' = 'english', 'the admission names its field and source');
select pg_temp.ok(pg_temp.item(pg_temp.page('viewer', '{"query": "Never Admitted"}'), pg_temp.u('k_unknown')) -> 'last_admitted_at' = 'null'::jsonb, 'with no admission record the value is null (shown as Unknown), never a guessed date');
select pg_temp.ok((pg_temp.item(pg_temp.page('viewer', '{"query": "Kestrel Completed"}'), pg_temp.u('k_completed')) ->> 'last_admitted_at')::timestamptz = '2026-10-20 10:00+11', 'an intake date filled counts; the skipped one after it does not');
-- intakes as the website builds them, and the feeds
select pg_temp.ok((select string_agg(coalesce(x ->> 'month', '-') || '/' || coalesce(x ->> 'year', '-') || '/' || coalesce(x ->> 'start_date', '-') || '/' || coalesce(x ->> 'application_deadline', '-'), ' ') from jsonb_array_elements(pg_temp.item(pg_temp.page('viewer', '{"query": "Kestrel Completed"}'), pg_temp.u('k_completed')) -> 'intakes') x)
  = '2/2027/2027-02-24/2026-12-15 7/2027/-/-', 'intakes: month from the start date or the label, year, start and deadline as held; nothing filled in');
select pg_temp.ok(pg_temp.item(pg_temp.page('viewer', '{"query": "Kestrel Completed"}'), pg_temp.u('k_completed')) -> 'intakes' -> 0 ->> 'start_precision' = 'day', 'the start''s precision comes from the intake-dates record');
select pg_temp.ok(pg_temp.item(pg_temp.page('viewer', '{"query": "Never Admitted"}'), pg_temp.u('k_unknown')) -> 'intakes' = '[]'::jsonb, 'a course with no intake has none (never a made-up one)');
select pg_temp.ok((pg_temp.item(pg_temp.page('viewer', '{"query": "Kestrel Completed"}'), pg_temp.u('k_completed')) -> 'published' ->> 'website_at')::timestamptz = '2026-11-02 10:00+11'
  and pg_temp.item(pg_temp.page('viewer', '{"query": "Kestrel Completed"}'), pg_temp.u('k_completed')) -> 'published' ->> 'zoho_at' is null, 'Last published is the website feed''s last change of the item; no Zoho item, none shown');
select pg_temp.ok((pg_temp.item(pg_temp.page('viewer', '{"query": "Kestrel Failed"}'), pg_temp.u('k_failed')) -> 'published' ->> 'website_removed')::boolean, 'a withdrawn feed item says so');
select pg_temp.ok(pg_temp.item(pg_temp.page('viewer', '{"query": "Never Admitted"}'), pg_temp.u('k_unknown')) -> 'published' = 'null'::jsonb, 'a course with no feed item has no published time');
-- field states
select pg_temp.ok((select string_agg(k || '=' || (v ->> 'state'), ' ' order by k) from jsonb_each(pg_temp.item(pg_temp.page('viewer', '{"query": "Modified After"}'), pg_temp.u('k_fresh')) -> 'field_states') x(k, v))
  = 'deadline=review description=pending english=populated intakes=held official_url=failed provider_tuition=not_applicable', 'field states: populated, pending, review, held, failed, not applicable');
select pg_temp.ok((pg_temp.item(pg_temp.page('viewer', '{"query": "Modified After"}'), pg_temp.u('k_fresh')) ->> 'layer4_open')::int = 1, 'open Layer 4 items are counted');
commit;

begin;
-- 6: server-side sort across pages, over the whole filtered set
select pg_temp.ok((pg_temp.page('viewer', '{"sort": "admitted", "direction": "desc", "lifecycle_status": "active", "limit": 50}') -> 'items' -> 0 ->> 'id')::uuid = pg_temp.u('k_newest'), 'Last data admitted, newest first: the newest admission of 35,700 courses is first on page 1');
select pg_temp.ok((pg_temp.page('viewer', '{"sort": "admitted", "direction": "asc", "lifecycle_status": "active", "limit": 50}') -> 'items' -> 0 ->> 'id')::uuid = pg_temp.u('k_oldest'), 'Last data admitted, oldest first: the oldest is first');
select pg_temp.ok((pg_temp.page('viewer', '{"sort": "admitted", "direction": "desc", "lifecycle_status": "active", "limit": 50}') -> 'items' -> 49 ->> 'last_admitted_at')::timestamptz
  >= (pg_temp.page('viewer', '{"sort": "admitted", "direction": "desc", "lifecycle_status": "active", "limit": 50, "offset": 50}') -> 'items' -> 0 ->> 'last_admitted_at')::timestamptz, 'page 2 continues the order of page 1');
select pg_temp.ok((select bool_and(e -> 'last_admitted_at' = 'null'::jsonb) from jsonb_array_elements(pg_temp.page('viewer', format('{"sort": "admitted", "direction": "desc", "lifecycle_status": "active", "limit": 50, "offset": %s}', (pg_temp.page('viewer', '{"lifecycle_status": "active", "limit": 1}') ->> 'total')::int - 5)::jsonb) -> 'items') e), 'Unknown sorts last');
select pg_temp.ok((pg_temp.page('viewer', '{"sort": "adapter", "direction": "asc", "lifecycle_status": "active", "limit": 50}') -> 'items' -> 0 -> 'adapter' ->> 'state') = 'failed', 'Adapter status sorts attention first (Failed)');
select pg_temp.ok((pg_temp.page('viewer', '{"sort": "adapter", "direction": "desc", "lifecycle_status": "active", "limit": 50}') -> 'items' -> 0 -> 'adapter' ->> 'state') = 'not_configured', 'Adapter status descending ends with Not configured first');
select pg_temp.ok((pg_temp.page('viewer', '{"sort": "modified", "direction": "desc", "lifecycle_status": "active", "limit": 50}') -> 'items' -> 0 ->> 'id')::uuid = pg_temp.u('k_fresh'), 'Last modified, newest first: the course changed on 4 Nov is first');
select pg_temp.ok((pg_temp.page('viewer', '{"sort": "city", "direction": "asc", "query": "Kestrel"}') -> 'items' -> 0 ->> 'id')::uuid = pg_temp.u('k_multi'), 'City sorts on the campus cities');
select pg_temp.ok(pg_temp.page('viewer', '{"sort": "admitted", "direction": "desc", "lifecycle_status": "active"}') ->> 'sort' = 'admitted', 'the page says which sort it applied');
select pg_temp.ok(pg_temp.page('viewer', '{"sort": "fee", "direction": "asc", "limit": 5}') -> 'items' -> 0 ? 'adapter', 'the legacy fee sort path also carries the new columns');
select pg_temp.ok(pg_temp.page('viewer', '{"limit": 5}') ->> 'execution_profile' = 'page_first_unfiltered_v1' and pg_temp.page('viewer', '{"limit": 5}') -> 'items' -> 0 ? 'last_admitted_at', 'the unfiltered first page carries the new columns');
commit;
