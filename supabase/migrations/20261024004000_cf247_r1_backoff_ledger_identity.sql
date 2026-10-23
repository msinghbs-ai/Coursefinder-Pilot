-- CF-247 (24 Oct 2026). R1 — the enabler the standing order begins with (Platform Admin 24 Oct 2026 09:55 "R1, for real this time";
-- plan: admin repo docs/platform/nz-enrichment-brief/2026-10-23-platform-throughput-gap-schema.md items 1–3 and the 00:45 extension;
-- record: docs/platform/nz-enrichment-brief/2026-10-24-au-builds-and-enrichment-jobs.md).
-- Q2 EMPTY-TICK BACKOFF WITH EVENT-DRIVEN RESET. The flag unit (v2.15.283, 15 Oct) already pauses a worker lane after
--   flag.empty_calls_to_pause empty calls and tries it again after flag.job_recheck_hours (6 h, rising with every check) or, for three modes
--   only (read, link_search, provider_facts), as soon as work waits. Measured today: coverage-read paused at 09:40 AEDT with pages due and a
--   next trial six hours away; central-find, find-site and the contact-page lane the same. So the backoff exists and its maximum is the
--   defect. This change (a) caps every trial wait at tick.backoff_max_minutes (15, 1–60) and (b) gives every paused-prone lane its own
--   "work is waiting" test, so the 10-minute flag-recheck wakes it as soon as its queue is fed (the event-driven reset). No worker change
--   and no new counter: flag.empty_calls_to_pause stays the "after N empty ticks" setting the plan called tick.backoff_after_empty.
-- Q4 (narrowed by the mandate): the companion-read failure and a "why idle" line. The University of Sydney's course data files
--   (.coredata.json) answer with the course page itself (HTML, 200) and the worker refused the body as not JSON (219 of 583 files failed, 49 of them
--   with every attempt used); worker v0.46.0 reads such an answer as the page, and the 219 get their attempts back here (count-guarded).
--   Every queue on the Work queues screen now carries one plain line saying why it is idle (paused by the idle guard and when it is tried
--   again; nothing waiting and which upstream lane feeds it; waiting with nothing finishing: a gate holds it; failing; nothing left).
-- Q3 DURABLE PER-MODE LEDGER: pipeline.mode_outcome_ledger, one row per worker call, written by the worker through
--   public.svc_worker_report_v1 at the end of every call (items, ok, failed, where the work landed, the call time); 90-day retention by
--   its own catalogued daily job (which also removes old zero-yield snapshots: v2.15.338 named retention-worker as their keeper, but that job never did). Queue wait per lane comes from security.lane_queue_wait_v1 (queue timestamps: queued → finished) until
--   the pickers carry the wait themselves; the health report reads both.
-- APPLY-TIME IDENTITY CHECK: security.coverage_apply_course_v1 (the common fee write) now refuses to admit a fee live when the course's
--   bound page carries a proof the country's tuition policy does not accept: the fee is written unverified with one Layer 4 row
--   (source identity_basis_reverify, the same shape as the 24 Oct 00:35 quarantine) and the result says fee_quarantined_identity.
--   Manual bindings and admin writes are exempt. Every caller is covered, whatever it checked before (the fee reader checks at enqueue only).
-- Replaces: nothing (flag_jobs_v1, worker_mode_waiting_v1, admin_queue_watch and coverage_apply_course_v1 edited in place, md5-guarded)
-- Retires: nothing

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

-- 1 settings -------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'tick.backoff_max_minutes', 'Idle lane: tried again within', 'A worker lane paused by the idle guard (its last runs found nothing to do) is tried again no later than this many minutes after the pause, and sooner the moment work waits for it. Keeps a drained lane from sleeping for hours while its queue fills.', 'number', '15'::jsonb, '1', '60', 'minutes', 770, 'Waste rules', 'security.flag_jobs_v1', 'R1 Q2 (Platform Admin 24 Oct 2026 09:55)'),
 ('pipeline', 'retention.mode_outcome_ledger_days', 'Worker ledger: kept for', 'Rows of the per-call worker ledger older than this are removed by the daily ledger-retention job.', 'number', '90'::jsonb, '30', '365', 'days', 771, 'Platform upkeep', 'job ledger-retention', 'R1 Q3')
on conflict (toolset_key, key) do nothing;

-- 2 Q2: the trial wait is capped; every paused-prone lane says when work waits ----------------------------------------------------------
select pg_temp.edit_n('security.flag_jobs_v1()', '48031e060996ce062287c52b433e8f0d', array[
  array[$o$null, now() + make_interval(hours => coalesce(security.flag_list_num_v1('flag.job_recheck_hours', coalesce(f.checks, 0)), 6)));$o$,
        $n$null, now() + least(make_interval(hours => coalesce(security.flag_list_num_v1('flag.job_recheck_hours', coalesce(f.checks, 0)), 6)),
                                 make_interval(mins => security.pipeline_num_v1('tick.backoff_max_minutes', 15)::int)));  /* R1 Q2 (24 Oct 2026): never longer than the backoff cap */$n$]], array[1]);

do $g$ begin
  if md5(pg_get_functiondef('security.worker_mode_waiting_v1(text)'::regprocedure)) <> '92da330ef4d63c0127a4cba236caba6f' then
    raise exception 'live security.worker_mode_waiting_v1 differs from the definition this change replaces';
  end if;
end $g$;
create or replace function security.worker_mode_waiting_v1(p_mode text) returns boolean
language sql stable security definer set search_path = '' as $$
  -- R1 Q2 (24 Oct 2026): one "work is waiting" test per lane the idle guard pauses; each mirrors its picker's eligibility (hidden
  -- providers left out) without leasing anything. A lane not listed answers false and waits for its capped trial.
  select case p_mode
    when 'read' then exists (select 1 from pipeline.coverage_course_pages p
                              where p.status in ('bound', 'ambiguous') and coalesce(p.next_read_at, now()) <= now() and coalesce(p.leased_until, '-infinity') < now() and p.read_attempts < 3
                                and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id))
    when 'link_search' then exists (select 1 from pipeline.course_link_search s
                              where s.state = 'queued' and s.requested_at is not null
                                and (not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true)
                                     or exists (select 1 from pipeline.firecrawl_target_cache tc where tc.provider_id = s.provider_id and tc.included))
                                and s.provider_id <> all (array(select x.provider_id from security.fc_search_stopped_v1() x)))
    when 'provider_facts' then exists (select 1 from pipeline.provider_fact_sources f where f.status = 'found' and coalesce(f.attempts, 0) < 3)
    when 'ai_match' then exists (select 1 from pipeline.coverage_ai_match q
                              where (q.state = 'ready' or (q.state = 'leased' and q.leased_until < now()))
                                and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id))
    when 'reidentify' then exists (select 1 from pipeline.coverage_course_pages p join pipeline.evidence_artifacts e on e.id = p.evidence_id
                              where p.status = 'mismatch' and p.read_status = 'identity_mismatch' and coalesce(p.basis, '') <> 'manual' and e.storage_path is not null
                                and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)
                                and not exists (select 1 from pipeline.page_rejections x where x.course_id = p.course_id and x.url = p.url))
    when 'discover' then exists (select 1 from pipeline.coverage_provider_discovery d
                              where (d.status = 'pending' or (d.status in ('mapped', 'failed') and d.next_due_at <= now())) and coalesce(d.leased_until, '-infinity') < now()
                                and d.attempts < 3 and security.enrich_focus_v1(d.provider_id)
                                and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id))
    when 'find_site' then exists (select 1 from pipeline.coverage_provider_discovery d
                              where d.status = 'no_website' and coalesce(d.site_searched_at, '-infinity') < now() - make_interval(days => security.pipeline_num_v1('retry.no_website_days', 30)::int)
                                and coalesce(d.leased_until, '-infinity') < now()
                                and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id))
    when 'central_find' then exists (select 1 from pipeline.provider_central_search s join catalogue.providers p on p.id = s.provider_id
                              where (s.state = 'queued' or (s.state = 'leased' and s.leased_until < now())) and s.attempts < 3 and p.lifecycle_status = 'active'
                                and p.website ~* '^https?://' and not security.third_party_host_v1(p.website)
                                and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)
                                and (s.requested_at is not null or not security.flag_provider_held_v1(s.provider_id, array['central_not_due', 'central_budget', 'site_unreachable'])))
    when 'contact_page' then exists (select 1 from catalogue.providers p
                              where p.lifecycle_status = 'active' and p.website ~* '^https?://' and (p.phone is null or p.email is null) and not security.third_party_host_v1(p.website)
                                and not exists (select 1 from pipeline.provider_contact_checks k where k.provider_id = p.id and k.kind = 'public_general'
                                                 and k.checked_at > now() - make_interval(days => security.pipeline_num_v1('contact.recheck_days', 90)::int))
                                and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
                                and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active'))
    when 'logo_find' then exists (select 1 from catalogue.providers p left join pipeline.provider_logo_finds f on f.provider_id = p.id
                              where p.lifecycle_status = 'active' and nullif(btrim(p.website), '') is not null and (f.requested_at is not null or p.publication_status = 'published')
                                and not exists (select 1 from catalogue.provider_assets a where a.provider_id = p.id and a.is_primary and a.status = 'approved' and a.asset_type in ('logo', 'logo_dark', 'logo_light'))
                                and (f.provider_id is null or f.requested_at is not null or f.status = 'queued')
                                and (f.requested_at is not null or not security.flag_provider_held_v1(p.id, array['site_unreachable', 'logo_not_found'])))
    when 'companion_read' then exists (select 1 from pipeline.course_companion_pages p
                              where p.next_read_at <= now() and (p.leased_until is null or p.leased_until < now())
                                and p.read_attempts < security.pipeline_num_v1('companion.max_attempts', 4) and p.status <> 'gone'
                                and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id))
    when 'source_find' then exists (select 1 from pipeline.source_find_runs r
                              where (r.step is not null or (r.work->>'again' = 'true' and coalesce(r.next_try_at, now()) <= now()))
                                and coalesce(r.leased_until, '-infinity') < now() and coalesce(r.work->>'test', 'false') <> 'true')
    when 'programme_read' then exists (select 1 from pipeline.programme_candidates c
                              where c.state in ('found', 'failed') and c.read_attempts < security.pipeline_num_v1('programme.read_attempts', 3)::int
                                and c.next_read_at <= now() and coalesce(c.leased_until, '-infinity') < now())
    else false end
$$;
comment on function security.worker_mode_waiting_v1(text) is 'R1 Q2: true when the lane''s own queue holds eligible work; the flag recheck (every 10 minutes) switches a paused lane on again the moment this is true';

-- 3 Q3: the per-mode ledger -------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.mode_outcome_ledger (
  id bigint generated always as identity primary key,
  run_at timestamptz not null default now(),
  mode text not null,
  status int not null default 200,
  ms int,
  items int not null default 0,
  ok int not null default 0,
  failed int not null default 0,
  wait_ms int,
  landed jsonb not null default '{}'::jsonb,
  worker text,
  detail jsonb
);
comment on table pipeline.mode_outcome_ledger is 'R1 Q3 (24 Oct 2026): one row per worker call — the mode, what it processed (items), how much succeeded and failed, where the work landed (the call''s tally), the call time and the worker version; written by public.svc_worker_report_v1 at the end of every call; 90-day retention (ledger-retention)';
create index if not exists mode_outcome_ledger_run_at_idx on pipeline.mode_outcome_ledger (run_at desc);
create index if not exists mode_outcome_ledger_mode_run_at_idx on pipeline.mode_outcome_ledger (mode, run_at desc);
alter table pipeline.mode_outcome_ledger enable row level security;

create or replace function public.svc_worker_report_v1(p_mode text, p_status int, p_ms int, p_body jsonb, p_worker text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_items int; v_failed int; v_ok int; v_landed jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  v_items := coalesce(security.worker_call_work_v1(p_body::text), 0)::int;
  v_failed := coalesce(nullif(p_body->>'failed', '')::int, nullif(p_body->'tally'->>'failed', '')::int, 0)
            + coalesce(nullif(p_body->'tally'->>'fetch_failed', '')::int, 0) + coalesce(nullif(p_body->'tally'->>'scrape_failed', '')::int, 0)
            + case when p_status >= 400 or coalesce(p_body->>'ok', 'true') = 'false' then 1 else 0 end;
  v_ok := greatest(0, coalesce(nullif(p_body->>'done', '')::int, nullif(p_body->>'applied', '')::int, v_items - v_failed));
  v_landed := coalesce(p_body->'landed', p_body->'tally', '{}'::jsonb);
  insert into pipeline.mode_outcome_ledger(mode, status, ms, items, ok, failed, landed, worker, detail)
  values (left(coalesce(p_mode, ''), 60), coalesce(p_status, 200), p_ms, v_items, v_ok, v_failed, v_landed, left(p_worker, 80),
          case when length((p_body - 'ok' - 'mode' - 'workerVersion' - 'tally' - 'landed')::text) <= 4000 then p_body - 'ok' - 'mode' - 'workerVersion' - 'tally' - 'landed'
               else jsonb_build_object('truncated', true, 'keys', (select jsonb_agg(k) from jsonb_object_keys(p_body) k)) end)  -- fixed: a row keeps at most 4 KB of detail
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.svc_worker_report_v1(text, int, int, jsonb, text) from public, anon, authenticated;
grant execute on function public.svc_worker_report_v1(text, int, int, jsonb, text) to service_role;
comment on function public.svc_worker_report_v1(text, int, int, jsonb, text) is 'R1 Q3: the worker reports every call''s outcome to pipeline.mode_outcome_ledger (service role only)';

-- queue wait per lane from the queues'' own timestamps (queued → finished), until the pickers carry the wait themselves
create or replace function security.lane_queue_wait_v1(p_hours int default 24)
returns table (lane text, finished bigint, p50_min numeric, p90_min numeric, max_min numeric, waiting bigint)
language sql stable security definer set search_path = '' as $$
  with w as (
    select 'fee_reader' lane, extract(epoch from (q.finished_at - q.created_at)) / 60 m from pipeline.fee_reader_queue q where q.finished_at > now() - make_interval(hours => p_hours)
    union all
    select 'enrich_fields', extract(epoch from (i.updated_at - i.created_at)) / 60 from pipeline.field_enrich_items i where i.updated_at > now() - make_interval(hours => p_hours) and i.state in ('filled', 'skipped', 'review', 'applied')
    union all
    select 'course_page_read', extract(epoch from (p.read_at - p.next_read_at)) / 60 from pipeline.coverage_course_pages p where p.read_at > now() - make_interval(hours => p_hours) and p.next_read_at is not null and p.read_at >= p.next_read_at
    union all
    select 'ai_page_match', extract(epoch from (q.decided_at - q.created_at)) / 60 from pipeline.coverage_ai_match q where q.decided_at > now() - make_interval(hours => p_hours)
    union all
    select 'course_page_search', extract(epoch from (s.done_at - coalesce(s.requested_at, s.queued_at))) / 60 from pipeline.course_link_search s where s.done_at > now() - make_interval(hours => p_hours)
    union all
    select 'central_ai', extract(epoch from (q.done_at - q.created_at)) / 60 from pipeline.central_ai_queue q where q.done_at > now() - make_interval(hours => p_hours)),
  q as (
    select 'fee_reader' lane, count(*) n from pipeline.fee_reader_queue where state = 'queued'
    union all select 'enrich_fields', count(*) from pipeline.field_enrich_items where state = 'queued'
    union all select 'course_page_read', count(*) from pipeline.coverage_course_pages p where p.status in ('bound', 'ambiguous') and coalesce(p.next_read_at, now()) <= now() and p.read_attempts < 3
    union all select 'ai_page_match', count(*) from pipeline.coverage_ai_match where state = 'ready'
    union all select 'course_page_search', count(*) from pipeline.course_link_search where state = 'queued'
    union all select 'central_ai', count(*) from pipeline.central_ai_queue where state = 'queued')
  select q.lane, count(w.m) finished, round(percentile_cont(0.5) within group (order by w.m)::numeric, 1), round(percentile_cont(0.9) within group (order by w.m)::numeric, 1), round(max(w.m)::numeric, 1), max(q.n)
    from q left join w on w.lane = q.lane group by q.lane order by q.lane
$$;
comment on function security.lane_queue_wait_v1(int) is 'R1 Q3: queue wait (minutes, p50/p90/max) and rows waiting per reader lane over the last p_hours, from the queues'' timestamps';

create or replace function security.ledger_retention_v1() returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare n_ledger int; n_zy int;
begin
  delete from pipeline.mode_outcome_ledger where run_at < now() - make_interval(days => security.pipeline_num_v1('retention.mode_outcome_ledger_days', 90)::int);
  get diagnostics n_ledger = row_count;
  -- the zero-yield snapshots (v2.15.338) named retention-worker as their keeper but nothing removed them: this job does, by their own setting
  delete from pipeline.zero_yield_snapshots where at < now() - make_interval(days => security.pipeline_num_v1('retention.zero_yield_snapshots_days', 90)::int);
  get diagnostics n_zy = row_count;
  return jsonb_build_object('mode_outcome_ledger', n_ledger, 'zero_yield_snapshots', n_zy);
end $function$;
comment on function security.ledger_retention_v1() is 'daily: removes worker-ledger rows and zero-yield snapshots older than their retention settings';
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('ledger-retention', 'Platform upkeep', 95, 'Ledgers: retention', 'Daily at 03:37 UTC: removes rows of the per-call worker ledger older than Worker ledger: kept for, and zero-yield snapshots older than Zero-yield snapshots kept.', 6, false, null)
on conflict (jobname) do nothing;
select cron.schedule('ledger-retention', '37 3 * * *', $$select security.ledger_retention_v1()$$);

-- 4 Q4: why idle -------------------------------------------------------------------------------------------------------------------------
alter table pipeline.queue_watch add column if not exists upstream_key text references pipeline.queue_watch(key);
comment on column pipeline.queue_watch.upstream_key is 'R1 Q4: the queue that feeds this one; named in the "why idle" line when nothing is waiting';
update pipeline.queue_watch set upstream_key = v.up from (values
  ('course_page_read', 'course_page_search'), ('fee_reader', 'course_page_read'), ('ai_page_match', 'course_page_discover'),
  ('credential_read', 'course_page_read'), ('companion_read', 'course_page_read'), ('central_ai', 'central_find'), ('programme_read', 'source_find')) v(k, up)
 where queue_watch.key = v.k and exists (select 1 from pipeline.queue_watch u where u.key = v.up);

create or replace function security.lane_why_idle_v1(p_key text) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when s.key is null then null
    when coalesce(array_length(s.jobs_paused, 1), 0) > 0 then
      'Paused by the idle guard (' || array_to_string(s.jobs_paused, ', ') || ')'
      || coalesce(' since ' || to_char(f.flagged_at at time zone 'Australia/Melbourne', 'DD Mon HH24:MI'), '')
      || coalesce('; tried again by ' || to_char(f.next_check_at at time zone 'Australia/Melbourne', 'DD Mon HH24:MI'), '') || ', or as soon as work waits'
    when s.state = 'failing' then 'Failing: ' || coalesce(s.reason, 'most tries in the last hour failed')
    when s.state = 'stuck' then 'Stuck: ' || coalesce(s.reason, 'work waiting and nothing finishing')
    when s.state = 'out_of_toolset' then 'A tool is out: ' || array_to_string(s.tools_out, ', ')
    when s.state = 'waiting' then 'Waiting for today''s budget: ' || array_to_string(s.tools_waiting, ', ')
    when s.state = 'nothing_left' then 'Nothing left to try: ' || coalesce(s.reason, '')
    when coalesce(s.pending, 0) > 0 and coalesce(s.done_window, 0) = 0 then
      s.pending || ' waiting and nothing finished in the last window: a gate is holding the lane' || coalesce(' (' || w.retry_label || ')', '')
    when coalesce(s.pending, 0) = 0 and w.upstream_key is not null then
      'Nothing waiting; fed by ' || u.label || ' (' || coalesce(us.pending, 0) || ' waiting there, ' || coalesce(us.state, 'not checked') || ')'
    when coalesce(s.pending, 0) = 0 then 'Nothing waiting'
    else null end
  from pipeline.queue_watch w
  left join pipeline.queue_watch_state s on s.key = w.key
  left join pipeline.queue_watch u on u.key = w.upstream_key
  left join pipeline.queue_watch_state us on us.key = w.upstream_key
  left join lateral (select x.flagged_at, x.next_check_at from pipeline.enrichment_flags x
                      where x.entity = 'job' and x.reason_code = 'idle_paused' and x.state = 'raised' and x.entity_key = any (s.jobs_paused)
                      order by x.flagged_at desc limit 1) f on true
  where w.key = p_key
$$;
comment on function security.lane_why_idle_v1(text) is 'R1 Q4: one plain line per queue saying why it is idle (paused and when tried again, nothing waiting and who feeds it, gated, failing, nothing left)';

select pg_temp.edit_n('public.admin_queue_watch(text,jsonb)', 'e2e9b8c9186590363acee4248973bd91', array[
  array[$o$'nothing_left_is', w.exhausted_label, 'fix', w.retry_label, 'fix_at', w.fix_at) order by w.sort)$o$,
        $n$'nothing_left_is', w.exhausted_label, 'fix', w.retry_label, 'fix_at', w.fix_at, 'why_idle', security.lane_why_idle_v1(w.key)) order by w.sort)$n$]], array[1]);

-- the companion data files that answered with the course page: attempts back (count-guarded), re-read by worker v0.46.0
do $g$ declare n int; begin
  select count(*) into n from pipeline.course_companion_pages p
   where p.provider_id = '68022bdf-43e8-44b3-ac14-e9eed9f71e83' and p.status = 'failed' and p.http_status = 200 and p.fetched_via = 'direct' and p.url ~* '\.json$' and p.read_attempts >= 3;
  if n <> 219 then raise exception 'expected 219 failed Sydney companion data files (170 at 3 attempts, 49 at 4), found %', n; end if;
  update pipeline.course_companion_pages p set read_attempts = 0, next_read_at = now(), updated_at = now()
   where p.provider_id = '68022bdf-43e8-44b3-ac14-e9eed9f71e83' and p.status = 'failed' and p.http_status = 200 and p.fetched_via = 'direct' and p.url ~* '\.json$' and p.read_attempts >= 3;
end $g$;

-- 5 apply-time identity check ----------------------------------------------------------------------------------------------------------
select pg_temp.edit_n('security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)', 'd6287accb0ee955048978427b59c1ca2', array[
  array[$o$declare c record; r jsonb; v_test uuid; v_key text; v_links int := 0; v_intakes int := 0; v_english int := 0; v_fees int := 0; v_cur text; v_floor numeric;$o$,
        $n$declare c record; r jsonb; v_test uuid; v_key text; v_links int := 0; v_intakes int := 0; v_english int := 0; v_fees int := 0; v_cur text; v_floor numeric; v_ident text; v_ident_url text; v_cc text;$n$],
  array[$o$    v_floor := security.fee_below_floor_v1(p_course_id, (p_payload->>'fee_amount')::numeric, nullif(btrim(p_payload->>'fee_basis'), ''));$o$,
        $n$    v_floor := security.fee_below_floor_v1(p_course_id, (p_payload->>'fee_amount')::numeric, nullif(btrim(p_payload->>'fee_basis'), ''));
    -- 24 Oct 2026 (R1, apply-time identity check): a fee for a course whose bound page carries a proof the country's tuition policy does not
    -- accept is never admitted live, whatever the caller checked: written unverified with one Layer 4 row (source identity_basis_reverify).
    -- Manual bindings are exempt. A page re-bound under the country's rule re-admits the fee through this same path.
    select p.identity_basis, p.url, k.iso_alpha2 into v_ident, v_ident_url, v_cc
      from pipeline.coverage_course_pages p join catalogue.providers pr on pr.id = p.provider_id join ref.countries k on k.id = pr.country_id
     where p.course_id = p_course_id and p.status = 'bound' and coalesce(p.basis, '') <> 'manual' and p.identity_basis is not null
       and p.identity_basis <> 'manual' and not security.coverage_identity_allowed(c.provider_id, p.identity_basis, 'tuition') limit 1;
    if v_ident is not null then
      if not exists (select 1 from pipeline.layer4_review_items l where l.entity_type = 'course' and l.entity_id = p_course_id and l.field_code = 'provider_current_tuition' and l.status = 'pending') then
        insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
        values ('course', p_course_id, 'provider_current_tuition', p_evidence_id, null,
                jsonb_build_object('amount', (p_payload->>'fee_amount')::numeric, 'currency', v_cur, 'basis', nullif(btrim(p_payload->>'fee_basis'), ''), 'page', p_url),
                jsonb_build_object('source', 'identity_basis_reverify', 'state', 'quarantined', 'country', v_cc, 'identity_basis', v_ident, 'page', v_ident_url), '{}'::jsonb, 'pending',
                'quarantined at the write: the course page was bound with a ' || v_ident || ' proof, which the ' || v_cc || ' tuition policy does not accept; re-binding the page under the country''s rule re-admits the fee',
                'CF-CHG-20260915-247 R1 apply-time identity check');
      end if;
      v_floor := coalesce(v_floor, -1);  /* fixed: a sentinel that keeps the fee unverified through the same write below; never shown */
    end if;$n$],
  array[$o$'fees_applied', v_fees, 'fee_quarantined', v_floor is not null);$o$,
        $n$'fees_applied', v_fees, 'fee_quarantined', v_floor is not null and v_floor <> -1, 'fee_quarantined_identity', v_ident is not null);$n$],
  -- the floor-quarantine Layer 4 row is not written for an identity quarantine (the sentinel): the floor branch runs only for a real floor
  array[$o$    if v_floor is not null then
      if not exists (select 1 from pipeline.layer4_review_items l where l.entity_type = 'course' and l.entity_id = p_course_id and l.field_code = 'provider_current_tuition' and l.status = 'pending') then
        insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
        values ('course', p_course_id, 'provider_current_tuition', p_evidence_id, null,
                jsonb_build_object('amount', (p_payload->>'fee_amount')::numeric, 'currency', v_cur, 'basis', nullif(btrim(p_payload->>'fee_basis'), ''), 'page', p_url),
                jsonb_build_object('page', p_url, 'source', 'fee floor', 'state', 'quarantined'), '{}'::jsonb, 'pending',$o$,
        $n$    if v_floor is not null then
      if v_floor <> -1 and not exists (select 1 from pipeline.layer4_review_items l where l.entity_type = 'course' and l.entity_id = p_course_id and l.field_code = 'provider_current_tuition' and l.status = 'pending') then
        insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
        values ('course', p_course_id, 'provider_current_tuition', p_evidence_id, null,
                jsonb_build_object('amount', (p_payload->>'fee_amount')::numeric, 'currency', v_cur, 'basis', nullif(btrim(p_payload->>'fee_basis'), ''), 'page', p_url),
                jsonb_build_object('page', p_url, 'source', 'fee floor', 'state', 'quarantined'), '{}'::jsonb, 'pending',$n$]], array[1, 1, 1, 1]);

-- 6 register ------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.mode_outcome_ledger', 'Layer 2', 'R1 Q3 per-call worker ledger (items, ok, failed, landed)', 'active', '{}', '20261024004000'),
 ('function', 'public.svc_worker_report_v1', 'Layer 2', 'worker call report into the ledger (service role)', 'active', '{}', '20261024004000'),
 ('function', 'security.lane_queue_wait_v1', 'Layer 2', 'queue wait percentiles per reader lane from queue timestamps', 'active', '{}', '20261024004000'),
 ('function', 'security.ledger_retention_v1', 'Layer 2', 'ledger and snapshot retention', 'active', '{}', '20261024004000'),
 ('function', 'security.lane_why_idle_v1', 'Layer 2', 'R1 Q4 why-idle line per work queue', 'active', '{}', '20261024004000'),
 ('job', 'ledger-retention', 'Layer 2', 'daily ledger and snapshot retention', 'active', '{}', '20261024004000')
on conflict (kind, name) do nothing;

select 'R1: backoff cap and per-lane waiting tests, per-mode ledger, why-idle line, companion data files re-read, apply-time identity check' ok;
