-- Guards: F-PDESC (P0, Platform Admin 9 Nov 2026), lease and record time-outs: migration 20261109233000 gives the same picks, items, order and results as before (lazy pick, sweep source found once, identity asked once).
-- Fixture data only (the pdesc-claim-context database: 18 fictional providers, 17 About copies). Prints "<scenario>|<result>" lines; every block rolls back. The same file runs BEFORE and AFTER the migration and must print the same lines. Run by tests/fixtures/pdesc-lease-record-timeouts/run.sh.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

create or replace function pg_temp.pid(n int) returns uuid language sql as $f$ select id from catalogue.providers where stable_key = 'fixture:provider:' || case when n = 13 then 'browser' else n::text end $f$;
create or replace function pg_temp.set_s(k text, v jsonb) returns void language sql as $f$ update pipeline.platform_toolset_settings set value = v where toolset_key = 'pipeline' and key = k $f$;
create or replace function pg_temp.out(label text, v anyelement) returns void language plpgsql as $f$ begin raise notice '%|%', label, v; end $f$;
create or replace function pg_temp.queue(n int) returns void language plpgsql as $f$
begin insert into pipeline.provider_description_reads(provider_id, state) select pg_temp.pid(n), 'queued' on conflict do nothing; end $f$;
-- the lease as the worker calls it; the providers it hands out in order, each with the address of its stored copy, and a digest of the whole answer without the random item ids
create or replace function pg_temp.lease(p_limit int) returns text language plpgsql as $f$
declare r jsonb; v_keys text; v_dig text;
begin
  r := public.svc_provider_description_lease_v1(p_limit, null, 'provider-description-reserve-v1');
  select coalesce(string_agg(p.stable_key || '=' || coalesce(e->'stored'->>'url', '-'), ',' order by o), '(none)') into v_keys
    from jsonb_array_elements(coalesce(r->'items', '[]'::jsonb)) with ordinality t(e, o) join catalogue.providers p on p.id = (e->>'provider_id')::uuid;
  select md5(coalesce(jsonb_agg(e - 'item_id' order by o)::text, '') || (r - 'items')::text) into v_dig from jsonb_array_elements(coalesce(r->'items', '[]'::jsonb)) with ordinality t(e, o);
  return v_keys || ' idle=' || coalesce(r->>'reason', '-') || ' digest=' || v_dig;
end $f$;
-- queue providers 1 to 12 (the fixture's scope), oldest first by their number
create or replace function pg_temp.queue_all() returns void language plpgsql as $f$
declare n int;
begin for n in 1..12 loop perform pg_temp.queue(n); update pipeline.provider_description_reads set next_try_at = now() - make_interval(mins => 100 - n), created_at = now() - make_interval(mins => 100 - n) where provider_id = pg_temp.pid(n); end loop; end $f$;

-- the record as the worker calls it: two leased reads, one with a page the worker read and stored now on the provider's own host (registered as evidence), one with an error (queued again); a digest of the result
create or replace function pg_temp.record_two() returns text language plpgsql as $f$
declare r jsonb; v_res jsonb := '[]'; v_tally jsonb; e jsonb; i int := 0; v_ev int; v_states text;
begin
  r := public.svc_provider_description_lease_v1(2, null, 'provider-description-reserve-v1');
  for e in select * from jsonb_array_elements(r->'items') loop
    i := i + 1;
    -- the page of the first read is already stored under the provider's sweep source, so the record finds it by its hash and registers nothing new
    if i = 1 then
      insert into pipeline.evidence_artifacts(source_id, evidence_type, source_url, storage_path, content_hash, mime_type)
      values (security.coverage_sweep_source((e->>'provider_id')::uuid), 'source_snapshot', 'https://' || (e->'hosts'->>0) || '/about', 'fixture/new-page.html', repeat('a', 64), 'text/html');
    end if;
    v_res := v_res || case when i = 1 then jsonb_build_array(jsonb_build_object('item_id', e->>'item_id', 'rule', 'no_about_page', 'reason', 'fixture',
                    'fetch', jsonb_build_object('status', 'read', 'storage_path', 'fixture/new-page.html', 'sha256', repeat('a', 64), 'url', 'https://' || (e->'hosts'->>0) || '/about', 'via', 'direct')))
                else jsonb_build_array(jsonb_build_object('item_id', e->>'item_id', 'error', 'fixture error')) end;
  end loop;
  v_tally := public.svc_provider_description_record(v_res);
  select count(*) into v_ev from pipeline.evidence_artifacts where content_hash = repeat('a', 64);
  select string_agg(p.stable_key || '=' || x.state || '/' || coalesce(x.rule, '-') || '/' || (x.evidence_id is not null)::text, ',' order by p.stable_key) into v_states
    from pipeline.provider_description_reads x join catalogue.providers p on p.id = x.provider_id where x.id in (select (it->>'item_id')::uuid from jsonb_array_elements(r->'items') it);
  return 'tally=' || v_tally::text || ' evidence=' || v_ev || ' ' || coalesce(v_states, '-');
end $f$;

-- 10 a provider that is out of scope and queued first is skipped; the next in order are handed out
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '0'); select pg_temp.queue_all();
update catalogue.providers set lifecycle_status = 'inactive' where id = pg_temp.pid(2);
select pg_temp.out('scope_skip', pg_temp.lease(3));
rollback;

-- 11 a provider that is not published is skipped (the identity test needs a published provider)
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.set_s('batch.provider_description', '10'); select pg_temp.queue_all();
update catalogue.providers set publication_status = 'draft' where id = pg_temp.pid(1);
select pg_temp.out('draft_skip', pg_temp.lease(4));
rollback;

-- 12 the limit is the setting when it is smaller than the call's limit, and the limit is reached with the dear tests stopping there
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '0'); select pg_temp.set_s('batch.provider_description', '2'); select pg_temp.queue_all();
select pg_temp.out('setting_limit', pg_temp.lease(9));
rollback;

-- 13 the record: a page read now on the own host is found by its hash under the sweep source (nothing new is registered); an error queues the read again
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '0'); select pg_temp.queue_all();
select pg_temp.out('record_direct', pg_temp.record_two());
rollback;
