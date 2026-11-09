-- Guards: F-PDESC Directive 3 (Platform Admin, 9 Nov 2026): a provider held for identity by an earlier reader is offered to the current reader once more (same stored page, no new fetch), a hold made by the current reader or for any other rule stays parked, and every later check (manual lock, setting, identity findings) still applies.
-- Fixture data only (the provider-description-autonomy seed: fictional providers). Prints "<scenario>|<result>" lines and rolls everything back. Run by tests/fixtures/pdesc-identity-reeval/run.sh after migrations 20261109182000 and 20261109185000.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned
begin;
update pipeline.platform_toolset_settings set value = (select jsonb_agg(stable_key) from catalogue.providers where stable_key like 'fixture:provider:%') where toolset_key = 'pipeline' and key = 'pdesc.provider_keys';
create or replace function pg_temp.pid(n int) returns uuid language sql as $f$ select id from catalogue.providers where stable_key = 'fixture:provider:' || n $f$;
create or replace function pg_temp.stored_hash(n int) returns text language sql as $f$ select coalesce(a.content_hash, a.id::text) from pipeline.evidence_artifacts a where a.id = security.provider_description_stored_v1(pg_temp.pid(n)) $f$;
-- a held read for provider n: rule, the reader behaviour version stamped on its identity check (null: none), the page hash (the stored copy's by default)
create or replace function pg_temp.hold(n int, p_rule text, p_ver text, p_hash text default null) returns void language plpgsql as $f$
begin
  perform set_config('session_replication_role', 'replica', true);   -- a fixture is a past read: the reader triggers do not see it
  delete from pipeline.provider_description_reads where provider_id = pg_temp.pid(n);
  insert into pipeline.provider_description_reads(provider_id, state, rule, content_hash, source_url, created_at, updated_at, tries, checks)
  values (pg_temp.pid(n), 'held', p_rule, coalesce(p_hash, pg_temp.stored_hash(n)), 'https://p' || n || '.example.edu/about', now() - interval '2 days', now() - interval '2 days', 1,
          case when p_ver is null then '{}'::jsonb else jsonb_build_object('identity', jsonb_build_object('ok', false, 'rule', p_rule, 'reader_behavior_version', p_ver)) end);
  perform set_config('session_replication_role', 'origin', true);
end $f$;
create or replace function pg_temp.set_reader(p_ver text) returns void language plpgsql as $f$
begin
  delete from pipeline.pdesc_reader_state;
  if p_ver is not null then insert into pipeline.pdesc_reader_state(singleton, version) values (true, p_ver); end if;
end $f$;
-- the open read the picker creates when it offers a provider again, due now
create or replace function pg_temp.open_read(n int) returns void language plpgsql as $f$
begin insert into pipeline.provider_description_reads(provider_id, state, next_try_at) values (pg_temp.pid(n), 'queued', now() - interval '1 hour'); end $f$;
-- a recorded failure of the lease's own signature for provider n's stored copy (what the recovery knowledge holds after a failed read)
create or replace function pg_temp.fail(n int) returns void language plpgsql as $f$
begin
  perform security.ops_learning_record_v1(jsonb_build_object('code', 'provider_description:official_about', 'entity', pg_temp.pid(n)::text,
    'evidence_signature', security.provider_description_signature_v1(pg_temp.stored_hash(n), (select model_identifier from pipeline.central_ai_settings where id = 1), 'provider-description-v2'),
    'performed_by', 'platform', 'success', false, 'stage_advanced', false, 'cost_usd', 0, 'expected', 'fixture', 'observed', '{}'::jsonb, 'evidence', '{}'::jsonb));
end $f$;
create or replace function pg_temp.lease_keys() returns text language sql as $f$
  select coalesce(string_agg(replace(p.stable_key, 'fixture:provider:', 'p'), ',' order by p.stable_key), '(none)')
    from jsonb_array_elements(coalesce(public.svc_provider_description_lease_v1(10, null, 'provider-description-reserve-v1')->'items', '[]'::jsonb)) e join catalogue.providers p on p.id = (e->>'provider_id')::uuid $f$;
create or replace function pg_temp.open_state(n int) returns text language sql as $f$
  select r.state || ':' || coalesce(r.rule, '-') from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(n) and r.state in ('queued', 'reading', 'held') order by (r.state = 'held'), r.created_at desc limit 1 $f$;
create or replace function pg_temp.why(n int) returns text language sql as $f$ select x->>'eligibility_reason' from jsonb_array_elements(security.provider_description_selection_v1(jsonb_build_object('filter', 'all', 'size', 1, 'mode', 'stored', 'provider_id', pg_temp.pid(n)))->'providers') x $f$;

-- 0. before any reader has stamped a page: no current reader; a stamped hold is the current one, so it stays parked (the deployed worker is what defines "current")
select pg_temp.set_reader(null);
select 'no_reader|' || coalesce(security.pdesc_reader_behaviour_v1(), '(none)');
select pg_temp.hold(2, 'provider_name_conflict', 'provider-description-source-guard-v1');
select pg_temp.set_reader('provider-description-source-guard-v1');
select 'v1_only_parked|' || security.pdesc_reader_behaviour_v1() || '|' || pg_temp.why(2);

-- 1. the reader changes: the running reader is v2. The v1 conflict hold, on the same stored page, is offered again
select pg_temp.hold(3, 'provider_name_conflict', 'provider-description-source-guard-v2');
select pg_temp.set_reader('provider-description-source-guard-v2');
select 'current_reader|' || security.pdesc_reader_behaviour_v1();
select 'v1_conflict_offered|' || pg_temp.why(2);
-- the same hold made by the current reader stays parked
select 'v2_conflict_parked|' || pg_temp.why(3);
-- other identity rules in the setting are offered too; a rule that is not an identity rule is not
select pg_temp.hold(4, 'provider_name_not_proved', 'provider-description-source-guard-v1');
select pg_temp.hold(5, 'provider_subunit_source', 'provider-description-source-guard-v1');
select pg_temp.hold(6, 'verbatim_passage', 'provider-description-source-guard-v1');
select pg_temp.hold(7, 'quote_not_on_page', 'provider-description-source-guard-v1');
select pg_temp.hold(8, 'not_stated', 'provider-description-source-guard-v1');
select 'v1_not_proved_offered|' || pg_temp.why(4);
select 'v1_subunit_offered|' || pg_temp.why(5);
select 'v1_verbatim_parked|' || pg_temp.why(6);
select 'v1_quote_parked|' || pg_temp.why(7);
select 'v1_not_stated_parked|' || pg_temp.why(8);
-- a hold with no reader stamp at all (made before the stamp existed) is an earlier reader's
select pg_temp.hold(9, 'provider_name_conflict', null);
select 'unstamped_conflict_offered|' || pg_temp.why(9);
-- a rejection by a person is never re-offered by this rule (only held reads)
delete from pipeline.provider_description_reads where provider_id = pg_temp.pid(10);
insert into pipeline.provider_description_reads(provider_id, state, rule, content_hash, source_url, created_at, updated_at, tries, checks)
values (pg_temp.pid(10), 'rejected', 'provider_name_conflict', pg_temp.stored_hash(10), 'https://p10.example.edu/about', now() - interval '2 days', now() - interval '2 days', 1, '{"identity":{"reader_behavior_version":"provider-description-source-guard-v1"}}'::jsonb);
select pg_temp.set_reader('provider-description-source-guard-v2');   -- the insert above is a past read written with the triggers on: the running reader is v2
select 'rejected_parked|' || pg_temp.why(10);

-- 2. every later check still applies: a manual lock, the setting, the governed identity proof
select pg_temp.hold(11, 'provider_name_conflict', 'provider-description-source-guard-v1');
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('provider', pg_temp.pid(11), 'description', 'value');
select 'manual_lock_wins|' || pg_temp.why(11);
update pipeline.platform_toolset_settings set value = '[]'::jsonb where toolset_key = 'pipeline' and key = 'pdesc.identity_reeval_rules';
select 'setting_empty_parked|' || pg_temp.why(2);
update pipeline.platform_toolset_settings set value = '["provider_name_conflict"]'::jsonb where toolset_key = 'pipeline' and key = 'pdesc.identity_reeval_rules';
select 'setting_narrowed|' || pg_temp.why(2) || '|' || pg_temp.why(4);
update pipeline.platform_toolset_settings set value = '["provider_name_conflict", "provider_name_not_proved", "provider_subunit_source"]'::jsonb where toolset_key = 'pipeline' and key = 'pdesc.identity_reeval_rules';

-- 3. once the current reader has judged it again, the hold carries the current version and is parked as before
update pipeline.provider_description_reads set checks = jsonb_build_object('identity', jsonb_build_object('ok', false, 'rule', 'provider_name_conflict', 'reader_behavior_version', 'provider-description-source-guard-v2')), updated_at = now() - interval '1 hour' where provider_id = pg_temp.pid(2);
select 'judged_again_parked|' || pg_temp.why(2);

-- 4. the running reader is the newest stamp a worker wrote (triggers on the reads): a new stamp becomes current, the same stamp or an old row touched again does not,
--    a rename of the prefix is picked up, and a worker rolled back to an earlier reader makes that reader current again
select pg_temp.set_reader('provider-description-source-guard-v2');
insert into pipeline.provider_description_reads(provider_id, state, rule, checks) values (pg_temp.pid(1), 'held', 'not_stated', '{"identity":{"ok":true,"reader_behavior_version":"provider-description-source-guard-v10"}}'::jsonb);
select 'new_stamp_current|' || security.pdesc_reader_behaviour_v1();
update pipeline.provider_description_reads set tries = tries + 1, checks = checks || '{"touched":true}'::jsonb where provider_id = pg_temp.pid(2);
select 'old_row_touched_unchanged|' || security.pdesc_reader_behaviour_v1();
insert into pipeline.provider_description_reads(provider_id, state, rule, checks) values (pg_temp.pid(12), 'held', 'not_stated', '{"identity":{"ok":true,"reader_behavior_version":"identity-reader-2027-a"}}'::jsonb);
select 'prefix_rename_current|' || security.pdesc_reader_behaviour_v1();
insert into pipeline.provider_description_reads(provider_id, state, rule, checks) values (pg_temp.pid(14), 'held', 'not_stated', '{"identity":{"ok":true,"reader_behavior_version":"provider-description-source-guard-v2"}}'::jsonb);
select 'rolled_back_current|' || security.pdesc_reader_behaviour_v1();
update pipeline.provider_description_reads set checks = checks || '{"identity":{"ok":true,"reader_behavior_version":"provider-description-source-guard-v3"}}'::jsonb where provider_id = pg_temp.pid(14);
select 'update_changing_stamp_current|' || security.pdesc_reader_behaviour_v1();
select 'reader_state_rows|' || count(*) from pipeline.pdesc_reader_state;

-- 5. the evidence signature is NOT changed by the reader: the memory of every other failure is kept
select pg_temp.set_reader('provider-description-source-guard-v1');
create temp table sig as select security.provider_description_signature_v1('h', 'm', 'p') s1;
select pg_temp.set_reader('provider-description-source-guard-v2');
select 'sig_independent_of_reader|' || ((select s1 from sig) = security.provider_description_signature_v1('h', 'm', 'p'))::text;

-- 6. the lease: providers 2 to 7 each have a finished read on the same stored page and a recorded failure for the lease's signature, and an open read due now (what the picker creates); provider 8 has no failure
update pipeline.platform_toolset_settings set value = '8'::jsonb where toolset_key = 'pipeline' and key = 'batch.provider_description';
update pipeline.platform_toolset_settings set value = '0'::jsonb where toolset_key = 'pipeline' and key = 'pdesc.machine_admit_on';
create or replace function pg_temp.lease_set() returns void language plpgsql as $f$
begin
  perform set_config('session_replication_role', 'replica', true);
  delete from pipeline.provider_description_reads where provider_id in (select pg_temp.pid(n) from generate_series(1, 14) n);
  perform set_config('session_replication_role', 'origin', true);
  perform pg_temp.hold(2, 'provider_name_conflict', 'provider-description-source-guard-v1'); perform pg_temp.fail(2); perform pg_temp.open_read(2);   -- identity, earlier reader: offered again
  perform pg_temp.hold(3, 'provider_name_conflict', 'provider-description-source-guard-v2'); perform pg_temp.fail(3); perform pg_temp.open_read(3);   -- identity, current reader: stays parked
  perform pg_temp.hold(4, 'not_stated', 'provider-description-source-guard-v1');             perform pg_temp.fail(4); perform pg_temp.open_read(4);   -- another kind of failure: its memory is kept
  perform pg_temp.hold(5, 'provider_subunit_source', 'provider-description-source-guard-v1'); perform pg_temp.fail(5); perform pg_temp.open_read(5);  -- identity, earlier reader: offered again
  perform pg_temp.hold(6, 'provider_name_conflict', null);                                   perform pg_temp.fail(6); perform pg_temp.open_read(6);   -- identity, no stamp: an earlier reader's
  perform pg_temp.hold(7, 'verbatim_passage', 'provider-description-source-guard-v1');       perform pg_temp.fail(7); perform pg_temp.open_read(7);   -- not an identity rule: its memory is kept
  perform pg_temp.open_read(8);                                                                                                                       -- no failure at all: leased as before
end $f$;
select pg_temp.set_reader('provider-description-source-guard-v2');
select pg_temp.lease_set();
select 'lease_reoffer|' || pg_temp.lease_keys();
select 'lease_blocked|p3=' || pg_temp.open_state(3) || ',p4=' || pg_temp.open_state(4) || ',p7=' || pg_temp.open_state(7);

-- 7. with the setting empty (no rule is re-offered) the earlier reader's failure keeps its memory for every rule: only the provider with no failure is leased
select pg_temp.lease_set();
update pipeline.platform_toolset_settings set value = '[]'::jsonb where toolset_key = 'pipeline' and key = 'pdesc.identity_reeval_rules';
select 'lease_setting_empty|' || pg_temp.lease_keys();
update pipeline.platform_toolset_settings set value = '["provider_name_conflict", "provider_name_not_proved", "provider_subunit_source"]'::jsonb where toolset_key = 'pipeline' and key = 'pdesc.identity_reeval_rules';

-- 7b. a worker rolled back to the earlier reader (v1 is running): holds stamped by another reader (v2, no stamp) are read once by it; holds stamped v1 are its own and stay parked
select pg_temp.lease_set();
select pg_temp.set_reader('provider-description-source-guard-v1');
select 'lease_rolled_back_reader|' || pg_temp.lease_keys();

-- 8. grants and setting
select 'grants|' || has_function_privilege('anon', 'security.pdesc_reader_behaviour_v1()'::regprocedure, 'execute')::text || '|' || has_function_privilege('authenticated', 'security.pdesc_reader_behaviour_v1()'::regprocedure, 'execute')::text
  || '|' || has_table_privilege('anon', 'pipeline.pdesc_reader_state', 'select')::text || '|' || has_table_privilege('authenticated', 'pipeline.pdesc_reader_state', 'select')::text;
select 'setting|' || (select value::text || '|' || kind || '|' || unit || '|' || section || '|' || (label <> '')::text || '|' || (used_by like '%selection_v1%')::text from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.identity_reeval_rules');
rollback;
