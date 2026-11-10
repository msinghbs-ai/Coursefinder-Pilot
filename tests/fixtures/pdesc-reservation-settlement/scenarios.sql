-- Guards: Platform Admin operating model v1.5 (10 Nov 2026, delivery first), the AI reservation leak of the provider reader: a reservation that nothing is working on is SETTLED by security.provider_description_settle_abandoned_v1 (called by the fire before it requeues), never released on the assumption that no call was made and never counted as free. The cost is the dearer of pdesc.read_cost_floor_usd and the observed cost of a read, never more than the reservation; the existing trigger writes the ledger row; a live lease is untouched; the run is idempotent and bounded by pdesc.queue_cap; a read that was reading with an expired lease is held existing_cost_reservation_uncertain and the fire returns it to the queue; the budget the stuck reservations used is free again.
-- Fixture data only (the pdesc-machine harness: fictional providers, no live data). Prints "<scenario>|<result>" lines; every block rolls back. Run by tests/fixtures/pdesc-reservation-settlement/run.sh.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

create or replace function pg_temp.pid(n int) returns uuid language sql as $f$ select id from catalogue.providers where stable_key = 'fixture:provider:' || n::text $f$;
create or replace function pg_temp.set_s(k text, v jsonb) returns void language sql as $f$ update pipeline.platform_toolset_settings set value = v where toolset_key = 'pipeline' and key = k $f$;
-- a read of fixture provider n: state, lease (minutes from now, null for none), reservation, calls made, cost recorded
create or replace function pg_temp.mk(n int, p_state text, p_lease_min int, p_reserved numeric, p_calls int default 0, p_cost numeric default 0, p_rule text default null) returns void language sql as $f$
  insert into pipeline.provider_description_reads(provider_id, state, leased_until, reserved_usd, ai_calls, cost_usd, rule, updated_at, created_at)
  values (pg_temp.pid(n), p_state, case when p_lease_min is null then null else now() + make_interval(mins => p_lease_min) end, p_reserved, p_calls, p_cost, p_rule, now() - make_interval(secs => n), now()) $f$;
-- state|rule|reserved|calls|cost|ledger rows summed for the read|settlement basis|leased
create or replace function pg_temp.rd(n int) returns text language sql as $f$
  select concat_ws('|', r.state, coalesce(r.rule, '-'), 'reserved=' || r.reserved_usd::numeric(10,5), 'calls=' || r.ai_calls, 'cost=' || r.cost_usd::numeric(10,5),
                   'ledger=' || coalesce((select sum(l.cost_usd) from pipeline.ai_spend_ledger l where l.source_id = r.id::text), 0)::numeric(10,5),
                   coalesce(r.checks->'reservation_settlement'->>'basis', '-'), 'lease=' || (r.leased_until is not null)::text)
    from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(n) order by r.created_at desc, r.id limit 1 $f$;
create or replace function pg_temp.ledger() returns numeric language sql as $f$ select coalesce(sum(cost_usd), 0)::numeric(10,5) from pipeline.ai_spend_ledger where lane = 'provider_description' $f$;
create or replace function pg_temp.settle() returns int language sql as $f$ select security.provider_description_settle_abandoned_v1() $f$;

-- 1. the leak as it is on live: reservations on held reads (no lease), an expired lease, a live lease, a failed read kept queued, a finished read whose cost was unknown; the observed cost of a read is below the floor
begin;
select pg_temp.mk(2, 'admitted', null, 0, 1, 0.0008);
select pg_temp.mk(3, 'held', null, 0.007, 0, 0, 'existing_cost_reservation_uncertain');
select pg_temp.mk(4, 'reading', -5, 0.007);
select pg_temp.mk(5, 'reading', 10, 0.007);
select pg_temp.mk(6, 'queued', null, 0.002);
select pg_temp.mk(7, 'proposed', null, 0.0055, 1, 0.0007);
select pg_temp.mk(8, 'queued', null, 0);
select 'floor_case_ledger_before|' || pg_temp.ledger();
select 'floor_case_settled|' || pg_temp.settle();
select 'floor_case_held_by_uncertainty|' || pg_temp.rd(3);
select 'floor_case_reading_expired|' || pg_temp.rd(4);
select 'floor_case_reading_live_untouched|' || pg_temp.rd(5);
select 'floor_case_below_floor_reservation_is_the_cap|' || pg_temp.rd(6);
select 'floor_case_finished_read_with_unknown_cost|' || pg_temp.rd(7);
select 'floor_case_no_reservation_untouched|' || pg_temp.rd(8);
select 'floor_case_ledger_after|' || pg_temp.ledger();
select 'floor_case_settlement_detail|' || (select concat_ws('|', c->>'floor_usd', c->>'state_before', c->>'ai_calls_before', c->>'reserved_usd', c->>'settled_usd', (c->>'at') is not null) from (select checks->'reservation_settlement' c from pipeline.provider_description_reads where provider_id = pg_temp.pid(4)) z);
-- applied again: nothing is settled twice
select 'again_settled|' || pg_temp.settle();
select 'again_ledger|' || pg_temp.ledger();
select 'again_read|' || pg_temp.rd(3);
rollback;

-- 2. the observed cost of a read is above the floor: the dearer of the two is used, never more than the reservation
begin;
select pg_temp.mk(2, 'admitted', null, 0, 1, 0.0300);
select pg_temp.mk(3, 'held', null, 0.007, 0, 0, 'existing_cost_reservation_uncertain');
select pg_temp.mk(4, 'queued', null, 0.0500, 1, 0.0100);
select pg_temp.mk(5, 'queued', null, 0.002);
select 'observed_case_average|' || (select (sum(cost_usd) / nullif(count(*) filter (where ai_calls > 0), 0))::numeric(10,5) from pipeline.provider_description_reads);
select 'observed_case_settled|' || pg_temp.settle();
select 'observed_case_capped_by_reservation|' || pg_temp.rd(3);
select 'observed_case_dearer_than_floor|' || pg_temp.rd(4);
select 'observed_case_small_reservation|' || pg_temp.rd(5);
rollback;

-- 3. the batch is bounded by pdesc.queue_cap, oldest first, and the rest follows on the next runs
begin;
select pg_temp.set_s('pdesc.queue_cap', '2'::jsonb);
select pg_temp.mk(n, 'held', null, 0.007, 0, 0, 'existing_cost_reservation_uncertain') from generate_series(2, 6) n;
select 'bound_run_1|' || pg_temp.settle();
select 'bound_oldest_first|' || (select string_agg(pg_temp.rd(n), ' / ' order by n) from generate_series(6, 5, -1) n);
select 'bound_newest_waits|' || pg_temp.rd(2);
select 'bound_run_2|' || pg_temp.settle();
select 'bound_run_3|' || pg_temp.settle();
select 'bound_run_4|' || pg_temp.settle();
select 'bound_ledger|' || pg_temp.ledger();
rollback;

-- 4. the budget the stuck reservations used is free again (ceiling US$0.30: 70 stuck reservations of US$0.007 and a live read that asks for a reservation)
begin;
select pg_temp.set_s('pdesc.ai_usd_max', '0.30'::jsonb);
select pg_temp.set_s('pdesc.queue_cap', '100'::jsonb);
insert into pipeline.ai_spend_ledger(lane, source, source_id, cost_usd) values ('provider_description', 'provider_description_reads', 'fixture', 0.0982);
select pg_temp.mk(n, 'held', null, 0.007, 0, 0, 'existing_cost_reservation_uncertain') from generate_series(2, 18) n where pg_temp.pid(n) is not null and n not in (16, 17);
update pipeline.provider_description_reads set reserved_usd = 0.4 where provider_id = pg_temp.pid(2);
select pg_temp.mk(1, 'reading', 10, 0);
create or replace function pg_temp.reserve() returns text language sql as $f$
  select concat_ws('|', g->>'ok', g->>'reason') from (select public.svc_provider_description_reserve_v1((select id from pipeline.provider_description_reads where provider_id = pg_temp.pid(1)),
         (select model_identifier from pipeline.central_ai_settings where id = 1), 0.007, 'fixture-hash') g) z $f$;
select 'before_settlement_reserve|' || pg_temp.reserve();
select 'before_settlement_reserved_total|' || (select sum(reserved_usd)::numeric(10,4) from pipeline.provider_description_reads);
select 'settled|' || pg_temp.settle();
select 'after_settlement_reserved_total|' || (select sum(reserved_usd)::numeric(10,4) from pipeline.provider_description_reads);
select 'after_settlement_reserve|' || pg_temp.reserve();
rollback;

-- 5. the fire returns a settled, expired read to the queue (the requeue it already makes: state held, that rule, reserved_usd = 0) and gives its try back
begin;
select pg_temp.mk(2, 'reading', -5, 0.007);
update pipeline.provider_description_reads set tries = 2 where provider_id = pg_temp.pid(2);
select 'fire_before|' || pg_temp.rd(2);
select 'fire_ran|' || (security.provider_description_fire_v1() is not null)::text;
select 'fire_after|' || pg_temp.rd(2) || '|tries=' || (select tries from pipeline.provider_description_reads where provider_id = pg_temp.pid(2)) || '|next_try_later=' || (select (next_try_at > now())::text from pipeline.provider_description_reads where provider_id = pg_temp.pid(2));
rollback;

-- 6. a person or the web cannot call it
select 'privileges|' || concat_ws('|', has_function_privilege('anon', 'security.provider_description_settle_abandoned_v1()', 'execute')::text, has_function_privilege('authenticated', 'security.provider_description_settle_abandoned_v1()', 'execute')::text,
  (select p.prosecdef::text from pg_proc p where p.oid = 'security.provider_description_settle_abandoned_v1()'::regprocedure), (select p.proconfig::text from pg_proc p where p.oid = 'security.provider_description_settle_abandoned_v1()'::regprocedure));
