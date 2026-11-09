-- Guards: F-PDESC Directive 3 (Platform Admin, 9 Nov 2026): a provider held for identity by an earlier reader is offered to the current reader once more (same stored page, no new fetch), a hold made by the current reader or for any other rule stays parked, and every later check (manual lock, setting, identity findings) still applies.
-- Fixture data only (the provider-description-autonomy seed: fictional providers). Prints "<scenario>|<result>" lines and rolls everything back. Run by tests/fixtures/pdesc-identity-reeval/run.sh after migration 20261109181000.
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
  delete from pipeline.provider_description_reads where provider_id = pg_temp.pid(n);
  insert into pipeline.provider_description_reads(provider_id, state, rule, content_hash, source_url, created_at, updated_at, tries, checks)
  values (pg_temp.pid(n), 'held', p_rule, coalesce(p_hash, pg_temp.stored_hash(n)), 'https://p' || n || '.example.edu/about', now() - interval '2 days', now() - interval '2 days', 1,
          case when p_ver is null then '{}'::jsonb else jsonb_build_object('identity', jsonb_build_object('ok', false, 'rule', p_rule, 'reader_behavior_version', p_ver)) end);
end $f$;
create or replace function pg_temp.why(n int) returns text language sql as $f$ select x->>'eligibility_reason' from jsonb_array_elements(security.provider_description_selection_v1(jsonb_build_object('filter', 'all', 'size', 1, 'mode', 'stored', 'provider_id', pg_temp.pid(n)))->'providers') x $f$;

-- 0. before any reader has stamped a page: no current reader; a stamped hold is the current one, so it stays parked (the deployed worker is what defines "current")
select 'no_reader|' || coalesce(security.pdesc_reader_behaviour_v1(), '(none)');
select pg_temp.hold(2, 'provider_name_conflict', 'provider-description-source-guard-v1');
select 'v1_only_parked|' || security.pdesc_reader_behaviour_v1() || '|' || pg_temp.why(2);

-- 1. the reader changes: a read stamped v2 exists. The v1 conflict hold, on the same stored page, is offered again
select pg_temp.hold(3, 'provider_name_conflict', 'provider-description-source-guard-v2');
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

-- 4. the version label is compared as a number within one prefix (v10 is newer than v9)
select pg_temp.hold(1, 'provider_name_conflict', 'provider-description-source-guard-v9');
select pg_temp.hold(12, 'provider_name_conflict', 'provider-description-source-guard-v10');
select 'v10_over_v9|' || security.pdesc_reader_behaviour_v1() || '|' || pg_temp.why(1) || '|' || pg_temp.why(12);

-- 5. the evidence signature includes the reader: the same page, model and prompt gives another signature when the reader changed, so a failure recorded for the earlier reader does not block the current one
delete from pipeline.provider_description_reads where checks ? 'identity';
select pg_temp.hold(3, 'provider_name_conflict', 'provider-description-source-guard-v1');
create temp table sig as select security.provider_description_signature_v1(pg_temp.stored_hash(2), 'm', 'provider-description-v2') s1, security.pdesc_reader_behaviour_v1() r1;
select 'sig_reader_v1|' || (select r1 from sig);
select pg_temp.hold(4, 'provider_name_conflict', 'provider-description-source-guard-v2');
select 'sig_changes_with_reader|' || ((select s1 from sig) <> security.provider_description_signature_v1(pg_temp.stored_hash(2), 'm', 'provider-description-v2'))::text || '|' || security.pdesc_reader_behaviour_v1();
select 'sig_stable_within_reader|' || (security.provider_description_signature_v1('h', 'm', 'p') = security.provider_description_signature_v1('h', 'm', 'p'))::text;
-- a failure recorded for the earlier reader's signature blocks that signature only
select security.ops_learning_record_v1(jsonb_build_object('code', 'provider_description:official_about', 'entity', pg_temp.pid(2)::text, 'evidence_signature', (select s1 from sig), 'performed_by', 'platform', 'success', false, 'stage_advanced', false, 'cost_usd', 0,
   'expected', 'fixture', 'observed', '{}'::jsonb, 'evidence', '{}'::jsonb)) is not null as recorded;
select 'retry_old_signature|' || (security.ops_learning_retry_check_v1('provider_description:official_about', pg_temp.pid(2)::text, (select s1 from sig))->>'allowed');
select 'retry_new_signature|' || (security.ops_learning_retry_check_v1('provider_description:official_about', pg_temp.pid(2)::text, security.provider_description_signature_v1(pg_temp.stored_hash(2), 'm', 'provider-description-v2'))->>'allowed');

-- 6. grants and index
select 'grants|' || has_function_privilege('anon', 'security.pdesc_reader_behaviour_v1()'::regprocedure, 'execute')::text || '|' || has_function_privilege('authenticated', 'security.pdesc_reader_behaviour_v1()'::regprocedure, 'execute')::text;
select 'setting|' || (select value::text || '|' || kind || '|' || unit || '|' || section || '|' || (label <> '')::text || '|' || (used_by like '%selection_v1%')::text from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.identity_reeval_rules');
rollback;
