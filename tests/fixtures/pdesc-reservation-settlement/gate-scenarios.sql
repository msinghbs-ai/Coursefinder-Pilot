-- Guards: Platform Admin operating model v1.5 (10 Nov 2026, delivery first), the Basic -> Enriched upgrade lane of the scheduled reader: security.provider_description_enqueue_v1 gates the lane on its OWN queued count (queued reads of providers that hold a register-fact profile, against the lower of pdesc.queue_per_run and pdesc.queue_cap), so the many queued reads of providers with no description no longer switch it off; every other bound stays (the switch pdesc.registry_upgrade_on, queue_per_run a run, the selection's own eligibility).
-- Fixture data only (the pdesc-basic-upgrade seed: fictional register providers, no live data). Prints "<scenario>|<result>" lines; every block rolls back. Run by tests/fixtures/pdesc-reservation-settlement/run.sh BEFORE the gate migration (expected-gate-before.txt: the starvation) and AFTER it (expected-gate.txt).
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

create or replace function pg_temp.pid(n int) returns uuid language sql as $f$ select id from catalogue.providers where stable_key = 'fixture:provider:' || case when n = 13 then 'browser' else n::text end $f$;
create or replace function pg_temp.set_s(k text, v jsonb) returns void language sql as $f$ update pipeline.platform_toolset_settings set value = v where toolset_key = 'pipeline' and key = k $f$;
create or replace function pg_temp.reg_setup() returns void language plpgsql as $f$
declare v_sub uuid := gen_random_uuid(); v_l1 uuid := gen_random_uuid(); v_l2 uuid := gen_random_uuid(); v_f1 uuid := gen_random_uuid(); v_f2 uuid := gen_random_uuid();
begin
  insert into ref.subdivisions(id, country_id, code, name, status) values (v_sub, '00000000-0000-0000-0000-0000000000a1', 'FX-VIC', 'Victoria', 'active');
  insert into ref.study_levels(code, name, id) values ('fx_bach', 'Bachelor', v_l1), ('fx_mast', 'Masters', v_l2);
  insert into ref.fields_of_study(id, name) values (v_f1, 'Business'), (v_f2, 'Engineering');
  update catalogue.providers set primary_city = 'MELBOURNE', subdivision_id = v_sub where id in (pg_temp.pid(1), pg_temp.pid(14));
  update catalogue.courses set study_level_id = v_l1, primary_field_id = v_f1 where id in (select id from catalogue.courses where provider_id = pg_temp.pid(1) and lifecycle_status = 'active' order by id limit 5);
  update catalogue.courses set study_level_id = v_l2, primary_field_id = v_f2 where id in (select id from catalogue.courses where provider_id = pg_temp.pid(1) and lifecycle_status = 'active' and study_level_id is null order by id limit 5);
end $f$;
-- provider 1 holds an admitted register-fact profile (made by the register-fact tier, as live), after an older read that found no About page
create or replace function pg_temp.mkprofile() returns void language plpgsql as $f$
begin
  perform pg_temp.reg_setup();
  perform pg_temp.set_s('pdesc.machine_admit_on', '1'); perform pg_temp.set_s('pdesc.registry_factual_on', '1'); perform pg_temp.set_s('pdesc.registry_after_rules', '["no_about_page"]'); perform pg_temp.set_s('pdesc.acquire_direct', '0'); perform pg_temp.set_s('batch.provider_description', '10');
  insert into pipeline.provider_description_reads(provider_id, state, rule, reason, created_at, updated_at) values (pg_temp.pid(1), 'held', 'no_about_page', 'fixture', now() - interval '4 days', now() - interval '4 days');
  if (security.provider_description_registry_tier_v1()->>'admitted')::int <> 1 then raise exception 'the fixture profile was not admitted'; end if;
  -- the profile was admitted two days ago (the fixture runs in one transaction, so every row would otherwise carry the same time)
  update pipeline.provider_description_reads set created_at = now() - interval '2 days', updated_at = now() - interval '2 days', last_verified_at = now() - interval '2 days' where provider_id = pg_temp.pid(1) and rule = 'registry_factual';
  update pipeline.provider_description_machine_admissions set created_at = now() - interval '2 days' where provider_id = pg_temp.pid(1) and tier = 'registry_factual';
end $f$;

-- how many times the enqueue asked the selection for providers (the missing-description lane asks once for each country share, the upgrade lane once)
create or replace function pg_temp.sel_calls() returns bigint language sql as $f$ select coalesce((select calls from pg_stat_xact_user_functions where funcid = 'security.provider_description_selection_v1(jsonb)'::regprocedure), 0) $f$;
create or replace function pg_temp.enqueue_calls() returns bigint language plpgsql as $f$
declare v_before bigint := pg_temp.sel_calls();
begin perform security.provider_description_enqueue_v1(); return pg_temp.sel_calls() - v_before; end $f$;
create or replace function pg_temp.q1() returns bigint language sql as $f$ select count(*) from pipeline.provider_description_reads where provider_id = pg_temp.pid(1) and state = 'queued' $f$;
-- n reads of providers that hold no profile, queued (the missing-description queue)
create or replace function pg_temp.fill(n int) returns void language sql as $f$ insert into pipeline.provider_description_reads(provider_id, state) select pg_temp.pid(k), 'queued' from unnest(array[5, 6, 7, 8, 9, 10, 11, 12]) with ordinality u(k, o) where o <= n $f$;

-- 1. the starvation: the queue is full of missing-description reads (queue_cap 2, two of them queued) and provider 1 holds a profile and has a page to read
-- the lane's selection calls with the upgrade switch OFF (the missing-description lane alone) is the baseline, from the same state
begin;
set local track_functions = 'all';
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.queue_cap', '2');
select pg_temp.fill(2);
select pg_temp.set_s('pdesc.registry_upgrade_on', '0');
select pg_temp.enqueue_calls() as base_full \gset
rollback;
begin;
set local track_functions = 'all';
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.queue_cap', '2'); select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
select pg_temp.fill(2);
select 'full_queue_lane_ran|' || (pg_temp.enqueue_calls() - :base_full);
select 'full_queue_provider1_queued|' || pg_temp.q1();
rollback;

-- 2. the queue is empty: the lane runs and queues the upgrade (as before)
begin;
set local track_functions = 'all';
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.registry_upgrade_on', '0');
select pg_temp.enqueue_calls() as base_empty \gset
rollback;
begin;
set local track_functions = 'all';
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
select 'empty_queue_lane_ran|' || (pg_temp.enqueue_calls() - :base_empty);
select 'empty_queue_provider1_queued|' || pg_temp.q1();
-- run again: the provider has a queued read now, so it is not queued twice
select 'empty_queue_again_provider1_queued|' || (pg_temp.enqueue_calls() is not null)::text || '|' || pg_temp.q1();
rollback;

-- 3. the lane's own queue is at its bound (queue_per_run 1, provider 1 already queued): no more upgrade reads are asked for, however short the whole queue is
begin;
set local track_functions = 'all';
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.queue_per_run', '1'); select pg_temp.set_s('pdesc.registry_upgrade_on', '0');
insert into pipeline.provider_description_reads(provider_id, state) values (pg_temp.pid(1), 'queued');
select pg_temp.enqueue_calls() as base_bound \gset
rollback;
begin;
set local track_functions = 'all';
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.queue_per_run', '1'); select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
insert into pipeline.provider_description_reads(provider_id, state) values (pg_temp.pid(1), 'queued');
select 'own_queue_at_bound_lane_ran|' || (pg_temp.enqueue_calls() - :base_bound);
select 'own_queue_at_bound_provider1_queued|' || pg_temp.q1();
rollback;

-- 4. the lane's own queue is below its bound (queue_per_run 2, one waiting): the lane asks again (for the difference)
begin;
set local track_functions = 'all';
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.queue_per_run', '2'); select pg_temp.set_s('pdesc.registry_upgrade_on', '0');
insert into pipeline.provider_description_reads(provider_id, state) values (pg_temp.pid(1), 'queued');
select pg_temp.enqueue_calls() as base_below \gset
rollback;
begin;
set local track_functions = 'all';
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.queue_per_run', '2'); select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
insert into pipeline.provider_description_reads(provider_id, state) values (pg_temp.pid(1), 'queued');
select 'own_queue_below_bound_lane_ran|' || (pg_temp.enqueue_calls() - :base_below);
rollback;

-- 5. other queued reads do not count against the lane (queue_per_run 1 and eight missing-description reads waiting, more than the lane's bound and than queue_cap 2)
begin;
set local track_functions = 'all';
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.queue_per_run', '1'); select pg_temp.set_s('pdesc.queue_cap', '2'); select pg_temp.set_s('pdesc.registry_upgrade_on', '0');
select pg_temp.fill(8);
select pg_temp.enqueue_calls() as base_many \gset
rollback;
begin;
set local track_functions = 'all';
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.queue_per_run', '1'); select pg_temp.set_s('pdesc.queue_cap', '2'); select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
select pg_temp.fill(8);
select 'many_queued_lane_ran|' || (pg_temp.enqueue_calls() - :base_many);
select 'many_queued_provider1_queued|' || pg_temp.q1();
rollback;

-- 6. the switch still decides: off, the lane never runs (provider 1 holds a profile and is a description held again); and the automatic mode off, the lane never runs
begin;
set local track_functions = 'all';
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.registry_upgrade_on', '0');
select pg_temp.enqueue_calls();
select 'switch_off_provider1_queued|' || pg_temp.q1();
rollback;
-- 7. a provider whose profile a person changed is not a profile: its queued read does not count, and a text that is not a profile is not offered
begin;
set local track_functions = 'all';
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.registry_upgrade_on', '1'); select pg_temp.set_s('pdesc.queue_per_run', '1');
insert into pipeline.provider_description_reads(provider_id, state) values (pg_temp.pid(1), 'queued');
update catalogue.providers set description = description || ' Edited by a person.' where id = pg_temp.pid(1);
select 'edited_profile_is_not_counted|' || coalesce(security.provider_description_basic_profile_v1(pg_temp.pid(1))::text, 'null') || '|' || (select count(*) from pipeline.provider_description_reads q where q.state = 'queued' and security.provider_description_basic_profile_v1(q.provider_id) is not null);
rollback;
