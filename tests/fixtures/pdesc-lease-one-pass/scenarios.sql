-- Guards: F-PDESC Directive 3 (Platform Admin, 9 Nov 2026), lease statement time-out: migration 20261109182000 finds each provider's stored About copy once; the lease hands out the same items, in the same order, with the same content, as before.
-- Fixture data only (the pdesc-claim-context database: 18 fictional providers, 17 About copies). Prints "<scenario>|<result>" lines; every block rolls back. The same file runs BEFORE and AFTER the migration and must print the same lines. Run by tests/fixtures/pdesc-lease-one-pass/run.sh.
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

-- 1 handing out, manual mode (machine admission off): up to five of the eight the setting allows, oldest first, each with its stored About copy
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '0'); select pg_temp.set_s('batch.provider_description', '8'); select pg_temp.queue_all();
select pg_temp.out('manual_five', pg_temp.lease(5));
rollback;

-- 2 handing out, automatic mode: the same providers in the order of the per-country rate, ten items
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.set_s('batch.provider_description', '10'); select pg_temp.queue_all();
select pg_temp.out('machine_ten', pg_temp.lease(10));
rollback;

-- 3 a provider whose only copy is not at an About address is not handed out (no copy: nothing to read while direct acquisition is off); the others still are
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '0'); select pg_temp.queue_all();
update pipeline.evidence_artifacts set source_url = 'https://p1.example.edu/news/story' where source_url = 'https://p1.example.edu/about';
select pg_temp.out('not_about_address', pg_temp.lease(4));
rollback;

-- 4 an address with an underscore About prefix (about_us) and an upper-case About name are copies; a path with too many parts, or one that only contains the word, is not
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '0'); select pg_temp.queue_all();
update pipeline.evidence_artifacts set source_url = 'https://p1.example.edu/about_us' where source_url = 'https://p1.example.edu/about';
update pipeline.evidence_artifacts set source_url = 'https://p2.example.edu/ABOUT' where source_url = 'https://p2.example.edu/about';
update pipeline.evidence_artifacts set source_url = 'https://p3.example.edu/study/our/story/about' where source_url = 'https://p3.example.edu/about';
update pipeline.evidence_artifacts set source_url = 'https://p4.example.edu/aboutface' where source_url = 'https://p4.example.edu/about';
select pg_temp.out('address_shapes', pg_temp.lease(6));
rollback;

-- 5 a copy older than the governed age (pdesc.source_max_age_days) is no copy
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '0'); select pg_temp.queue_all();
update pipeline.evidence_artifacts set captured_at = now() - interval '2 years', created_at = now() - interval '2 years' where source_url = 'https://p1.example.edu/about';
select pg_temp.out('old_copy', pg_temp.lease(3));
rollback;

-- 6 a read whose lease ran out is handed out again, with its stored copy (the lost worker call)
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '0'); select pg_temp.queue_all();
update pipeline.provider_description_reads set state = 'reading', tries = 1, leased_until = now() - interval '1 minute', next_try_at = now() - interval '5 hours' where provider_id = pg_temp.pid(7);
select pg_temp.out('lease_ran_out', pg_temp.lease(3));
rollback;

-- 7 a read whose lease is still running is not handed out
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '0'); select pg_temp.queue_all();
update pipeline.provider_description_reads set state = 'reading', tries = 1, leased_until = now() + interval '10 minutes' where provider_id = pg_temp.pid(1);
select pg_temp.out('lease_running', pg_temp.lease(2));
rollback;

-- 8 a stored copy of a provider with open work is also found when the provider has several copies: the newest one that passes the page rule is used
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '0'); select pg_temp.queue_all();
insert into pipeline.evidence_artifacts(id, source_id, evidence_type, source_url, storage_path, mime_type, captured_at, content_hash)
  select '00000000-0000-0000-0000-0000000000e2'::uuid, s.id, 'official_page', 'https://p2.example.edu/overview', 'fixture/overview-2.html', 'text/html', date_trunc('day', now()) + interval '23 hours 59 minutes', 'fixture-newer-hash' from pipeline.sources s where s.provider_id = pg_temp.pid(2) limit 1;
select pg_temp.out('newest_copy', pg_temp.lease(3));
rollback;

-- 9 nothing queued: nothing handed out, and nothing is asked
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '0');
select pg_temp.out('nothing_queued', pg_temp.lease(5));
rollback;
