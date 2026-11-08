-- Guards: F-PDESC (QA B2): times each step of the whole-platform reader on the scale fixture (3,103 providers, 766 stored About pages, machine admission on, all three countries) and counts the per-provider checks a step makes.
-- Prints "time|<step>|<seconds>|<result>" and "calls|<step>|<function>|<n>"; tests/fixtures/pdesc-machine/run.sh asserts the budgets. Scratch database only.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned
set client_min_messages = warning;
create or replace function pg_temp.timed(p_name text, p_sql text) returns text language plpgsql as $f$
declare t0 timestamptz := clock_timestamp(); r text;
begin execute p_sql into r; return 'time|' || p_name || '|' || round(extract(epoch from clock_timestamp() - t0)::numeric, 2) || '|' || coalesce(left(r, 60), ''); end $f$;
-- the same, and the number of times the named functions ran in the step (the difference of this backend's statistics before and after, so calls not yet flushed from an earlier step are not counted)
create or replace function pg_temp.counted(p_name text, p_sql text) returns text language plpgsql as $f$
declare t0 timestamptz; r text; c record; o text; b jsonb;
begin
  select coalesce(jsonb_object_agg(funcname, calls), '{}'::jsonb) into b from pg_stat_xact_user_functions where funcname in ('provider_description_stored_v1', 'provider_description_identity_v1', 'provider_description_validate_v1', 'provider_description_scope_v1');
  t0 := clock_timestamp(); execute p_sql into r; o := 'time|' || p_name || '|' || round(extract(epoch from clock_timestamp() - t0)::numeric, 2) || '|' || coalesce(left(r, 60), '');
  for c in select funcname, calls from pg_stat_xact_user_functions where funcname in ('provider_description_stored_v1', 'provider_description_identity_v1', 'provider_description_validate_v1', 'provider_description_scope_v1') order by funcname loop
    o := o || E'\ncalls|' || p_name || '|' || c.funcname || '|' || (c.calls - coalesce((b->>c.funcname)::bigint, 0));
  end loop;
  return o;
end $f$;
update pipeline.platform_toolset_settings set value = '[]' where toolset_key = 'pipeline' and key in ('pdesc.provider_keys', 'pdesc.provider_types');
update pipeline.platform_toolset_settings set value = '["AU","NZ","CA"]' where toolset_key = 'pipeline' and key = 'pdesc.countries';
set fx.uid = '90000000-0000-0000-0000-000000000005';
select pg_temp.timed('scope_v1 over every provider', $$select count(*) from catalogue.providers p where security.provider_description_scope_v1(p.id)$$);
select pg_temp.timed('stored_v1 over every in-scope provider (reference)', $$select count(*) from catalogue.providers p where security.provider_description_scope_v1(p.id) and security.provider_description_stored_v1(p.id) is not null$$);
select pg_temp.timed('identity_v1 for 20 providers with a stored page', $$select count(*) from (select p.id, a.source_url from catalogue.providers p join pipeline.sources s on s.provider_id = p.id join pipeline.evidence_artifacts a on a.source_id = s.id where s.label = 'Stored institutional About page' order by p.id limit 20) z where (security.provider_description_identity_v1(z.id, z.source_url)->>'ok')::boolean$$);
select pg_temp.timed('selection_v1 older evaluation, every candidate (reference)', $$select security.provider_description_selection_v1('{"filter":"all","size":10,"prefilter":false}')->>'eligible'$$);
update pipeline.platform_toolset_settings set value = '1' where toolset_key = 'pipeline' and key = 'pdesc.machine_admit_on';
update pipeline.platform_toolset_settings set value = '1' where toolset_key = 'pipeline' and key = 'pdesc.registry_factual_on';
begin;
set local track_functions = 'all';
select pg_temp.counted('selection_v1 default list, size 60', $$select security.provider_description_selection_v1('{"size":60}')->>'eligible'$$);
commit;
select pg_temp.timed('throughput_v1', $$select security.provider_description_throughput_v1()->>'enqueue_size'$$);
begin;
set local track_functions = 'all';
select pg_temp.counted('funnel (rank 6 caller, 3,000 in scope)', $$select public.admin_provider_description_funnel_v1()->>'stall'$$);
commit;
begin;
set local track_functions = 'all';
select pg_temp.counted('enqueue_v1, stored mode, run 1', $$select security.provider_description_enqueue_v1()$$);
commit;
begin;
set local track_functions = 'all';
select pg_temp.counted('enqueue_v1, stored mode, run 2', $$select security.provider_description_enqueue_v1()$$);
commit;
select pg_temp.timed('queued after two runs', $$select count(*) from pipeline.provider_description_reads where state = 'queued'$$);
select pg_temp.timed('distinct providers looked at', $$select count(*) from pipeline.provider_description_scan_marks$$);
-- the first twenty are read (held here), then the next run must look at others: the rotation reaches providers not yet looked at
update pipeline.provider_description_reads set state = 'held', rule = 'fixture_done', reason = 'fixture' where state = 'queued';
select pg_temp.timed('enqueue_v1, stored mode, run 3', $$select security.provider_description_enqueue_v1()$$);
select pg_temp.timed('distinct providers looked at after run 3', $$select count(*) from pipeline.provider_description_scan_marks$$);
select pg_temp.timed('queued after run 3 that were not queued before', $$select count(*) from pipeline.provider_description_reads r where r.state = 'queued' and not exists (select 1 from pipeline.provider_description_reads o where o.provider_id = r.provider_id and o.rule = 'fixture_done')$$);
update pipeline.provider_description_reads set state = 'held', rule = 'fixture_done', reason = 'fixture' where state = 'queued';
update pipeline.platform_toolset_settings set value = '1' where toolset_key = 'pipeline' and key = 'pdesc.acquire_direct';
select pg_temp.timed('enqueue_v1, direct mode', $$select security.provider_description_enqueue_v1()$$);
select pg_temp.timed('lease: svc_provider_description_next', $$select jsonb_array_length(public.svc_provider_description_lease_v1(3, null, 'provider-description-reserve-v1')->'items')$$);
select pg_temp.timed('registry tier run', $$select security.provider_description_registry_tier_v1()::text$$);
select pg_temp.timed('machine report', $$select security.provider_description_machine_report_v1()->'parity'->>'admitted'$$);
update pipeline.platform_toolset_settings set value = '0' where toolset_key = 'pipeline' and key = 'pdesc.acquire_direct';
select pg_temp.timed('fire_v1 (whole run)', $$select security.provider_description_fire_v1()::text$$);
