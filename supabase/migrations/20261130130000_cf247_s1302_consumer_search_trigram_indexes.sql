-- CF-247 s1302 (S1-API-Frontend-Delivery; SS-Programme-Control 27 Nov 2026 12:08 AEDT, IQ-00615 "Consumer Search Performance").
-- Read live 27 Nov 2026 12:30 to 13:10 AEDT:
--   * IQ-00615 (P1, since 19 Nov, three regressions): the consumer snapshot probe security.consumer_api_snapshot_v1 skips search_master_page2 ("time budget",
--     6000 ms) whenever the free-text search before it (search_bachelor_au) is slow. In the last 14 recorded runs search_bachelor_au took 3.4 to 7.7 s when
--     the page cache was cold (before-batch runs) and 1.5 to 2.1 s warm; the skip is a symptom, the probe order and its shared budget are not the cause.
--   * The same frozen search is what consumers call. pipeline.api_requests, last 7 days: website v2 search p50 3.7 s, p95 10.0 s, max 26.4 s (992 calls);
--     website v3 search p50 4.6 s, p95 17.3 s, 25 server errors (520 calls); Zoho v2 search p95 11.2 s (33 calls).
--   * Cause: api.zoho_course_search_v2 (behind zoho_edge_course_search_v2, zoho_v2_course_search, website_v2_course_search and website_v3_course_search_core)
--     filters free text as  search_tsv @@ q  OR  course_title ILIKE '%q%'  OR  provider_name ILIKE '%q%'  OR  lower(course_code) = q  OR  lower(course_stable_key) = q.
--     The two ILIKE arms have no index, so the planner reads every Australian row of search.course_documents (24 to 26 thousand heap rows, 10.6 thousand
--     blocks, 56 thousand buffer hits for one count) and detoasts search_tsv on each. Live heap is 115 MB against 62 MB compact (46% dead space from about
--     9 million updates and 1.1 million deletes since the table was built), so a cold cache costs several seconds.
--   * Measured on a temporary copy of the live table (identical rows, the same predicate, Australia): with course_title and provider_name trigram indexes
--     the same predicate returned the same rows (count and md5 of the course keys equal for bachelor, master, nursing, engineering) in
--     123 ms (bachelor, was 671), 101 ms (master, was 674), 46 ms (engineering, was 596), 10 ms (nursing, was 748), 0.4 ms (no match, was 544).
-- What it changes: two GIN trigram indexes on search.course_documents (course_title, provider_name; 5.1 MB and 3.6 MB), a fresh ANALYZE, and one recovery
--   knowledge row so the lesson is held where the platform learns (pipeline.ops_remedy_knowledge). The other three arms already have indexes
--   (course_documents_tsv_idx, course_documents_course_code_lower_idx, course_documents_stable_key_lower_idx), so the planner can answer the whole OR from
--   indexes. No function, column, grant or result changes; the probe, its 6000 ms budget and its acceptance check are untouched (not weakened).
-- G1: no job. G2: no value in code (the probe budget stays the setting admit.consumer_snapshot_budget_ms). G3: indexes only; the 75 functions and 48 relations
--   are checked before and after, and no frozen function or table shape is created, altered or dropped (precedent: course_documents_title_lower_idx).
-- Replaces: nothing (no function or table is replaced; an index is added beside the data). Retires: nothing.
set local lock_timeout = '10s';  -- fixed: lock wait for the index build (it blocks writes to the table for a few seconds, reads continue)

create temp table s1302_guard on commit drop as select (select count(*) from pipeline.manual_locks) locks_before;
create temp table s1302_cron on commit drop as select jobid from cron.job;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v; end if;
  if not exists (select 1 from pg_extension where extname = 'pg_trgm') then raise exception 'guard: pg_trgm is not installed'; end if;
end $g$;

create index if not exists course_documents_title_trgm_idx on search.course_documents using gin (course_title extensions.gin_trgm_ops);
create index if not exists course_documents_provider_name_trgm_idx on search.course_documents using gin (provider_name extensions.gin_trgm_ops);
comment on index search.course_documents_title_trgm_idx is 'CF-247 s1302 (IQ-00615): lets course_title ILIKE ''%q%'' in the consumer free-text search use an index (OR with search_tsv, code and key indexes); do not drop.';
comment on index search.course_documents_provider_name_trgm_idx is 'CF-247 s1302 (IQ-00615): lets provider_name ILIKE ''%q%'' in the consumer free-text search use an index; do not drop.';
analyze search.course_documents;

-- the lesson, in the existing recovery knowledge (the closure harvest, s1294, adds the outcome when IQ-00615 closes)
insert into pipeline.ops_remedy_knowledge (code, lane, title, fingerprint_like, root_cause, remedy_code, trigger_conditions, authority, performed_by, expected_outcome,
  no_retry_condition, reuse_conditions, auto_eligible, eligibility_reason, eligibility_changed_at, eligibility_changed_by, seeded_from)
values ('consumer_search:unindexed_free_text:latency', 'platform', 'Consumer free-text search slow: an OR of ILIKE arms with no index (probe skipped on its time budget)',
  array['health:consumer_snapshot:%'], 'unindexed_free_text_search', 'fix_in_release',
  '{"signal": "consumer_snapshot probe skipped on its time budget, the preceding free-text search read (search_bachelor_au) over about 3 s", "confirm": "pipeline.api_requests p95 for search above 5 s; EXPLAIN shows a bitmap heap scan on the country index with the text predicate as a Filter and a high Rows Removed by Filter", "negative_control": "a filter-only search (no query text) is not affected"}'::jsonb,
  'release', 'claude_engineering',
  'free-text search answered from indexes: warm under 150 ms and cold under 1 s on the Australian slice, the probe runs every read and the check stays green for 24 hours',
  'do not raise the probe time budget or statement timeout, drop or reorder reads, or mark a skipped read as passed: that hides the latency consumers see. Fix the read.',
  'any consumer search predicate that ORs ILIKE ''%q%'' arms or other unindexed expressions over search.course_documents; check pg_trgm indexes exist before adding a new text column to the search; read EXPLAIN with Buffers on the real predicate, not on the probe',
  false, 'index and read-path change through a release; not an automatic remedy', now(), 'S1-API-Frontend-Delivery (s1302)', 'IQ-00615 (27 Nov 2026)')
on conflict (code) do nothing;

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
  if (select count(*) from pg_indexes where schemaname = 'search' and tablename = 'course_documents' and indexname in ('course_documents_title_trgm_idx', 'course_documents_provider_name_trgm_idx')) <> 2 then raise exception 'post-check: the trigram indexes are not both in place'; end if;
  if exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid where c.relname in ('course_documents_title_trgm_idx', 'course_documents_provider_name_trgm_idx') and not i.indisvalid) then raise exception 'post-check: a trigram index is not valid'; end if;
  if not exists (select 1 from pipeline.ops_remedy_knowledge where code = 'consumer_search:unindexed_free_text:latency' and not auto_eligible) then raise exception 'post-check: the lesson is not held'; end if;
  if exists (select 1 from cron.job j where not exists (select 1 from s1302_cron b where b.jobid = j.jobid)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1302_guard) then raise exception 'post-check: manual locks changed'; end if;
end $c$;
