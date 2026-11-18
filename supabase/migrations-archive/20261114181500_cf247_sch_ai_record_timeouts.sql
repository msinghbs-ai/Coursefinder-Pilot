-- CF-247 R5: paid scholarship AI answers commit on the first pass (public.svc_scholarship_ai_record stays inside the worker's 8 s statement limit).
-- Evidence (live, 14 Nov 2026; postgres logs 13 Nov 06:30 to 14 Nov 06:30 UTC, PostgREST calls of svc_scholarship_ai_record cancelled with
--   "canceling statement due to statement timeout", 188 in 24 hours). The paid answer is rolled back with the call, so the page is re-queued and paid for again.
--   1. 134 (71%) waited for the search-document writer lock: security.scholarship_sweep_apply_v1 (127) and security.scholarship_admission_withdraw_v1 (7)
--      call search.refresh_course_enrichment_scoped_v1(courses, true) inside the call, which waits on pg_advisory_xact_lock('cf247:search_course_documents_writer').
--      Job search-refresh-requested (6-59/10) holds that lock for its full refresh: p50 84 s, up to the 120 s limit (427 of 514 runs in 14 days over 2 s).
--      The cancellations cluster in minutes :x6 to :x8 of every ten.
--   2. 36 (19%) were the scoped refresh's own work (staging, the course_documents update, row locks on course_documents). The refresh costs about 60 ms a
--      course; one sweep changed up to 563 course links (41,504 course links changed in 24 hours over 516 changes), so it can never fit in 8 s.
--   3. 12 (6%) were the v_prev lookup in svc_scholarship_ai_record (the earlier model's value in the same root chain): a join on
--      coalesce(x.root_id, x.id) with no index on pipeline.scholarship_ai_extractions.queue_id scans the 176 MB table backwards (2.6 to 3.9 s measured).
--   4. 6 (3%) were the sweep's own course matching (scholarship_course_title_match_v1, scholarship_url_norm). Not changed here; measured again after.
--   Ruled out: the inserts into pipeline.evidence_artifacts and pipeline.scholarship_ai_extractions and their triggers (cheap), unindexed foreign keys
--   (scholarship_ai_queue.model_code and others: not on this path), lock waits with public.svc_scholarship_ai_next (no cancellation names it).
-- What:
--   1. Index pipeline.scholarship_ai_extractions (queue_id, id desc), and the v_prev lookup reads the root row and its children by id and root_id
--      (both indexed) instead of joining on an expression. Same rows, same order (measured 2 ms against 2.6 to 3.9 s).
--   2. search.course_refresh_requests: an append-only queue of courses whose search documents need the scoped refresh, filled by
--      search.course_refresh_request_v1(courses, by). No row is ever updated by the caller, so queueing never waits on a lock.
--   3. security.scholarship_sweep_apply_v1 and security.scholarship_admission_withdraw_v1 (md5-guarded edits): when the transaction-local flag
--      cf247.defer_search_refresh is 'on' they queue the courses instead of refreshing them. Every other caller (admin actions, Layer 4 decisions,
--      svc_scholarship_read_record, readmit, admit from provider page) leaves the flag unset and refreshes in the call exactly as before.
--   4. public.svc_scholarship_ai_record (md5-guarded edit): sets the flag for its own transaction while search.defer_ai_record_refresh_on is 1, and
--      uses the indexed v_prev lookup.
--   5. security.search_course_refresh_drain_v1(limit) and job search-course-refresh (every minute, catalogued): takes the writer lock only if it is free
--      (pg_try_advisory_xact_lock, never waits), refreshes up to batch.search_course_refresh queued courses (oldest first) with the same scoped refresh, and
--      stamps the requests it covered. A request queued while it ran stays open for the next run. Search sees a scholarship's course links a minute or
--      two later than before; publication rules and the consumer API are unchanged.
-- Guards: G1 (one new job, catalogued before it is scheduled), G2 (the switch and the batch are settings; the job command has no number; the writer lock
--   name is a technical lock, marked fixed), G3 (no consumer API object read or changed: search.course_documents is written only by the existing scoped
--   refresh), Decision 260 (Replaces/Retires, table purpose, register rows), nothing deleted or dropped.
-- Live definitions this change edits (md5 of pg_get_functiondef, read 14 Nov 2026 17:40 AEDT):
--   public.svc_scholarship_ai_record(...) cbcf286f7d5cdd916aee7bb34ca52bc4, security.scholarship_sweep_apply_v1(uuid) ccd52459abe03f92b18de526ae100d82,
--   security.scholarship_admission_withdraw_v1(uuid,jsonb) b95aa4d6bd52881eecc448a593a28167.
-- Rollback without a migration: set search.defer_ai_record_refresh_on to 0 (the record call refreshes in the call again, as before this change).
-- Rehearsal (rolled back, against live, before apply):
--   1. Guards: the three md5s above match live (step 0 below raises otherwise).
--   2. Run this file inside begin; ... rollback; through the SQL editor or the Supabase MCP (statement_timeout 120 s). Nothing persists.
--   3. Inside the same transaction, before rollback: (a) svc_scholarship_ai_record's v_prev lookup for the largest root chain runs under 500 ms (post-check);
--      (b) set local role service_role and set local statement_timeout = '8s', set_config('cf247.defer_search_refresh','on',true), then
--      security.scholarship_ai_apply_v1(63275) (124 linked courses; 12.6 s before) completes under 8 s and leaves its courses in
--      search.course_refresh_requests; (c) security.search_course_refresh_drain_v1(300) refreshes them and stamps processed_at.
--   4. rollback; then confirm the three md5s are unchanged, no search-course-refresh job exists and search.course_refresh_requests does not exist.
--   After apply: the post-checks below; then for 24 hours the postgres-log count of svc_scholarship_ai_record cancellations (expected: only the residual
--   course-matching ones, about 6 a day), the queue's open courses (expected: drained within a few minutes) and the drain's run times.
-- Replaces: nothing
-- Retires: nothing

-- 0. guards: the live definitions this change edits ------------------------------------------------------------------------------------------------------
do $g$
begin
  if md5(pg_get_functiondef('public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)'::regprocedure)) <> 'cbcf286f7d5cdd916aee7bb34ca52bc4' then
    raise exception 'live public.svc_scholarship_ai_record differs from the definition this change edits';
  end if;
  if md5(pg_get_functiondef('security.scholarship_sweep_apply_v1(uuid)'::regprocedure)) <> 'ccd52459abe03f92b18de526ae100d82' then
    raise exception 'live security.scholarship_sweep_apply_v1 differs from the definition this change edits';
  end if;
  if md5(pg_get_functiondef('security.scholarship_admission_withdraw_v1(uuid,jsonb)'::regprocedure)) <> 'b95aa4d6bd52881eecc448a593a28167' then
    raise exception 'live security.scholarship_admission_withdraw_v1 differs from the definition this change edits';
  end if;
  perform 'search.refresh_course_enrichment_scoped_v1(uuid[],boolean)'::regprocedure;
end $g$;

-- 1. index for the v_prev lookup -------------------------------------------------------------------------------------------------------------------------
create index if not exists scholarship_ai_extractions_queue_idx on pipeline.scholarship_ai_extractions (queue_id, id desc);

-- 2. the course refresh queue ----------------------------------------------------------------------------------------------------------------------------
create table if not exists search.course_refresh_requests (
  id bigserial primary key,
  course_id uuid not null,
  requested_at timestamptz not null default now(),
  requested_by text not null,
  processed_at timestamptz,
  result jsonb
);
comment on table search.course_refresh_requests is 'Courses whose search documents need the scoped enrichment refresh, queued by calls that must stay inside the 8 s statement limit (svc_scholarship_ai_record through scholarship_sweep_apply_v1 and scholarship_admission_withdraw_v1) and refreshed by security.search_course_refresh_drain_v1 (job search-course-refresh). Append-only for callers; the drain stamps processed_at.';
create index if not exists course_refresh_requests_open on search.course_refresh_requests (id) where processed_at is null;
create index if not exists course_refresh_requests_open_course on search.course_refresh_requests (course_id, id) where processed_at is null;
alter table search.course_refresh_requests enable row level security;
revoke all on table search.course_refresh_requests from public, anon, authenticated, service_role;
revoke all on sequence search.course_refresh_requests_id_seq from public, anon, authenticated, service_role;

create or replace function search.course_refresh_request_v1(p_course_ids uuid[], p_requested_by text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
-- R5 (14 Nov 2026): queue courses for the scoped search refresh; an insert only, so the caller never waits on a lock
declare v_n integer;
begin
  if p_course_ids is null or cardinality(p_course_ids) = 0 then return 0; end if;
  insert into search.course_refresh_requests(course_id, requested_by)
  select distinct c.id, coalesce(p_requested_by, 'unknown') from unnest(p_course_ids) c(id) where c.id is not null;
  get diagnostics v_n = row_count;
  return v_n;
end
$function$;
comment on function search.course_refresh_request_v1(uuid[], text) is 'Queues courses for the scoped search refresh (search.course_refresh_requests); refreshed by security.search_course_refresh_drain_v1. Insert only, never waits on a lock.';
revoke all on function search.course_refresh_request_v1(uuid[], text) from public, anon, authenticated;

create or replace function security.search_course_refresh_drain_v1(p_limit integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
-- R5 (14 Nov 2026): refreshes queued courses with the existing scoped refresh, oldest first; never waits for the writer lock
declare v_t0 timestamptz := clock_timestamp(); v_max bigint; v_ids uuid[]; r jsonb; v_rows integer;
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247:search_course_documents_writer')) then  -- fixed: the one writer lock for search.course_documents (W27); never wait for it
    return jsonb_build_object('held', 'another search-document writer is running; the queued courses wait for the next run',
                              'open_courses', (select count(distinct q.course_id) from search.course_refresh_requests q where q.processed_at is null));
  end if;
  select max(q.id) into v_max from search.course_refresh_requests q where q.processed_at is null;
  if v_max is null then return jsonb_build_object('open_courses', 0); end if;
  select array_agg(z.course_id order by z.first_id) into v_ids
    from (select q.course_id, min(q.id) first_id from search.course_refresh_requests q
           where q.processed_at is null and q.id <= v_max group by q.course_id order by min(q.id) limit greatest(coalesce(p_limit, 0), 1)) z;
  r := search.refresh_course_enrichment_scoped_v1(v_ids, true);
  update search.course_refresh_requests q set processed_at = now(), result = jsonb_build_object('rows', r->'rows', 'changed', r->'changed')
   where q.processed_at is null and q.id <= v_max and q.course_id = any(v_ids);
  get diagnostics v_rows = row_count;
  return jsonb_build_object('courses', cardinality(v_ids), 'requests', v_rows, 'changed', r->'changed',
                            'open_courses', (select count(distinct q.course_id) from search.course_refresh_requests q where q.processed_at is null),
                            'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
end
$function$;
comment on function security.search_course_refresh_drain_v1(integer) is 'Job search-course-refresh: refreshes up to p_limit queued courses (search.course_refresh_requests, oldest first) with search.refresh_course_enrichment_scoped_v1 when the search-document writer lock is free, and stamps the requests it covered.';
revoke all on function security.search_course_refresh_drain_v1(integer) from public, anon, authenticated;

-- 3 and 4. md5-guarded edits ------------------------------------------------------------------------------------------------------------------------------
create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('security.scholarship_sweep_apply_v1(uuid)', 'ccd52459abe03f92b18de526ae100d82', array[
  array[$o$    perform search.refresh_course_enrichment_scoped_v1(array(select distinct unnest(v_add||v_del)),true);$o$,
        $n$    -- R5 (14 Nov 2026): inside svc_scholarship_ai_record (flag cf247.defer_search_refresh) the courses are queued, not refreshed in the call
    if coalesce(current_setting('cf247.defer_search_refresh', true), '') = 'on' then
      perform search.course_refresh_request_v1(array(select distinct unnest(v_add||v_del)), 'scholarship_sweep_apply_v1');
    else
      perform search.refresh_course_enrichment_scoped_v1(array(select distinct unnest(v_add||v_del)),true);
    end if;$n$]
], array[1]);

select pg_temp.edit_n('security.scholarship_admission_withdraw_v1(uuid,jsonb)', 'b95aa4d6bd52881eecc448a593a28167', array[
  array[$o$  if cardinality(v_courses)>0 then perform search.refresh_course_enrichment_scoped_v1(v_courses,true); end if;$o$,
        $n$  -- R5 (14 Nov 2026): inside svc_scholarship_ai_record (flag cf247.defer_search_refresh) the courses are queued, not refreshed in the call
  if cardinality(v_courses)>0 then
    if coalesce(current_setting('cf247.defer_search_refresh', true), '') = 'on' then
      perform search.course_refresh_request_v1(v_courses, 'scholarship_admission_withdraw_v1');
    else
      perform search.refresh_course_enrichment_scoped_v1(v_courses,true);
    end if;
  end if;$n$]
], array[1]);

select pg_temp.edit_n('public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)', 'cbcf286f7d5cdd916aee7bb34ca52bc4', array[
  array[$o$  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;$o$,
        $n$  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- R5 (14 Nov 2026): search refreshes this answer causes are queued (search.course_refresh_requests) so the paid answer commits inside the 8 s limit
  if security.pipeline_num_v1('search.defer_ai_record_refresh_on', 1) = 1 then perform set_config('cf247.defer_search_refresh', 'on', true); end if;$n$],
  array[$o$    select e.answer->'value' val, e.model_code into v_prev from pipeline.scholarship_ai_extractions e join pipeline.scholarship_ai_queue x on x.id = e.queue_id
     where coalesce(x.root_id, x.id) = coalesce(q.root_id, q.id) and x.id <> q.id and e.verdict = 'scholarship' and e.error is null
       and coalesce((e.checks->>'value')::boolean, false) order by e.id desc limit 1;$o$,
        $n$    -- R5 (14 Nov 2026): the root row and its children by id and root_id (indexed), the same rows as the join on coalesce(root_id, id)
    select e.answer->'value' val, e.model_code into v_prev from pipeline.scholarship_ai_extractions e
     where e.queue_id in (select x.id from pipeline.scholarship_ai_queue x where x.id = coalesce(q.root_id, q.id) and coalesce(x.root_id, x.id) = coalesce(q.root_id, q.id)
                          union all
                          select x.id from pipeline.scholarship_ai_queue x where x.root_id = coalesce(q.root_id, q.id))
       and e.queue_id <> q.id and e.verdict = 'scholarship' and e.error is null
       and coalesce((e.checks->>'value')::boolean, false) order by e.id desc limit 1;$n$]
], array[1, 1]);

-- 5. settings (G2), job (G1), register -------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'search.defer_ai_record_refresh_on', 'Scholarship AI: queue the search refresh an answer causes',
  '1: when a scholarship AI answer changes a scholarship''s course links or withdraws it, the courses are queued for the search refresh (job search-course-refresh, every minute) so the paid answer is saved inside the 8 s limit. 0: refresh in the answer''s own call, as before 14 Nov 2026 (answers can time out and be paid for again).',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 331, 'Website API', 'public.svc_scholarship_ai_record',
  'R5 (14 Nov 2026): 188 paid answers in 24 hours were cancelled at the 8 s limit, 170 of them in the search refresh'),
 ('pipeline', 'batch.search_course_refresh', 'Queued courses refreshed in search per run',
  'Each minute the search-course-refresh job refreshes at most this many queued courses (about 60 ms a course), when no full search refresh is running.',
  'number', to_jsonb(300), 10, 2000, 'courses', 332, 'Website API', 'security.search_course_refresh_drain_v1 (job search-course-refresh)',
  'R5 (14 Nov 2026)')
on conflict (toolset_key, key) do nothing;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('search-course-refresh', 'Search and API', 11, 'Refresh search for queued courses',
  'Every minute: refreshes up to batch.search_course_refresh courses queued in search.course_refresh_requests (scholarship course links changed or withdrawn by an AI answer) with the scoped search refresh, when no full search refresh is running. No Firecrawl and no AI.',
  5, true, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'search-course-refresh') then
    perform cron.schedule('search-course-refresh', '* * * * *', 'select security.search_course_refresh_drain_v1(security.pipeline_num_v1(''batch.search_course_refresh'', 300)::int)');
  end if;
end $j$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'search-course-refresh', 'Website API', 'Search and API', 'R5: refreshes courses queued by calls that must stay inside the 8 s limit (scholarship AI answers) with the scoped search refresh', 'active', '{}', '20261114181500'),
 ('table', 'search.course_refresh_requests', 'Website API', 'Search and API', 'Courses queued for the scoped search refresh, with who queued them and when the drain covered them', 'active', '{}', '20261114181500')
on conflict do nothing;

-- 6. post-checks ----------------------------------------------------------------------------------------------------------------------------------------
do $c$
declare v_def text; v_root bigint; t0 timestamptz; v_ms int; v_n int;
begin
  v_def := pg_get_functiondef('public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)'::regprocedure);
  if position('cf247.defer_search_refresh' in v_def) = 0 or position('join pipeline.scholarship_ai_queue x on x.id = e.queue_id' in v_def) > 0 then
    raise exception 'post-check: svc_scholarship_ai_record was not edited as intended';
  end if;
  if position('course_refresh_request_v1' in pg_get_functiondef('security.scholarship_sweep_apply_v1(uuid)'::regprocedure)) = 0
     or position('course_refresh_request_v1' in pg_get_functiondef('security.scholarship_admission_withdraw_v1(uuid,jsonb)'::regprocedure)) = 0 then
    raise exception 'post-check: the sweep or withdraw step was not edited as intended';
  end if;
  if to_regclass('pipeline.scholarship_ai_extractions_queue_idx') is null then raise exception 'post-check: index missing'; end if;
  if not exists (select 1 from cron.job where jobname = 'search-course-refresh')
     or not exists (select 1 from pipeline.automation_catalogue where jobname = 'search-course-refresh') then
    raise exception 'post-check: job search-course-refresh is not scheduled and catalogued';
  end if;
  -- the v_prev lookup for the largest root chain stays well inside the limit
  select x.root_id into v_root from pipeline.scholarship_ai_queue x where x.root_id is not null group by x.root_id order by count(*) desc limit 1;
  t0 := clock_timestamp();
  select count(*) into v_n from (
    select e.id from pipeline.scholarship_ai_extractions e
     where e.queue_id in (select x.id from pipeline.scholarship_ai_queue x where x.id = v_root and coalesce(x.root_id, x.id) = v_root
                          union all select x.id from pipeline.scholarship_ai_queue x where x.root_id = v_root)
       and e.verdict = 'scholarship' and e.error is null and coalesce((e.checks->>'value')::boolean, false) order by e.id desc limit 1) z;
  v_ms := (extract(epoch from clock_timestamp() - t0) * 1000)::int;
  if v_ms > 500 then raise exception 'post-check: the v_prev lookup took % ms for root %', v_ms, v_root; end if;
end $c$;
