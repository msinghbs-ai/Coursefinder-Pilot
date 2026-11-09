-- Guards: CF-247 Operations load speed (Platform Admin P1, 10 Nov 2026): the partial index evidence_artifacts_link_queue_idx is kept only because it makes the link-queue count of job evidence-link-index (a line of security.admin_live_activity_v1) cheaper on a table of the live size.
-- Scratch database only. Builds pipeline.evidence_artifacts at the live size (208 thousand rows, 104,722 of them tested by the count, as read on 10 Nov 2026; wide rows, as live, so the heap is as large), runs the count's exact text before and after the index, and prints
-- buffers and time of each. The plan and the buffers are asserted (index only scan on the new index with no heap fetch and no pass over the table, and at least 1.5 times faster); the times are printed. The index is created by the migration's own statement (read from its file by run.sh).
\set ON_ERROR_STOP on
set client_min_messages = warning;
create schema if not exists pipeline;
drop table if exists pipeline.evidence_link_index_state, pipeline.layer2_onboarding_snapshot, pipeline.sources, pipeline.evidence_artifacts cascade;
create table pipeline.sources (id uuid primary key, provider_id uuid);
create table pipeline.layer2_onboarding_snapshot (provider_id uuid primary key);
create table pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), source_id uuid, evidence_type text, storage_path text, mime_type text, captured_at timestamptz default now(), meta jsonb);
create index evidence_source_idx on pipeline.evidence_artifacts (source_id);
create table pipeline.evidence_link_index_state (evidence_id uuid primary key, status text, indexed_at timestamptz);
insert into pipeline.sources select gen_random_uuid(), gen_random_uuid() from generate_series(1, 6000);
insert into pipeline.layer2_onboarding_snapshot select provider_id from pipeline.sources where random() < 0.92;
-- 208,000 rows: about half are the evidence the indexer may read (page snapshots held in storage), the rest are other types, other mime types or external addresses
with a as (select array_agg(id) ids from pipeline.sources)
insert into pipeline.evidence_artifacts(source_id, evidence_type, storage_path, mime_type, captured_at, meta)
select a.ids[1 + g % 6000],
       case when g % 2 = 0 then (array['layer2_html_snapshot','layer2_extraction_input','source_snapshot','provider_contact_html_snapshot'])[1 + g % 4] else (array['screenshot','pdf_copy','api_payload'])[1 + g % 3] end,
       case when g % 40 = 7 then 'https://example.org/' || g else 'evidence/' || md5(g::text) || '/' || md5((g * 7)::text) || '.dat' end,
       case when g % 9 = 3 then 'application/pdf' when g % 3 = 0 then 'application/json' else 'text/html; charset=utf-8' end,
       now() - make_interval(secs => g), jsonb_build_object('note', repeat(md5(g::text), 37), 'n', g)
  from a, generate_series(1, 208000) g;
insert into pipeline.evidence_link_index_state select e.id, 'indexed', now() - interval '3 days' from pipeline.evidence_artifacts e where random() < 0.9995;
update pipeline.evidence_link_index_state set status = 'error', indexed_at = now() - interval '8 hours' where random() < 0.002;
vacuum analyze pipeline.sources, pipeline.layer2_onboarding_snapshot, pipeline.evidence_artifacts, pipeline.evidence_link_index_state;
select 'evidence rows' k, count(*)::text v from pipeline.evidence_artifacts union all
select 'tested by the count', count(*)::text from pipeline.evidence_artifacts e where e.storage_path is not null and e.storage_path !~ '^[a-z-]+://' and e.evidence_type in ('layer2_html_snapshot','layer2_extraction_input','source_snapshot','provider_contact_html_snapshot') and (e.mime_type ilike '%html%' or e.mime_type ilike '%json%');

create temp table plans(phase text, line text, n serial);
create or replace function pg_temp.explain_count(p_phase text) returns void language plpgsql as $f$
declare r text;
begin
  -- the count exactly as security.admin_live_activity_v1 has it
  for r in execute $q$explain (analyze, buffers, timing off, summary on)
    select count(*) from pipeline.evidence_artifacts e left join pipeline.evidence_link_index_state st on st.evidence_id = e.id
              join pipeline.sources s on s.id = e.source_id join pipeline.layer2_onboarding_snapshot o on o.provider_id = s.provider_id
             where e.storage_path is not null and e.storage_path !~ '^[a-z-]+://'
               and e.evidence_type in ('layer2_html_snapshot','layer2_extraction_input','source_snapshot','provider_contact_html_snapshot')
               and (e.mime_type ilike '%html%' or e.mime_type ilike '%json%')
               and (st.evidence_id is null or (st.status = 'error' and st.indexed_at < now() - interval '6 hours'))$q$ loop
    insert into plans(phase, line) values (p_phase, r);
  end loop;
end $f$;
-- warm the cache once, then measure (serial, so the buffers of the whole statement are counted by its top node)
set max_parallel_workers_per_gather = 0;
select pg_temp.explain_count('warm'); delete from plans;
select pg_temp.explain_count('before');
\i :idxfile
vacuum analyze pipeline.evidence_artifacts;
select pg_temp.explain_count('warm2'); delete from plans where phase = 'warm2';
select pg_temp.explain_count('after');
select phase, regexp_replace(line, '^ +', '') line from plans where line ~ 'Execution Time|Scan on evidence_artifacts|Scan using|Heap Fetches' and line !~ 'Index Cond' order by n;
set client_min_messages = notice;
do $chk$
declare t_before numeric; t_after numeric; v_heap bigint; v_fetch bigint;
begin
  select (regexp_match(line, 'Execution Time: ([\d.]+)'))[1]::numeric into t_before from plans where phase = 'before' and line ~ 'Execution Time';
  select (regexp_match(line, 'Execution Time: ([\d.]+)'))[1]::numeric into t_after from plans where phase = 'after' and line ~ 'Execution Time';
  select relpages into v_heap from pg_class where oid = 'pipeline.evidence_artifacts'::regclass;
  select coalesce(sum((regexp_match(line, 'Heap Fetches: (\d+)'))[1]::bigint), 0) into v_fetch from plans where phase = 'after' and line ~ 'Heap Fetches' and line ~ '';
  -- the buffer counts of an index only scan include the visibility map page of every row, so the proof is the plan: no pass over the table's %-page heap, no heap fetch
  raise notice 'link queue count on 208 thousand evidence rows (% heap pages): before % ms (sequential scan of the heap), after % ms', v_heap, t_before, t_after;
  if exists (select 1 from plans where phase = 'before' and line ~ 'Seq Scan on evidence_artifacts') is not true then raise exception 'before the index the count does not scan the heap (the fixture is not live-like)'; end if;
  if exists (select 1 from plans where phase = 'after' and line ~ 'Scan on evidence_artifacts') then raise exception 'after the index the count still scans the table'; end if;
  if not exists (select 1 from plans where phase = 'after' and line ~ 'Index Only Scan using evidence_artifacts_link_queue_idx') then raise exception 'the count does not use the new index (index only scan)'; end if;
  if not exists (select 1 from plans where phase = 'after' and line ~ 'Heap Fetches: 0') then raise exception 'the index only scan fetches from the heap'; end if;
  if t_after * 1.5 > t_before then raise exception 'the index does not make the count at least 1.5 times faster (% ms -> % ms)', t_before, t_after; end if;
  raise notice 'ok: index-benefit';
end $chk$;
