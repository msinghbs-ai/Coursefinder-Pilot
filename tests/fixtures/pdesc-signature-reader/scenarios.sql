-- Guards: Platform Admin 9-10 Nov 2026 on-demand provider descriptions – identity fix must be able to reach the AI step: the evidence signature carries the reader that is running, so a failure recorded under an earlier reader does not block the current reader, and a failure recorded under the current reader still blocks an unchanged retry.
-- Fixture data only (the provider-description-autonomy seed: fictional providers). Prints "<scenario>|<result>" lines and rolls everything back. Run by tests/fixtures/pdesc-signature-reader/run.sh after migrations 20261109182000, 20261109185000, 20261109233000 and 20261110040000, BEFORE and AFTER migration 20261110090000.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned
begin;
update pipeline.platform_toolset_settings set value = (select jsonb_agg(stable_key) from catalogue.providers where stable_key like 'fixture:provider:%') where toolset_key = 'pipeline' and key = 'pdesc.provider_keys';
update pipeline.platform_toolset_settings set value = '8'::jsonb where toolset_key = 'pipeline' and key = 'batch.provider_description';
update pipeline.platform_toolset_settings set value = '0'::jsonb where toolset_key = 'pipeline' and key = 'pdesc.machine_admit_on';
create or replace function pg_temp.pid(n int) returns uuid language sql as $f$ select id from catalogue.providers where stable_key = 'fixture:provider:' || n $f$;
create or replace function pg_temp.stored_hash(n int) returns text language sql as $f$ select coalesce(a.content_hash, a.id::text) from pipeline.evidence_artifacts a where a.id = security.provider_description_stored_v1(pg_temp.pid(n)) $f$;
create or replace function pg_temp.model() returns text language sql as $f$ select model_identifier from pipeline.central_ai_settings where id = 1 $f$;
create or replace function pg_temp.set_reader(p_ver text) returns void language plpgsql as $f$
begin
  delete from pipeline.pdesc_reader_state;
  if p_ver is not null then insert into pipeline.pdesc_reader_state(singleton, version) values (true, p_ver); end if;
end $f$;
-- a clean slate for provider n: no reads, no recorded outcomes
create or replace function pg_temp.clean(n int) returns void language plpgsql as $f$
begin
  perform set_config('session_replication_role', 'replica', true);
  delete from pipeline.provider_description_reads where provider_id = pg_temp.pid(n);
  delete from pipeline.ops_remedy_outcomes where knowledge_code = 'provider_description:official_about' and entity = pg_temp.pid(n)::text;
  perform set_config('session_replication_role', 'origin', true);
end $f$;
-- a failed attempt recorded the way the platform records it: a read is held and the learning trigger (security.provider_description_learning_trg_v1) writes the outcome under the reader that is running now
create or replace function pg_temp.fail(n int, p_rule text) returns void language plpgsql as $f$
declare v_id uuid;
begin
  insert into pipeline.provider_description_reads(provider_id, state, model, prompt_version, content_hash, source_url, tries, leased_until)
  values (pg_temp.pid(n), 'reading', pg_temp.model(), 'provider-description-v2', pg_temp.stored_hash(n), 'https://p' || n || '.example.edu/about', 1, now() + interval '10 minutes') returning id into v_id;
  update pipeline.provider_description_reads set state = 'held', rule = p_rule, leased_until = null where id = v_id;
end $f$;
-- the reservation the worker makes before the AI call: the reason it is refused, or ok
create or replace function pg_temp.reserve(n int) returns text language plpgsql as $f$
declare v_id uuid; r jsonb;
begin
  perform set_config('session_replication_role', 'replica', true);
  delete from pipeline.provider_description_reads where provider_id = pg_temp.pid(n) and state in ('reading', 'queued');
  perform set_config('session_replication_role', 'origin', true);
  insert into pipeline.provider_description_reads(provider_id, state, model, prompt_version, source_url, tries, leased_until)
  values (pg_temp.pid(n), 'reading', pg_temp.model(), 'provider-description-v2', 'https://p' || n || '.example.edu/about', 1, now() + interval '10 minutes') returning id into v_id;
  r := public.svc_provider_description_reserve_v1(v_id, pg_temp.model(), 0.0002, pg_temp.stored_hash(n));
  delete from pipeline.provider_description_reads where id = v_id;
  update pipeline.provider_description_reads set reserved_usd = 0 where provider_id = pg_temp.pid(n);
  return case when (r->>'ok')::boolean then 'ok' else r->>'reason' end;
end $f$;
create or replace function pg_temp.why(n int) returns text language sql as $f$ select x->>'eligibility_reason' from jsonb_array_elements(security.provider_description_selection_v1(jsonb_build_object('filter', 'all', 'size', 1, 'mode', 'stored', 'provider_id', pg_temp.pid(n)))->'providers') x $f$;

-- 1. the reservation with no failure on record is allowed (the fixture's AI gates are open)
select pg_temp.set_reader('provider-description-source-guard-v2');
select 'no_failure_reserve|' || pg_temp.reserve(2);

-- 2. an identity hold made by reader v2 is recorded as a failed attempt (no AI call was made). The same reader, same page: refused, as before
select pg_temp.clean(3);
select pg_temp.fail(3, 'provider_name_conflict');
select 'v2_failure_recorded|' || (select count(*) from pipeline.ops_remedy_outcomes where knowledge_code = 'provider_description:official_about' and entity = pg_temp.pid(3)::text and not success);
select 'v2_failure_blocks_v2|' || pg_temp.reserve(3);

-- 3. the reader changes to v3 (the identity proof was fixed). The same page, the same model, the same prompt: the earlier reader's failure no longer blocks the reservation
select pg_temp.set_reader('provider-description-source-guard-v3');
select 'v2_failure_blocks_v3|' || pg_temp.reserve(3);

-- 4. a failure recorded while v3 is running blocks an unchanged retry under v3, and is not held against a later reader v4
select pg_temp.clean(4);
select pg_temp.fail(4, 'not_stated');
select 'v3_failure_blocks_v3|' || pg_temp.reserve(4);
select pg_temp.set_reader('provider-description-source-guard-v4');
select 'v3_failure_blocks_v4|' || pg_temp.reserve(4);
select pg_temp.set_reader('provider-description-source-guard-v3');
select 'v3_failure_blocks_v3_again|' || pg_temp.reserve(4);

-- 5. the signature: the same reader gives the same signature, another reader a different one, and one function serves the recorder and every checker
select pg_temp.set_reader('provider-description-source-guard-v2');
create temp table sig as select security.provider_description_signature_v1('h', 'm', 'p') s2;
select 'sig_same_reader_same|' || ((select s2 from sig) = security.provider_description_signature_v1('h', 'm', 'p'))::text;
select pg_temp.set_reader('provider-description-source-guard-v3');
select 'sig_other_reader_differs|' || ((select s2 from sig) <> security.provider_description_signature_v1('h', 'm', 'p'))::text;
select 'recorded_signature_is_current_signature|' || exists (select 1 from pipeline.ops_remedy_outcomes o where o.knowledge_code = 'provider_description:official_about' and o.entity = pg_temp.pid(4)::text
                                                              and o.evidence_signature = security.provider_description_signature_v1(pg_temp.stored_hash(4), pg_temp.model(), 'provider-description-v2'))::text;

-- 6. no reader on record (the state row is empty): the signature is exactly the one before reader versions existed, and a failure under no reader blocks under no reader and not under a reader
select pg_temp.set_reader(null);
select 'no_reader|' || coalesce(security.pdesc_reader_behaviour_v1(), '(none)');
select 'no_reader_signature_is_legacy|' || (security.provider_description_signature_v1('h', 'm', 'p') =
  md5('h|m|p|' || md5(pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure)) || '|' ||
      coalesce((select jsonb_object_agg(key, value order by key)::text from pipeline.platform_toolset_settings where toolset_key = 'pipeline'
                 and key in ('pdesc.min_quote_chars','pdesc.min_sentences','pdesc.max_sentences','pdesc.min_chars','pdesc.max_chars','pdesc.support_min_share','pdesc.duplicate_share','pdesc.source_max_age_days','pdesc.verbatim_span_max_chars','pdesc.claim_words','pdesc.evidence_claim_words','pdesc.superlatives')), '')))::text;
select pg_temp.clean(5);
select pg_temp.fail(5, 'not_stated');
select 'no_reader_failure_blocks_no_reader|' || pg_temp.reserve(5);
select pg_temp.set_reader('provider-description-source-guard-v1');
select 'no_reader_failure_blocks_v1|' || pg_temp.reserve(5);

-- 7. everything else in the reservation is as it was: unchanged rejected evidence is refused whichever reader runs, and the AI ceiling still bounds spend
select pg_temp.set_reader('provider-description-source-guard-v3');
select pg_temp.clean(6);
select pg_temp.set_reader('provider-description-source-guard-v2');
select pg_temp.fail(6, 'not_stated');
select pg_temp.set_reader('provider-description-source-guard-v3');
select pg_temp.clean(6);
do $d$ begin
  perform set_config('session_replication_role', 'replica', true);
  insert into pipeline.provider_description_reads(provider_id, state, rule, content_hash, source_url, created_at, updated_at, tries)
  values (pg_temp.pid(6), 'rejected', 'review_rejected', pg_temp.stored_hash(6), 'https://p6.example.edu/about', now() - interval '1 day', now() - interval '1 day', 1);
  perform set_config('session_replication_role', 'origin', true);
end $d$;
select 'rejected_evidence_still_refused_v3|' || pg_temp.reserve(6);
select pg_temp.set_reader('provider-description-source-guard-v2');
select pg_temp.clean(7);
select pg_temp.fail(7, 'provider_name_conflict');
select pg_temp.set_reader('provider-description-source-guard-v3');
update pipeline.platform_toolset_settings set value = '0.0001'::jsonb where toolset_key = 'pipeline' and key = 'pdesc.ai_usd_max';
select 'ai_ceiling_still_applies|' || pg_temp.reserve(7);
update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'pdesc.ai_usd_max';
select 'ceiling_restored_reserve|' || pg_temp.reserve(7);

-- 8. the picker and the lease use the same signature. Provider 8 and 9: an older read of another page held for another rule, long past the recheck period, and a failure on record for the stored page recorded under reader v2
create or replace function pg_temp.old_failure(n int) returns void language plpgsql as $f$
begin
  perform pg_temp.set_reader('provider-description-source-guard-v2');
  perform pg_temp.clean(n);
  perform pg_temp.fail(n, 'not_stated');
  perform set_config('session_replication_role', 'replica', true);
  update pipeline.provider_description_reads set content_hash = 'an-older-page', updated_at = now() - interval '400 days', created_at = now() - interval '400 days' where provider_id = pg_temp.pid(n);
  perform set_config('session_replication_role', 'origin', true);
end $f$;
select pg_temp.old_failure(8);
select 'picker_v2_failure_under_v2|' || pg_temp.why(8);
select pg_temp.set_reader('provider-description-source-guard-v3');
select 'picker_v2_failure_under_v3|' || pg_temp.why(8);
create or replace function pg_temp.lease_keys() returns text language sql as $f$
  select coalesce(string_agg(replace(p.stable_key, 'fixture:provider:', 'p'), ',' order by p.stable_key), '(none)')
    from jsonb_array_elements(coalesce(public.svc_provider_description_lease_v1(10, null, 'provider-description-reserve-v1')->'items', '[]'::jsonb)) e join catalogue.providers p on p.id = (e->>'provider_id')::uuid $f$;
create or replace function pg_temp.lease_set(p_reader text) returns void language plpgsql as $f$
begin
  perform pg_temp.old_failure(9);
  perform pg_temp.clean(10);
  perform pg_temp.set_reader(p_reader);
  insert into pipeline.provider_description_reads(provider_id, state, next_try_at) values (pg_temp.pid(9), 'queued', now() - interval '1 hour'), (pg_temp.pid(10), 'queued', now() - interval '1 hour');
end $f$;
select pg_temp.lease_set('provider-description-source-guard-v2');
select 'lease_v2_failure_under_v2|' || pg_temp.lease_keys();
select pg_temp.lease_set('provider-description-source-guard-v3');
select 'lease_v2_failure_under_v3|' || pg_temp.lease_keys();

-- 8b. the recorder runs after the reader's own stamp (the stamp trigger sorts before the learning trigger): a read written by reader v3 while v2 was the stamp on record is recorded under v3
select pg_temp.set_reader('provider-description-source-guard-v2');
select pg_temp.clean(11);
do $d$ declare v_id uuid; begin
  insert into pipeline.provider_description_reads(provider_id, state, model, prompt_version, content_hash, source_url, tries, leased_until)
  values (pg_temp.pid(11), 'reading', pg_temp.model(), 'provider-description-v2', pg_temp.stored_hash(11), 'https://p11.example.edu/about', 1, now() + interval '10 minutes') returning id into v_id;
  update pipeline.provider_description_reads set state = 'held', rule = 'not_stated', leased_until = null,
         checks = '{"identity":{"ok":true,"reader_behavior_version":"provider-description-source-guard-v3"}}'::jsonb where id = v_id;
end $d$;
select 'stamp_moved_by_the_read|' || security.pdesc_reader_behaviour_v1();
select 'recorded_under_the_reader_that_wrote_it|' || exists (select 1 from pipeline.ops_remedy_outcomes o where o.entity = pg_temp.pid(11)::text and o.knowledge_code = 'provider_description:official_about'
                                                                and o.evidence_signature = security.provider_description_signature_v1(pg_temp.stored_hash(11), pg_temp.model(), 'provider-description-v2'))::text;
select pg_temp.set_reader('provider-description-source-guard-v2');
select 'not_recorded_under_the_old_reader|' || (not exists (select 1 from pipeline.ops_remedy_outcomes o where o.entity = pg_temp.pid(11)::text and o.knowledge_code = 'provider_description:official_about'
                                                                and o.evidence_signature = security.provider_description_signature_v1(pg_temp.stored_hash(11), pg_temp.model(), 'provider-description-v2')))::text;

-- 8c. Sydney's shape (QA of #980, read 14939e4a on 10 Nov 2026): the latest read is held recovery_knowledge_unchanged_failure on the unchanged page with no AI call and nothing reserved; the failure it found was recorded under an earlier reader.
--     The picker must offer it again under the new reader, and must keep parking every other hold. A latest read is made the way the platform makes it: the hold is written with the reader triggers off (a past read).
create or replace function pg_temp.latest(n int, p_rule text, p_calls int, p_reserved numeric, p_hash text default null, p_state text default 'held') returns void language plpgsql as $f$
begin
  perform set_config('session_replication_role', 'replica', true);
  insert into pipeline.provider_description_reads(provider_id, state, rule, content_hash, source_url, created_at, updated_at, tries, ai_calls, reserved_usd, model, prompt_version, checks)
  values (pg_temp.pid(n), p_state, p_rule, coalesce(p_hash, pg_temp.stored_hash(n)), 'https://p' || n || '.example.edu/about', now() + interval '1 minute', now() + interval '1 minute', 1, p_calls, p_reserved, pg_temp.model(), 'provider-description-v2',
          '{"identity":{"ok":true,"reader_behavior_version":"provider-description-source-guard-v3"}}'::jsonb);
  perform set_config('session_replication_role', 'origin', true);
end $f$;
-- Sydney: a failure recorded under reader v2 (the identity hold), then the v3 read refused by the old signature check
select pg_temp.set_reader('provider-description-source-guard-v2');
select pg_temp.clean(12);
select pg_temp.fail(12, 'provider_name_conflict');
select pg_temp.set_reader('provider-description-source-guard-v3');
select pg_temp.latest(12, 'recovery_knowledge_unchanged_failure', 0, 0);
select 'sydney_shape_picker|' || pg_temp.why(12);
-- the same shape with the memory made by the CURRENT reader: the memory still matches, parked
select pg_temp.clean(15);
select pg_temp.fail(15, 'provider_name_conflict');
select pg_temp.latest(15, 'recovery_knowledge_unchanged_failure', 0, 0);
select 'memory_matches_current_reader_picker|' || pg_temp.why(15);
-- a real AI failure on the unchanged page stays parked: another rule, or the same rule with an AI call made, or a reservation left
select pg_temp.set_reader('provider-description-source-guard-v2');
select pg_temp.clean(7);
select pg_temp.fail(7, 'verbatim_passage');
select pg_temp.set_reader('provider-description-source-guard-v3');
select pg_temp.latest(7, 'verbatim_passage', 1, 0);
select 'real_ai_failure_other_rule_picker|' || pg_temp.why(7);
select pg_temp.set_reader('provider-description-source-guard-v2');
select pg_temp.clean(5);
select pg_temp.fail(5, 'provider_name_conflict');
select pg_temp.set_reader('provider-description-source-guard-v3');
select pg_temp.latest(5, 'recovery_knowledge_unchanged_failure', 1, 0);
select 'real_ai_failure_same_rule_picker|' || pg_temp.why(5);
select pg_temp.set_reader('provider-description-source-guard-v2');
select pg_temp.clean(6);
select pg_temp.fail(6, 'provider_name_conflict');
select pg_temp.set_reader('provider-description-source-guard-v3');
select pg_temp.latest(6, 'recovery_knowledge_unchanged_failure', 0, 0.0002);
select 'reservation_left_picker|' || pg_temp.why(6);
-- a rejected page stays refused: the latest read rejected, or an earlier read of the provider rejected on this page
select pg_temp.set_reader('provider-description-source-guard-v2');
select pg_temp.clean(1);
select pg_temp.fail(1, 'provider_name_conflict');
select pg_temp.set_reader('provider-description-source-guard-v3');
select pg_temp.latest(1, 'review_rejected', 0, 0, null, 'rejected');
select 'rejected_latest_picker|' || pg_temp.why(1);
select pg_temp.set_reader('provider-description-source-guard-v2');
select pg_temp.clean(2);
select pg_temp.fail(2, 'provider_name_conflict');
select pg_temp.set_reader('provider-description-source-guard-v3');
do $d$ begin
  perform set_config('session_replication_role', 'replica', true);
  insert into pipeline.provider_description_reads(provider_id, state, rule, content_hash, source_url, created_at, updated_at, tries)
  values (pg_temp.pid(2), 'rejected', 'review_rejected', pg_temp.stored_hash(2), 'https://p2.example.edu/about', now() - interval '3 days', now() - interval '3 days', 1);
  perform set_config('session_replication_role', 'origin', true);
end $d$;
select pg_temp.latest(2, 'recovery_knowledge_unchanged_failure', 0, 0);
select 'rejected_earlier_picker|' || pg_temp.why(2);
-- a changed page stays parked by the recheck period (the hold was made on another page)
select pg_temp.set_reader('provider-description-source-guard-v2');
select pg_temp.clean(3);
select pg_temp.fail(3, 'provider_name_conflict');
select pg_temp.set_reader('provider-description-source-guard-v3');
select pg_temp.latest(3, 'recovery_knowledge_unchanged_failure', 0, 0, 'an-older-page');
select 'changed_page_picker|' || pg_temp.why(3);
-- a repeat read is not offered twice without a new failure signature: Sydney's read is offered, is read, and the AI step fails for real under v3 (a failure is recorded for the new signature); the next hold is parked,
-- and a still newer reader (v4) is a new signature, so it is offered once more
select pg_temp.fail(12, 'not_stated');
select pg_temp.latest(12, 'recovery_knowledge_unchanged_failure', 0, 0);
select 'repeat_same_signature_picker|' || pg_temp.why(12);
select pg_temp.set_reader('provider-description-source-guard-v4');
select 'repeat_new_reader_picker|' || pg_temp.why(12);
-- the automatic queue offers Sydney's shape: its read is queued again (a stored-page read, no new fetch)
select pg_temp.set_reader('provider-description-source-guard-v2');
select pg_temp.clean(12);
select pg_temp.fail(12, 'provider_name_conflict');
select pg_temp.set_reader('provider-description-source-guard-v3');
select pg_temp.latest(12, 'recovery_knowledge_unchanged_failure', 0, 0);
update pipeline.platform_toolset_settings set value = '40'::jsonb where toolset_key = 'pipeline' and key in ('pdesc.queue_per_run', 'pdesc.pending_max', 'run_now.pilot_cap');
select 'enqueue_ran|' || (security.provider_description_enqueue_v1() is not null)::text;
select 'sydney_shape_enqueued|' || case when exists (select 1 from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(12) and r.state = 'queued') then 'queued' else 'not queued' end;

-- 9. the reader function is one primary-key row of the reader table and never reads the reads; grants stay closed
select 'reader_fn_reads_only_state|' || (prosrc like '%pdesc_reader_state%' and prosrc not like '%provider_description_reads%')::text from pg_proc where oid = 'security.pdesc_reader_behaviour_v1()'::regprocedure;
select 'grants|' || has_function_privilege('anon', 'security.provider_description_signature_v1(text,text,text)'::regprocedure, 'execute')::text || '|' || has_function_privilege('authenticated', 'security.provider_description_signature_v1(text,text,text)'::regprocedure, 'execute')::text;
rollback;
