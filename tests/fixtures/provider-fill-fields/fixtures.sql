-- Guards: Fill fields (Platform Admin 9-10 Nov 2026) and G4 database-backed tests: behaviour of the Fill fields migration on isolated fixtures. Every assertion prints "ok: <what>" or raises.
\set ON_ERROR_STOP on
set fx.uid = '90000000-0000-0000-0000-0000000000aa';
set fx.rank = '6';

create function pg_temp.id(p_name text) returns uuid language sql as $$ select id from public.fx_names where name = p_name $$;
create function pg_temp.ok(p_label text, p_cond boolean) returns void language plpgsql as $$ begin if p_cond is not true then raise exception 'FAILED: %', p_label; end if; raise notice 'ok: %', p_label; end $$;
create function pg_temp.strip(j jsonb) returns jsonb language sql as $$
  select jsonb_set(j, '{items}', coalesce((select jsonb_agg(i #- '{pdesc,quality}' #- '{pdesc,website_publication}' #- '{pdesc,zoho_publication}' #- '{pdesc,missing_fields}' order by o) from jsonb_array_elements(j->'items') with ordinality t(i, o)), '[]'::jsonb)) $$;
create function pg_temp.rpc(p_action text, p_args jsonb default '{}') returns jsonb language sql as $$ select public.admin_provider_description_run_v1(p_action, p_args) $$;
create function pg_temp.cls(p_name text) returns text language sql as $$ select quality_class from security.provider_description_quality_v1(array[pg_temp.id(p_name)], true) $$;

-- 1. the level of each named provider
select pg_temp.ok('missing: no description, no read', pg_temp.cls('missing-one') = 'missing');
select pg_temp.ok('a manual lock does not change the level: still missing', pg_temp.cls('locked-one') = 'missing');
select pg_temp.ok('queued read is Enrichment queued', pg_temp.cls('queued-one') = 'queued');
select pg_temp.ok('reading read is Enrichment processing', pg_temp.cls('reading-one') = 'processing');
select pg_temp.ok('proposed with a pending Layer 4 item is Waiting for human decision', pg_temp.cls('proposed-one') = 'waiting_decision');
select pg_temp.ok('a held read is Held', pg_temp.cls('held-one') = 'held');
select pg_temp.ok('a declined machine admission is Held', pg_temp.cls('declined-one') = 'held');
select pg_temp.ok('registry facts admission is Basic registry profile', pg_temp.cls('basic-one') = 'basic_registry' and pg_temp.cls('basic-current') = 'basic_registry');
select pg_temp.ok('stored page admission with both feeds matching is Verified published', pg_temp.cls('verified-one') = 'verified_published');
select pg_temp.ok('Website matched and Zoho not applicable is Verified published (not applicable is not a failure)', pg_temp.cls('webonly-one') = 'verified_published');
select pg_temp.ok('Website holds older text and Zoho has no item is Consumer publication pending', pg_temp.cls('pending-one') = 'consumer_pending');
select pg_temp.ok('admitted with both consumers not applicable stays Enriched and admitted', pg_temp.cls('nocourses-one') = 'enriched_admitted');
select pg_temp.ok('a description with no admission record is shown as such, never as enriched', pg_temp.cls('unrecorded-one') = 'unrecorded');
select pg_temp.ok('without the feeds worked out an enriched provider has no level (Unknown, not a guess)',
  (select quality_class from security.provider_description_quality_v1(array[pg_temp.id('verified-one')], false)) is null
  and (select quality_class from security.provider_description_quality_v1(array[pg_temp.id('basic-one')], false)) = 'basic_registry');
select pg_temp.ok('per consumer verdicts', (select website_publication || '/' || coalesce(zoho_publication, '-') from security.provider_description_quality_v1(array[pg_temp.id('webonly-one')], true)) = 'verified/not_applicable'
  and (select website_publication || '/' || zoho_publication from security.provider_description_quality_v1(array[pg_temp.id('pending-one')], true)) = 'pending/pending');
select pg_temp.ok('missing fields are listed (informational)', (select 'description' = any(missing_fields) and 'phone' = any(missing_fields) and not 'website' = any(missing_fields) from security.provider_description_quality_v1(array[pg_temp.id('missing-one')], true)));

-- 2. live counts
select pg_temp.ok('counts by level add up to every provider', (security.provider_description_quality_counts_v1()->>'total')::int = (select count(*) from catalogue.providers)
  and (select sum(v::int) from jsonb_each_text(security.provider_description_quality_counts_v1()->'classes') e(k, v)) = (select count(*) from catalogue.providers));
select pg_temp.ok('counts: missing 2002, queued 1, processing 1, waiting 1, held 2, basic 2, unrecorded 1, enriched 1, pending 1, verified 2',
  security.provider_description_quality_counts_v1()->'classes' = '{"missing":2002,"queued":1,"processing":1,"waiting_decision":1,"held":2,"basic_registry":2,"unrecorded":1,"enriched_admitted":1,"consumer_pending":1,"verified_published":2}'::jsonb);

-- 3. the snapshot table: written only by the refresh; class_since moves only when the level changes
select pg_temp.ok('the snapshot starts empty', (select count(*) from pipeline.provider_description_quality) = 0);
create temp table r1 as select security.provider_description_quality_refresh_v1() j;
select pg_temp.ok('a refresh with no ids classifies every provider (one statement, no limit setting)', (select (j->>'refreshed')::int from r1) = (select count(*) from catalogue.providers)
  and (select count(*) from pipeline.provider_description_quality) = (select count(*) from catalogue.providers));
create temp table since as select provider_id, class_since from pipeline.provider_description_quality;
create temp table r2 as select security.provider_description_quality_refresh_v1() j;
select pg_temp.ok('a second refresh keeps class_since where the level has not changed', (select count(*) from pipeline.provider_description_quality q join since s using (provider_id) where q.class_since <> s.class_since) = 0);
update catalogue.providers set description = 'A hand written description.' where id = pg_temp.id('missing-one');
create temp table r3 as select security.provider_description_quality_refresh_v1(array[pg_temp.id('missing-one')]) j;
select pg_temp.ok('after a change the refresh moves class_since for that provider only', (select (j->>'refreshed')::int from r3) = 1
  and (select q.quality_class = 'unrecorded' and q.class_since > s.class_since from pipeline.provider_description_quality q join since s using (provider_id) where provider_id = pg_temp.id('missing-one'))
  and (select count(*) from pipeline.provider_description_quality q join since s using (provider_id) where q.class_since <> s.class_since) = 1);
update catalogue.providers set description = null where id = pg_temp.id('missing-one');
select pg_temp.ok('the counts carry the snapshot rows and their age, with no staleness limit of their own', (security.provider_description_quality_counts_v1()->'snapshot') ? 'oldest'
  and not (security.provider_description_quality_counts_v1()->'snapshot') ? 'stale_after_minutes' and not (security.provider_description_quality_counts_v1()->'snapshot') ? 'old');
select pg_temp.ok('the snapshot table is not readable by the API roles and has row level security', not has_table_privilege('authenticated', 'pipeline.provider_description_quality', 'select')
  and not has_table_privilege('anon', 'pipeline.provider_description_quality', 'select') and not has_table_privilege('authenticated', 'pipeline.provider_description_quality', 'insert')
  and (select relrowsecurity from pg_class where oid = 'pipeline.provider_description_quality'::regclass));
select pg_temp.ok('no function of this change is executable by anon or authenticated', not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname in ('provider_description_quality_v1', 'provider_description_quality_refresh_v1', 'provider_description_quality_counts_v1',
    'provider_description_selection_multi_v1', 'provider_description_cohort_cap_v1', 'provider_description_fill_status_v1', 'provider_description_publication_read_v1', 'provider_missing_fields_v1')
    and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))));

-- 4. the page: every earlier request gives the same rows, order, fields and total
create temp table args(n serial, a jsonb);
insert into args(a) values ('{}'), ('{"sort":"courses","direction":"desc"}'), ('{"query":"one"}'), ('{"description":"filled"}'), ('{"description":"missing","limit":5,"offset":2}'), ('{"admission":"held"}'), ('{"admission":"admitted","sort":"desc_admitted"}'),
  ('{"source_tier":"stored"}'), ('{"website":"matched"}'), ('{"zoho":"not_applicable","limit":5,"offset":2}'), ('{"sort":"website"}'), ('{"sort":"mismatch","direction":"desc"}'), ('{"feeds":true}'),
  ('{"sort":"admission","direction":"desc"}'), ('{"provider_type":"university","sort":"type"}'), ('{"sort":"reader"}'), ('{"sort":"next_retry","direction":"desc"}'), ('{"lifecycle_status":"active","publication_status":"published","sort":"verified"}');
do $$
declare r record; v_old jsonb; v_new jsonb; v_n int := 0;
begin
  for r in select * from args order by n loop
    v_old := security.admin_providers_page_v3_before(r.a); v_new := security.admin_providers_page_v3(r.a);
    if pg_temp.strip(v_new) is distinct from v_old then raise exception 'FAILED: page differs for %', r.a; end if;
    v_n := v_n + 1;
  end loop;
  raise notice 'ok: % request shapes give the same rows, order, fields, paging and total as before (new keys only: quality, website_publication, zoho_publication, missing_fields)', v_n;
end $$;

-- 5. the new filter, sort and item fields
select pg_temp.ok('filter basic = 2, enriched = 4, missing = 2002, held = 2',
  (security.admin_providers_page_v3('{"quality":"basic"}')->>'total')::int = 2 and (security.admin_providers_page_v3('{"quality":"enriched"}')->>'total')::int = 4
  and (security.admin_providers_page_v3('{"quality":"missing"}')->>'total')::int = 2002 and (security.admin_providers_page_v3('{"quality":"held"}')->>'total')::int = 2);
select pg_temp.ok('each single level filters to its own providers', (security.admin_providers_page_v3('{"quality":"verified_published"}')->>'total')::int = 2 and (security.admin_providers_page_v3('{"quality":"consumer_pending"}')->>'total')::int = 1
  and (security.admin_providers_page_v3('{"quality":"waiting_decision"}')->>'total')::int = 1 and (security.admin_providers_page_v3('{"quality":"processing"}')->>'total')::int = 1 and (security.admin_providers_page_v3('{"quality":"queued"}')->>'total')::int = 1
  and (security.admin_providers_page_v3('{"quality":"unrecorded"}')->>'total')::int = 1 and (security.admin_providers_page_v3('{"quality":"enriched_admitted"}')->>'total')::int = 1);
select pg_temp.ok('the filter totals equal the live counts', (security.admin_providers_page_v3('{"quality":"missing"}')->>'total')::int = (security.provider_description_quality_counts_v1()->'classes'->>'missing')::int);
select pg_temp.ok('filters combine: basic and a search', (security.admin_providers_page_v3('{"quality":"basic","query":"current"}')->>'total')::int = 1);
do $$ begin begin perform security.admin_providers_page_v3('{"quality":"nonsense"}'); raise exception 'FAILED: an unknown quality filter was accepted'; exception when sqlstate '22023' then raise notice 'ok: an unknown quality filter is refused (22023)'; end; end $$;
select pg_temp.ok('sort quality ascending starts at Missing, descending at Verified published (whole dataset)',
  (security.admin_providers_page_v3('{"sort":"quality","limit":1}')->'items'->0->'pdesc'->>'quality') = 'missing'
  and (security.admin_providers_page_v3('{"sort":"quality","direction":"desc","limit":2}')->'items'->0->'pdesc'->>'quality') = 'verified_published');
select pg_temp.ok('sort quality pages across the whole set: the last page ends at Verified published and the total is every provider',
  (security.admin_providers_page_v3('{"sort":"quality","limit":200,"offset":1900}')->>'total')::int = (select count(*) from catalogue.providers)
  and (select count(*) from jsonb_array_elements(security.admin_providers_page_v3('{"sort":"quality","limit":200,"offset":1900}')->'items') i where i->'pdesc'->>'quality' = 'verified_published') = 2);
select pg_temp.ok('an item carries its level only when the feeds were worked out for it',
  (security.admin_providers_page_v3('{"query":"verified-one"}')->'items'->0->'pdesc'->'quality') = 'null'::jsonb
  and (security.admin_providers_page_v3('{"query":"verified-one","feeds":true}')->'items'->0->'pdesc'->>'quality') = 'verified_published'
  and (security.admin_providers_page_v3('{"query":"verified-one","feeds":true}')->'items'->0->'pdesc'->>'website_publication') = 'verified'
  and (security.admin_providers_page_v3('{"query":"basic-one"}')->'items'->0->'pdesc'->>'quality') = 'basic_registry');
select pg_temp.ok('sort missing_fields puts the providers with the most missing fields first; the item lists them',
  (select jsonb_array_length(i->'pdesc'->'missing_fields') from jsonb_array_elements(security.admin_providers_page_v3('{"sort":"missing_fields","direction":"desc","limit":1}')->'items') i) >=
  (select jsonb_array_length(i->'pdesc'->'missing_fields') from jsonb_array_elements(security.admin_providers_page_v3('{"sort":"missing_fields","direction":"asc","limit":1}')->'items') i)
  and (security.admin_providers_page_v3('{"query":"bulk 3","limit":1}')->'items'->0->'pdesc'->'missing_fields') @> '"website"'::jsonb);
select pg_temp.ok('the page function is still planned per call', exists (select 1 from pg_proc p where p.oid = 'security.admin_providers_page_v3(jsonb)'::regprocedure and p.proconfig @> array['plan_cache_mode=force_custom_plan']));

-- 6. timing at fixture volume (not production volume; production is measured read only on the live project by supabase/held/provider_fill_fields_equivalence.sql)
do $$
declare t0 timestamptz; v_ms numeric;
begin
  t0 := clock_timestamp(); perform security.admin_providers_page_v3('{"quality":"missing","sort":"quality"}'); v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  raise notice 'ok: whole-set quality filter with quality sort over % providers took % ms', (select count(*) from catalogue.providers), round(v_ms);
  if v_ms > 4000 then raise exception 'FAILED: quality filter and sort too slow (% ms)', round(v_ms); end if;
  t0 := clock_timestamp(); perform security.admin_providers_page_v3('{"sort":"quality","direction":"desc"}'); v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  if v_ms > 4000 then raise exception 'FAILED: quality sort too slow (% ms)', round(v_ms); end if;
  raise notice 'ok: whole-set quality sort took % ms', round(v_ms);
end $$;

-- 7. the Run & Validate service
select pg_temp.ok('every earlier action answers the same: capabilities (max_size is the same cap)', (public.admin_provider_description_run_v1_before('capabilities') - 'providers') = (public.admin_provider_description_run_v1('capabilities') - 'providers'));
create function pg_temp.strip_p(j jsonb) returns jsonb language sql as $$ select j - 'token' - 'preview_token' - 'expires_at' - 'as_at' $$;
select pg_temp.ok('every earlier action answers the same: preview without a named set',
  pg_temp.strip_p(public.admin_provider_description_run_v1_before('preview', '{"country":"AU","size":3}')) = pg_temp.strip_p(public.admin_provider_description_run_v1('preview', '{"country":"AU","size":3}')));
select pg_temp.ok('fill_caps: one cap, the least of the four settings, and capabilities.max_size is the same number',
  (pg_temp.rpc('fill_caps')->>'max_size')::int = 10 and (pg_temp.rpc('fill_caps')->'cap'->>'effective')::int = 10 and (pg_temp.rpc('capabilities')->>'max_size')::int = 10
  and (pg_temp.rpc('fill_caps')->>'poll_seconds')::int = 900 and (pg_temp.rpc('fill_caps')->>'status_max')::int = 10 and (pg_temp.rpc('fill_caps')->>'run_now_allowed')::boolean and pg_temp.rpc('fill_caps') ? 'quality_classes' and not pg_temp.rpc('fill_caps') ? 'providers');
-- the poll interval is a quarter of the reader's own window (pdesc.every_minutes), never under 30 seconds; no setting of its own
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, sort, section, used_by) values ('pipeline', 'pdesc.every_minutes', 'm', 'number', to_jsonb(10), 10, 1440, 'minutes', 9, 's', 'u');
select pg_temp.ok('poll_seconds follows pdesc.every_minutes (10 minutes -> 150 seconds)', (pg_temp.rpc('fill_caps')->>'poll_seconds')::int = 150);
update pipeline.platform_toolset_settings set value = to_jsonb(1) where key = 'pdesc.every_minutes';
select pg_temp.ok('poll_seconds is never under 30', (pg_temp.rpc('fill_caps')->>'poll_seconds')::int = 30);
delete from pipeline.platform_toolset_settings where key = 'pdesc.every_minutes';
update pipeline.platform_toolset_settings set value = to_jsonb(4) where key = 'pdesc.queue_cap';
select pg_temp.ok('lowering the queue cap lowers the screen limit and the server check together', (pg_temp.rpc('fill_caps')->>'max_size')::int = 4 and (pg_temp.rpc('capabilities')->>'max_size')::int = 4 and security.provider_description_cohort_cap_v1() = 4);
do $$ begin begin perform public.admin_provider_description_run_v1('preview', jsonb_build_object('provider_ids', (select jsonb_agg(id) from (select id from catalogue.providers limit 5) x), 'fill_mode', 'missing', 'size', 5));
  raise exception 'FAILED: five providers were accepted under a cap of four'; exception when sqlstate '22023' then raise notice 'ok: a named set over the cap is refused (22023)'; end; end $$;
update pipeline.platform_toolset_settings set value = to_jsonb(60) where key = 'pdesc.queue_cap';

create temp table pv as select pg_temp.rpc('preview', jsonb_build_object('provider_ids', jsonb_build_array(pg_temp.id('missing-one'), pg_temp.id('basic-one'), pg_temp.id('locked-one'), pg_temp.id('queued-one')), 'fill_mode', 'missing')) j;
select pg_temp.ok('fill missing: eligible ones selected, a description already present and a manual lock are refused with their exact reason',
  (select (j->>'selected')::int = 2 and (j->>'size')::int = 4 from pv)
  and (select j->'exclusions' @> jsonb_build_array(jsonb_build_object('provider_id', pg_temp.id('basic-one'), 'provider', 'basic-one', 'reason', 'description_already_present'), jsonb_build_object('provider_id', pg_temp.id('locked-one'), 'provider', 'locked-one', 'reason', 'manual_lock')) from pv));
select pg_temp.ok('the preview is saved with the named set and the mode (so Run Now re-checks the same set)', (select selection->>'fill_mode' = 'missing' and selection->>'description_state' = 'missing' and jsonb_array_length(selection->'provider_ids') = 4
  from pipeline.provider_description_cohorts where id = (select (j->>'token')::uuid from pv)));
-- the refresh of a basic profile is a Platform Admin policy switch that this change reads and never creates (Agent C's pdesc.registry_upgrade_on, with pdesc.machine_admit_on); off, the panel shows the exact refusal
create temp table pu_off as select pg_temp.rpc('preview', jsonb_build_object('provider_ids', jsonb_build_array(pg_temp.id('basic-one'), pg_temp.id('missing-one'), pg_temp.id('locked-one')), 'fill_mode', 'upgrade_basic')) j;
select pg_temp.ok('refresh a basic profile while the switch is off: the exact refusal upgrade_switched_off, nothing selected; a non-basic provider and a locked one keep their own reason',
  (select (j->>'selected')::int = 0 from pu_off)
  and (select j->'exclusions' @> jsonb_build_array(jsonb_build_object('provider_id', pg_temp.id('basic-one'), 'provider', 'basic-one', 'reason', 'upgrade_switched_off'),
        jsonb_build_object('provider_id', pg_temp.id('missing-one'), 'provider', 'missing-one', 'reason', 'not_a_basic_registry_profile'), jsonb_build_object('provider_id', pg_temp.id('locked-one'), 'provider', 'locked-one', 'reason', 'manual_lock')) from pu_off)
  and not (pg_temp.rpc('fill_caps')->>'upgrade_basic_on')::boolean);
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, sort, section, used_by) values
 ('pipeline', 'pdesc.registry_upgrade_on', 'stand-in for the other change', 'number', to_jsonb(1), 0, 1, 'on/off', 90, 's', 'u'), ('pipeline', 'pdesc.machine_admit_on', 'stand-in', 'number', to_jsonb(1), 0, 1, 'on/off', 91, 's', 'u');
select pg_temp.ok('with the switch on, fill_caps says so', (pg_temp.rpc('fill_caps')->>'upgrade_basic_on')::boolean);
create temp table pu as select pg_temp.rpc('preview', jsonb_build_object('provider_ids', jsonb_build_array(pg_temp.id('basic-one'), pg_temp.id('basic-current'), pg_temp.id('missing-one'), pg_temp.id('verified-one')), 'fill_mode', 'upgrade_basic')) j;
select pg_temp.ok('refresh a basic registry profile: the eligible one is selected; the backend''s own refusal is shown as it is; a provider that is not basic is refused by name',
  (select (j->>'selected')::int = 2 from pu)
  and (select j->'exclusions' @> jsonb_build_array(
        jsonb_build_object('provider_id', pg_temp.id('missing-one'), 'provider', 'missing-one', 'reason', 'not_a_basic_registry_profile'), jsonb_build_object('provider_id', pg_temp.id('verified-one'), 'provider', 'verified-one', 'reason', 'not_a_basic_registry_profile')) from pu)
  and (select selection->>'description_state' = 'stale' and selection->>'fill_mode' = 'upgrade_basic' from pipeline.provider_description_cohorts where id = (select (j->>'token')::uuid from pu))
  and (select (e->>'upgrade')::boolean from pu, jsonb_array_elements(pu.j->'providers') e where e->>'provider_id' = pg_temp.id('basic-one')::text));
delete from pipeline.platform_toolset_settings where key in ('pdesc.registry_upgrade_on', 'pdesc.machine_admit_on');
do $$ begin begin perform public.admin_provider_description_run_v1('preview', jsonb_build_object('provider_ids', '[]'::jsonb, 'fill_mode', 'missing')); raise exception 'FAILED: an empty set was accepted';
  exception when sqlstate '22023' then raise notice 'ok: an empty named set is refused (22023)'; end; end $$;
do $$ begin begin perform public.admin_provider_description_run_v1('preview', jsonb_build_object('provider_ids', jsonb_build_array(gen_random_uuid()), 'fill_mode', 'sideways')); raise exception 'FAILED: an unknown fill mode was accepted';
  exception when sqlstate '22023' then raise notice 'ok: an unknown fill mode is refused (22023)'; end; end $$;

-- save and run the governed cohort for two missing providers
create temp table pm as select pg_temp.rpc('preview', jsonb_build_object('provider_ids', jsonb_build_array(pg_temp.id('missing-one'), pg_temp.id('queued-one')), 'fill_mode', 'missing')) j;
set fx.rank = '3';
do $$ begin begin perform pg_temp.rpc('prepare', jsonb_build_object('preview_token', (select j->>'token' from pm), 'reason', 'cohort for the test')); raise exception 'FAILED: a rank below the job''s control rank prepared a cohort';
  exception when sqlstate '42501' then raise notice 'ok: a role below the job''s control rank may preview but not save (42501)'; end; end $$;
select pg_temp.ok('a role at rank 3 may read the status of a named set', jsonb_array_length(pg_temp.rpc('provider_status', jsonb_build_object('provider_ids', jsonb_build_array(pg_temp.id('missing-one'))))->'providers') = 1);
do $$ begin begin perform pg_temp.rpc('quality_refresh'); raise exception 'FAILED: rank 3 refreshed the snapshot'; exception when sqlstate '42501' then raise notice 'ok: refreshing the snapshot needs the job''s control rank (42501)'; end; end $$;
do $$ begin begin perform pg_temp.rpc('provider_publication', jsonb_build_object('provider_ids', jsonb_build_array(pg_temp.id('verified-one')))); raise exception 'FAILED: rank 3 verified publication';
  exception when sqlstate '42501' then raise notice 'ok: verifying publication needs the job''s control rank (42501)'; end; end $$;
set fx.rank = '6';
do $$ begin begin perform pg_temp.rpc('prepare', jsonb_build_object('preview_token', (select j->>'token' from pm), 'reason', 'x')); raise exception 'FAILED: a short reason was accepted';
  exception when sqlstate '22023' then raise notice 'ok: the audit reason must meet the governed minimum (22023)'; end; end $$;
create temp table pp as select pg_temp.rpc('prepare', jsonb_build_object('preview_token', (select j->>'token' from pm), 'reason', 'Fill the missing descriptions for two providers')) j;
select pg_temp.ok('prepare fixes the membership: the two eligible providers', (select j->>'state' = 'prepared' from pp) and (select count(*) from pipeline.provider_description_cohort_members where cohort_id = (select (j->>'cohort_id')::uuid from pp)) = 2);
create temp table pr as select pg_temp.rpc('run', jsonb_build_object('cohort_id', (select j->>'cohort_id' from pp))) j;
select pg_temp.ok('run goes through the same Run Now job kind with the cohort recorded', exists (select 1 from pipeline.admin_jobs where kind = 'job_run_now' and args->>'cohort_id' = (select j->>'cohort_id' from pp) and state = 'done')
  and (select state = 'started' and run_id is not null from pipeline.provider_description_cohorts where id = (select (j->>'cohort_id')::uuid from pp)));
select pg_temp.ok('running the same cohort again repeats nothing', (pg_temp.rpc('run', jsonb_build_object('cohort_id', (select j->>'cohort_id' from pp)))->>'repeat')::boolean);
create temp table ps as select pg_temp.rpc('provider_status', jsonb_build_object('provider_ids', jsonb_build_array(pg_temp.id('missing-one'), pg_temp.id('queued-one'), pg_temp.id('verified-one'), pg_temp.id('held-one'), pg_temp.id('nocourses-one')), 'feeds', true)) j;
select pg_temp.ok('status without the saved cohort: the latest task for each provider named in it, persisted',
  (select p->'latest_task'->>'cohort_id' = (select j->>'cohort_id' from pp) and p->'latest_task'->>'run_state' = 'done' and (p->'latest_task'->>'requested_by_me')::boolean from ps, jsonb_array_elements(ps.j->'providers') p where p->>'name' = 'missing-one')
  and (select p->'latest_task' = 'null'::jsonb or p->'latest_task' is null from ps, jsonb_array_elements(ps.j->'providers') p where p->>'name' = 'verified-one'));
select pg_temp.ok('status shows description present or missing, the level, the reader, the hold reason and the next retry',
  (select (p->>'description_present')::boolean and p->>'quality_class' = 'verified_published' and p->>'website_publication' = 'verified' from ps, jsonb_array_elements(ps.j->'providers') p where p->>'name' = 'verified-one')
  and (select not (p->>'description_present')::boolean and p->>'quality_class' = 'queued' and p->'reader'->>'state' = 'queued' from ps, jsonb_array_elements(ps.j->'providers') p where p->>'name' = 'queued-one')
  and (select p->>'quality_class' = 'held' and p->>'hold_reason' = 'the page does not name the provider' and p->>'next_retry_at' is not null from ps, jsonb_array_elements(ps.j->'providers') p where p->>'name' = 'held-one'));
select pg_temp.ok('status carries the other missing provider fields as information only', (select p->'missing_fields' @> '"phone"' from ps, jsonb_array_elements(ps.j->'providers') p where p->>'name' = 'missing-one'));
do $$ begin begin perform pg_temp.rpc('provider_status', jsonb_build_object('provider_ids', (select jsonb_agg(id) from (select id from catalogue.providers limit 11) x))); raise exception 'FAILED: 11 providers were accepted by one status read under a cap of 10';
  exception when sqlstate '22023' then raise notice 'ok: one status read is bounded by the cohort cap (22023)'; end; end $$;
create temp table pb as select pg_temp.rpc('provider_publication', jsonb_build_object('provider_ids', jsonb_build_array(pg_temp.id('verified-one'), pg_temp.id('pending-one'), pg_temp.id('missing-one')))) j;
select pg_temp.ok('verify publication: the actual consumer read-back, per consumer, never the feed table alone',
  (select p->'website'->>'status' = 'verified' and p->'zoho'->>'status' = 'verified' from pb, jsonb_array_elements(pb.j->'providers') p where p->>'name' = 'verified-one')
  and (select p->'website'->>'status' = 'mismatch' and p->'zoho'->>'status' = 'not_served' from pb, jsonb_array_elements(pb.j->'providers') p where p->>'name' = 'pending-one')
  and (select p->'website'->>'status' = 'awaiting_description' from pb, jsonb_array_elements(pb.j->'providers') p where p->>'name' = 'missing-one'));
-- the Website answers NOT_FOUND for a provider it does not serve: that is not served (Not applicable), never an error
create temp table nf as select pg_temp.rpc('provider_publication', jsonb_build_object('provider_ids', (select jsonb_agg(p.id) from catalogue.providers p
  where nullif(btrim(p.description), '') is not null and not exists (select 1 from pipeline.website_sync_items w where w.entity = 'provider' and w.item_key = p.stable_key)))) j;
select pg_temp.ok('Website NOT_FOUND is not_served and never an error; the Catalogue''s own feed state is carried beside it',
  (select count(*) from nf, jsonb_array_elements(nf.j->'providers')) > 0
  and not exists (select 1 from nf, jsonb_array_elements(nf.j->'providers') p where p->'website'->>'status' = 'error' or p->'zoho'->>'status' = 'error')
  and exists (select 1 from nf, jsonb_array_elements(nf.j->'providers') p where p->'website'->>'status' = 'not_served' and p->'website' ? 'feed'));
select pg_temp.ok('status of a locked provider says locked', (select (p->>'locked')::boolean from jsonb_array_elements(pg_temp.rpc('provider_status', jsonb_build_object('provider_ids', jsonb_build_array(pg_temp.id('locked-one'))))->'providers') p));
-- a basic profile whose upgrade read is waiting or running shows that level, and goes back to Basic when no such read is left
insert into pipeline.provider_description_reads(provider_id, state) values (pg_temp.id('basic-one'), 'queued');
select pg_temp.ok('a basic profile with an upgrade read queued is Enrichment queued', pg_temp.cls('basic-one') = 'queued');
update pipeline.provider_description_reads set state = 'reading' where provider_id = pg_temp.id('basic-one') and state = 'queued';
select pg_temp.ok('a basic profile with an upgrade read running is Enrichment processing', pg_temp.cls('basic-one') = 'processing');
delete from pipeline.provider_description_reads where provider_id = pg_temp.id('basic-one') and state = 'reading';
select pg_temp.ok('and Basic registry profile again when the read is gone', pg_temp.cls('basic-one') = 'basic_registry');
select pg_temp.ok('the verification is recorded in the control log', exists (select 1 from pipeline.admin_control_events where area = 'provider_descriptions' and action = 'verify_provider_publication'));
select pg_temp.ok('quality_counts through the service', (pg_temp.rpc('quality_counts')->>'total')::int = (select count(*) from catalogue.providers));
select pg_temp.ok('quality_refresh through the service writes the named provider only', (pg_temp.rpc('quality_refresh', jsonb_build_object('provider_ids', jsonb_build_array(pg_temp.id('basic-one'))))->>'refreshed')::int = 1);
do $$ declare v_before text; v_after text; begin
  -- the cap check at run time is the same cap: a fixed cohort larger than the current cap is refused, and stays recoverable
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where key = 'pdesc.queue_per_run';
  begin perform pg_temp.rpc('run', jsonb_build_object('cohort_id', (select (j->>'cohort_id') from (select pg_temp.rpc('prepare', jsonb_build_object('preview_token', (select j->>'token' from (select pg_temp.rpc('preview', jsonb_build_object('provider_ids', jsonb_build_array(pg_temp.id('queued-one')), 'fill_mode', 'missing')) j) z), 'reason', 'a one provider cohort')) j) y)));
    raise notice 'ok: a cohort within the lowered cap still runs';
  exception when others then raise exception 'FAILED: %', sqlerrm; end;
  update pipeline.platform_toolset_settings set value = to_jsonb(10) where key = 'pdesc.queue_per_run';
end $$;

-- 7b. Run Now carries the upgrade argument: an upgrade cohort is prepared AND run, and the read is queued (the run re-checks the stored selection with the same argument the preview used)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, sort, section, used_by) values
 ('pipeline', 'pdesc.registry_upgrade_on', 'stand-in for the other change', 'number', to_jsonb(1), 0, 1, 'on/off', 90, 's', 'u'), ('pipeline', 'pdesc.machine_admit_on', 'stand-in', 'number', to_jsonb(1), 0, 1, 'on/off', 91, 's', 'u');
create temp table uv as select pg_temp.rpc('preview', jsonb_build_object('provider_ids', jsonb_build_array(pg_temp.id('basic-current')), 'fill_mode', 'upgrade_basic')) j;
create temp table up as select pg_temp.rpc('prepare', jsonb_build_object('preview_token', (select j->>'token' from uv), 'reason', 'Upgrade the register profile through the reader')) j;
select pg_temp.ok('the stored cohort selection carries upgrade, so the run re-checks it as the preview did',
  (select (selection->>'upgrade')::boolean and selection->>'fill_mode' = 'upgrade_basic' from pipeline.provider_description_cohorts where id = (select (j->>'cohort_id')::uuid from up)));
create temp table ur as select pg_temp.rpc('run', jsonb_build_object('cohort_id', (select j->>'cohort_id' from up))) j;
select pg_temp.ok('an upgrade cohort runs: not parked as selection_changed_before_run, and the read is queued for the member',
  (select coalesce(j->>'reason', '') <> 'selection_changed_before_run' and not coalesce((j->>'parked')::boolean, false) from ur)
  and exists (select 1 from pipeline.provider_description_cohort_members m join pipeline.provider_description_reads r on r.id = m.read_id
               where m.cohort_id = (select (j->>'cohort_id')::uuid from up) and m.provider_id = pg_temp.id('basic-current') and r.state = 'queued')
  and (select count(*) from pipeline.provider_description_reads where provider_id = pg_temp.id('basic-current') and state = 'queued') = 1);
-- with the switch turned off after the preview, the run does not read: it parks the member instead of queueing an upgrade the policy no longer allows
delete from pipeline.provider_description_reads where provider_id = pg_temp.id('basic-current') and state = 'queued';
update pipeline.provider_description_cohort_members set read_id = null where provider_id = pg_temp.id('basic-current');
create temp table up2 as select pg_temp.rpc('prepare', jsonb_build_object('preview_token', (select j->>'token' from (select pg_temp.rpc('preview', jsonb_build_object('provider_ids', jsonb_build_array(pg_temp.id('basic-current')), 'fill_mode', 'upgrade_basic')) j) z), 'reason', 'Second upgrade cohort')) j;
update pipeline.platform_toolset_settings set value = to_jsonb(0) where key = 'pdesc.registry_upgrade_on';
create temp table ur2 as select pg_temp.rpc('run', jsonb_build_object('cohort_id', (select j->>'cohort_id' from up2))) j;
select pg_temp.ok('switched off after the preview: the run queues nothing for the member',
  not exists (select 1 from pipeline.provider_description_reads where provider_id = pg_temp.id('basic-current') and state = 'queued'));
delete from pipeline.platform_toolset_settings where key in ('pdesc.registry_upgrade_on', 'pdesc.machine_admit_on');

-- 8. the migration says what it should
select pg_temp.ok('no setting is added (Platform Admin 10 Nov 2026 05:40)', (select count(*) from pipeline.platform_toolset_settings where key in ('pdesc.quality_refresh_max', 'pdesc.quality_stale_minutes', 'pdesc.fill_poll_seconds', 'pdesc.fill_status_max')) = 0);
select pg_temp.ok('the Provider registry is 34 columns, two new, both off by default and sortable', (select count(*) from pipeline.admin_table_columns where screen = 'providers') = 34
  and (select count(*) from pipeline.admin_table_columns where screen = 'providers' and key in ('description_quality', 'missing_fields') and not default_visible and sort_key is not null) = 2);
select pg_temp.ok('the component register names the new table and functions', (select count(*) from pipeline.component_register where introduced_in = '20261110030000') = 5);
