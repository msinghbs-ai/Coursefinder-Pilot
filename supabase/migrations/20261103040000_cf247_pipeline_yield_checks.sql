-- CF-247 pipeline yield checks: "job invocation succeeded" is not "work done" (Platform Admin direction 2 Nov 2026 23:24, admin
-- docs/platform/nz-enrichment-brief/2026-11-02-overnight-continuous-delivery-direction-2324.md §3; continuous validation mandate 16:58 §4 V4).
-- Why (read-only, production, 2 Nov 2026 23:36-23:57 AEDT, :x6-:x8 windows):
--   * coverage-sweep mode scholarship_discover answered HTTP 500 to 22 of its 36 calls in 6 hours while job scholarship-discover recorded 36
--     succeeded runs: pg_cron only sees the call being sent. link_search answered 500 to 116 of 360 calls. Platform health's edge check groups
--     by function (coverage-sweep is one function with 30 modes), so one failing mode inside a busy function stays below its threshold, and a
--     worker that answers 200 with "ok": false is not counted at all.
--   * pipeline.mode_outcome_ledger (one row per worker call: items, ok, failed) has the yield of every call; nothing reads it for
--     persistent zero yield while work waits.
--   * pipeline.provider_course_lists records the course addresses the source finder saw and the links read: 25 lists read fewer links than
--     they list (one 3,000 of 3,313). Entry-matrix runs record held_incomplete reads.
--   * Repeated failed attempts per provider: 20 providers each have 10 or more course pages that failed (fetch_failed or blocked) after
--     3 or more attempts (up to 153 for one provider).
-- What (reuses the integration queue of 20261102120000, its upsert by fingerprint and its P0 alert path; nothing is edited):
--   1. pipeline.integration_yield_buckets: hourly tallies per worker mode, filled incrementally from the newest edge responses
--      (net._http_response joined to pipeline.edge_request_log by its ring slot) and the newest ledger rows, past a watermark in
--      pipeline.integration_validate_state. The checks read the buckets, never the logs again.
--   2. security.integration_yield_checks_v1: hidden worker errors (HTTP 4xx/5xx, time-outs, transport errors or "ok": false under a call
--      the scheduler counts as sent), persistent zero yield (calls, no item done, while items failed or work waits: security.worker_mode_waiting_v1),
--      incomplete pagination (course lists) and incomplete whole reads (entry-matrix held_incomplete / held_partial), repeated failed
--      attempts per provider (course pages, scholarship discovery, provider flags). One fingerprint each; an unchanged problem is not
--      duplicated; a check that ran and no longer sees it marks the issue cleared.
--   3. Job integration-validate runs it after security.integration_validate_v1 (command changed, no number; the job keeps its state,
--      inactive until the integrator switches it on).
--   4. security.pipeline_yield_v1 and public.admin_pipeline_yield (PIM Admin and above): per-stage yield for the scholarship, course page,
--      academic entry (AER) and description lanes (invoked, source accessed, pages discovered, read completely, extracted, accepted or held,
--      published, consumer read-back), from existing tables only. Shown on Platform health › Integration queue.
-- Replaces: nothing (security.integration_validate_v1 is not edited; the job integration-validate calls one more function)
-- Retires: nothing
-- Nothing is dropped, deleted or switched on. No existing function is edited. Consumer API untouched (G3): search.course_documents,
-- catalogue and scholarship tables are only read.

-- 1. settings (G2) -------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'integration.hidden_error_window_minutes', 'Integration checks: hidden errors looked at over',
  'Worker calls answered with an error (HTTP 4xx or 5xx, a time-out, a transport error, or "ok": false) are counted per worker mode over this window.',
  'number', to_jsonb(120), 30, 1440, 'minutes', 997, 'Integration queue', 'security.integration_yield_checks_v1 (hidden worker errors)', 'Platform Admin direction 2 Nov 2026 23:24 §3: hidden errors'),
 ('pipeline', 'integration.hidden_error_min_failures', 'Integration checks: hidden errors before an issue',
  'A worker mode needs at least this many failed answers in the window to open an issue.',
  'number', to_jsonb(3), 1, 100, 'calls', 998, 'Integration queue', 'security.integration_yield_checks_v1 (hidden worker errors)', 'Platform Admin direction 2 Nov 2026 23:24 §3'),
 ('pipeline', 'integration.hidden_error_min_share', 'Integration checks: share of failed answers',
  'And at least this share of its answers in the window failed.',
  'number', to_jsonb(25), 1, 100, '%', 999, 'Integration queue', 'security.integration_yield_checks_v1 (hidden worker errors)', 'Platform Admin direction 2 Nov 2026 23:24 §3'),
 ('pipeline', 'integration.zero_yield_hours', 'Integration checks: zero yield looked at over',
  'A worker mode called at least the minimum number of times in this many hours with no item done, while items failed or work is waiting, opens a zero-yield issue.',
  'number', to_jsonb(6), 1, 72, 'hours', 1000, 'Integration queue', 'security.integration_yield_checks_v1 (persistent zero yield)', 'Platform Admin direction 2 Nov 2026 23:24 §3: persistent zero-yield runs'),
 ('pipeline', 'integration.zero_yield_min_calls', 'Integration checks: calls before zero yield counts',
  'The fewest calls in the window for zero yield to count (a lane called once or twice is not judged).',
  'number', to_jsonb(6), 1, 1000, 'calls', 1001, 'Integration queue', 'security.integration_yield_checks_v1 (persistent zero yield)', 'Platform Admin direction 2 Nov 2026 23:24 §3'),
 ('pipeline', 'integration.provider_failed_attempts_min', 'Integration checks: failed attempts per item',
  'An item (course page, discovery, provider flag) counts as repeatedly failing after this many attempts.',
  'number', to_jsonb(3), 1, 20, 'attempts', 1002, 'Integration queue', 'security.integration_yield_checks_v1 (repeated failed attempts per provider)', 'Platform Admin direction 2 Nov 2026 23:24 §3'),
 ('pipeline', 'integration.provider_failed_pages_min', 'Integration checks: failing course pages per provider',
  'A provider with at least this many course pages failing after the attempts above is listed in the repeated-failures issue.',
  'number', to_jsonb(10), 1, 1000, 'pages', 1003, 'Integration queue', 'security.integration_yield_checks_v1 (repeated failed attempts per provider)', 'Platform Admin direction 2 Nov 2026 23:24 §3'),
 ('pipeline', 'integration.bucket_keep_hours', 'Integration checks: hourly tallies kept for',
  'Hourly tallies of worker answers and yield older than this are removed by the check itself.',
  'number', to_jsonb(72), 6, 720, 'hours', 1004, 'Integration queue', 'security.integration_yield_checks_v1', 'Platform Admin direction 2 Nov 2026 23:24 §3'),
 ('pipeline', 'integration.yield_window_hours', 'Pipeline yield: window shown',
  'Platform health › Integration queue › Pipeline yield counts each stage over this many hours.',
  'number', to_jsonb(24), 1, 168, 'hours', 1005, 'Integration queue', 'security.pipeline_yield_v1 (screen)', 'Platform Admin direction 2 Nov 2026 23:24 §3: every stage distinguished')
on conflict do nothing;

-- 2. hourly tallies ---------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.integration_yield_buckets (
  kind text not null check (kind in ('edge', 'ledger')),
  key text not null,
  bucket timestamptz not null,
  calls int not null default 0,
  failures int not null default 0,
  items int not null default 0,
  ok int not null default 0,
  sample text,
  primary key (kind, key, bucket)
);
comment on table pipeline.integration_yield_buckets is 'CF-247 pipeline yield checks (Platform Admin direction 2 Nov 2026 23:24 §3): hourly tallies per worker mode, filled incrementally by security.integration_yield_checks_v1 (job integration-validate) from the newest edge responses (kind edge: calls and failed answers, with a sample) and the newest worker ledger rows (kind ledger: calls, items, ok, failed), past the watermarks in pipeline.integration_validate_state. Kept for integration.bucket_keep_hours. Never read by the consumer API.';
alter table pipeline.integration_yield_buckets enable row level security;
revoke all on pipeline.integration_yield_buckets from public, anon, authenticated;

-- 3. the checks -------------------------------------------------------------------------------------------------------------------------------
create or replace function security.integration_yield_checks_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Platform Admin direction 2 Nov 2026 23:24 §3: a successful scheduler invocation with zero successful work and an underlying error is not a
-- successful pipeline outcome. Each finding opens or updates one integration issue by fingerprint (security.integration_issue_upsert_v1).
declare v_win interval := make_interval(mins => security.pipeline_num_v1('integration.hidden_error_window_minutes', 120)::int);
        v_minf int := security.pipeline_num_v1('integration.hidden_error_min_failures', 3)::int;
        v_share numeric := security.pipeline_num_v1('integration.hidden_error_min_share', 25);
        v_zy interval := make_interval(hours => security.pipeline_num_v1('integration.zero_yield_hours', 6)::int);
        v_zmin int := security.pipeline_num_v1('integration.zero_yield_min_calls', 6)::int;
        v_att int := security.pipeline_num_v1('integration.provider_failed_attempts_min', 3)::int;
        v_pmin int := security.pipeline_num_v1('integration.provider_failed_pages_min', 10)::int;
        v_keep interval := make_interval(hours => security.pipeline_num_v1('integration.bucket_keep_hours', 72)::int);
        v_back interval := make_interval(hours => security.pipeline_num_v1('integration.first_run_lookback_hours', 24)::int);
        s pipeline.integration_validate_state; r record; v_ok text[] := '{}'; v_seen text[] := '{}'; v_err jsonb := '{}'::jsonb; v_out jsonb := '{}'::jsonb;
        v_id bigint; v_n int; v_m int; v_wait boolean; v_res jsonb; v_fp text;
begin
  -- 1. edge responses past the watermark -> hourly tallies per function and mode
  begin
    select * into s from pipeline.integration_validate_state where check_key = 'yield_edge';
    with h as (select x.id, x.created, x.status_code, x.timed_out, x.error_msg, left(x.content, 2000) content  -- fixed: only the head of an answer is read
                 from net._http_response x
                where x.created >= coalesce(s.watermark_at - interval '10 minutes', now() - v_win) and x.id > coalesce(s.watermark_id, 0)),  -- fixed: slack for rows written by longer transactions
         e as (select h.id, coalesce(l.function_name, 'unattributed') || ':' || coalesce(l.mode, '') k, date_trunc('hour', h.created) b,
                      (coalesce(h.status_code, 0) >= 400 or h.timed_out is true or h.error_msg is not null
                       or (coalesce(h.status_code, 0) < 300 and h.content ~ '"ok"\s*:\s*false')) failed,
                      left(coalesce(h.error_msg, coalesce(h.status_code::text, 'no status') || ' ' || coalesce(h.content, '')), 200) sample
                 from h left join pipeline.edge_request_log l on l.slot = (h.id % 50000)::int and l.request_id = h.id)  -- fixed: the request log is a ring of 50,000 slots
    insert into pipeline.integration_yield_buckets as t(kind, key, bucket, calls, failures, sample)
    select 'edge', e.k, e.b, count(*), count(*) filter (where e.failed), (array_agg(e.sample order by e.id desc) filter (where e.failed))[1]
      from e group by e.k, e.b
    on conflict (kind, key, bucket) do update set calls = t.calls + excluded.calls, failures = t.failures + excluded.failures, sample = coalesce(excluded.sample, t.sample);
    select max(x.id) into v_id from net._http_response x where x.created >= coalesce(s.watermark_at - interval '10 minutes', now() - v_win) and x.id > coalesce(s.watermark_id, 0);  -- fixed: same slack
    insert into pipeline.integration_validate_state as t(check_key, last_run_at, watermark_id, watermark_at) values ('yield_edge', now(), v_id, now())
    on conflict (check_key) do update set last_run_at = now(), watermark_id = coalesce(excluded.watermark_id, t.watermark_id),
      watermark_at = case when excluded.watermark_id is null then t.watermark_at else now() end, last_error = null;
    -- hidden worker errors over the window
    v_n := 0;
    for r in select b.key, sum(b.calls) calls, sum(b.failures) failures, (array_agg(b.sample order by b.bucket desc) filter (where b.sample is not null))[1] sample
               from pipeline.integration_yield_buckets b where b.kind = 'edge' and b.bucket >= date_trunc('hour', now() - v_win) group by b.key loop
      if r.failures >= v_minf and r.failures * 100 >= v_share * r.calls then
        v_fp := 'hidden_worker_error:' || r.key;
        perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', v_fp,
          'title', 'Worker ' || r.key || ' answers with errors while its job counts as succeeded', 'layer', 'Scheduling', 'subsystem', r.key,
          'failure', r.failures || ' of ' || r.calls || ' answer(s) failed in the last ' || security.pipeline_num_v1('integration.hidden_error_window_minutes', 120)
                     || ' minutes (HTTP 4xx/5xx, time-out, transport error or "ok": false); last: ' || coalesce(r.sample, 'no sample'),
          'expected', 'A scheduled call that reaches the worker does its work; the job''s succeeded status is not taken as success',
          'source', 'integration-validate (yield checks)', 'validation_layer', 'V4',
          'evidence', jsonb_build_object('calls', r.calls, 'failed', r.failures, 'sample', r.sample),
          'severity', 'P1', 'root_cause_class', 'unclassified', 'workstream', 'A7'), 'integration-validate');
        v_seen := v_seen || v_fp; v_n := v_n + 1;
      end if;
    end loop;
    v_ok := v_ok || 'hidden_worker_error'::text; v_out := v_out || jsonb_build_object('hidden_worker_error', v_n);
  exception when others then v_err := v_err || jsonb_build_object('hidden_worker_error', left(sqlerrm, 300));
  end;

  -- 2. worker ledger past the watermark -> hourly tallies per mode; persistent zero yield
  begin
    select * into s from pipeline.integration_validate_state where check_key = 'yield_ledger';
    insert into pipeline.integration_yield_buckets as t(kind, key, bucket, calls, failures, items, ok)
    select 'ledger', l.mode, date_trunc('hour', l.run_at), count(*), sum(l.failed), sum(l.items), sum(l.ok)
      from pipeline.mode_outcome_ledger l
     where l.id > coalesce(s.watermark_id, 0) and l.run_at >= coalesce(s.watermark_at - interval '10 minutes', now() - v_back)  -- fixed: slack for rows written by longer transactions
     group by l.mode, date_trunc('hour', l.run_at)
    on conflict (kind, key, bucket) do update set calls = t.calls + excluded.calls, failures = t.failures + excluded.failures, items = t.items + excluded.items, ok = t.ok + excluded.ok;
    select max(l.id) into v_id from pipeline.mode_outcome_ledger l where l.id > coalesce(s.watermark_id, 0) and l.run_at >= coalesce(s.watermark_at - interval '10 minutes', now() - v_back);  -- fixed: same slack
    insert into pipeline.integration_validate_state as t(check_key, last_run_at, watermark_id, watermark_at) values ('yield_ledger', now(), v_id, now())
    on conflict (check_key) do update set last_run_at = now(), watermark_id = coalesce(excluded.watermark_id, t.watermark_id),
      watermark_at = case when excluded.watermark_id is null then t.watermark_at else now() end, last_error = null;
    v_n := 0;
    for r in select b.key, sum(b.calls) calls, sum(b.items) items, sum(b.ok) ok, sum(b.failures) failures
               from pipeline.integration_yield_buckets b where b.kind = 'ledger' and b.bucket >= date_trunc('hour', now() - v_zy) group by b.key loop
      if r.calls >= v_zmin and r.ok = 0 then
        v_wait := false;
        if r.failures = 0 and r.items = 0 then v_wait := coalesce(security.worker_mode_waiting_v1(r.key), false); end if;
        if r.failures > 0 or r.items > 0 or v_wait then
          v_fp := 'zero_yield:' || r.key;
          perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', v_fp,
            'title', 'Worker mode ' || r.key || ': calls with no work done', 'layer', 'Scheduling', 'subsystem', 'coverage-sweep mode ' || r.key,
            'failure', r.calls || ' call(s) in ' || security.pipeline_num_v1('integration.zero_yield_hours', 6) || ' hours, 0 items done, ' || r.items || ' taken, '
                       || r.failures || ' failed' || case when v_wait then ', work waiting' else '' end,
            'expected', 'A lane with work waiting finishes items; an idle lane is paused by the flag unit',
            'source', 'integration-validate (yield checks)', 'validation_layer', 'V4',
            'evidence', jsonb_build_object('calls', r.calls, 'items', r.items, 'ok', r.ok, 'failed', r.failures, 'work_waiting', v_wait),
            'severity', case when r.failures > 0 then 'P1' else 'P2' end, 'root_cause_class', 'unclassified', 'workstream', 'A7'), 'integration-validate');
          v_seen := v_seen || v_fp; v_n := v_n + 1;
        end if;
      end if;
    end loop;
    v_ok := v_ok || 'zero_yield'::text; v_out := v_out || jsonb_build_object('zero_yield', v_n);
  exception when others then v_err := v_err || jsonb_build_object('zero_yield', left(sqlerrm, 300));
  end;

  -- 3. incomplete pagination (course lists) and incomplete whole reads (entry matrices)
  begin
    select count(*), coalesce(jsonb_agg(distinct c.provider_id), '[]'::jsonb), coalesce(sum(substring(c.reason from '\((\d+) course addresses\)')::int - c.links_found), 0)
      into v_n, v_res, v_m
      from pipeline.provider_course_lists c
     where c.status = 'read' and substring(c.reason from '\((\d+) course addresses\)')::int > coalesce(c.links_found, 0);
    if v_n > 0 then
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'incomplete_pagination:course_lists',
        'title', 'Course lists read fewer course addresses than they list', 'layer', 'Layer 2', 'subsystem', 'pipeline.provider_course_lists (course_list_read)',
        'failure', v_n || ' course list(s) marked read with ' || v_m || ' listed course address(es) not reached (pages or a cap left out)',
        'expected', 'A course list is read to its last page, or its shortfall is recorded as partial', 'source', 'integration-validate (yield checks)', 'validation_layer', 'V4',
        'provider_ids', v_res, 'evidence', jsonb_build_object('lists', v_n, 'addresses_missing', v_m), 'severity', 'P2', 'root_cause_class', 'code_defect', 'workstream', 'A2'), 'integration-validate');
      v_seen := v_seen || 'incomplete_pagination:course_lists'::text;
    end if;
    select count(*), coalesce(jsonb_agg(distinct m.provider_id), '[]'::jsonb) into v_n, v_res
      from pipeline.entry_matrix_runs m where m.state = 'failed' and (m.error like 'held_incomplete%' or m.error like 'held_partial%');
    if v_n > 0 then
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'incomplete_read:entry_matrix',
        'title', 'Entry-matrix reads held as incomplete', 'layer', 'AER', 'subsystem', 'pipeline.entry_matrix_runs',
        'failure', v_n || ' run(s) held_incomplete or held_partial (a table column, slice or published minimum left out)',
        'expected', 'Whole-read completeness is shown before any row is admitted (direction 23:24 §1 AER D-R3)', 'source', 'integration-validate (yield checks)', 'validation_layer', 'V4',
        'provider_ids', v_res, 'evidence', jsonb_build_object('runs', v_n), 'severity', 'P2', 'root_cause_class', 'code_defect', 'workstream', 'A3'), 'integration-validate');
      v_seen := v_seen || 'incomplete_read:entry_matrix'::text;
    end if;
    v_ok := v_ok || array['incomplete_pagination', 'incomplete_read']::text[];
  exception when others then v_err := v_err || jsonb_build_object('incomplete', left(sqlerrm, 300));
  end;

  -- 4. repeated failed attempts per provider
  begin
    select count(*), coalesce(jsonb_agg(x.provider_id order by x.n desc), '[]'::jsonb), coalesce(max(x.n), 0) into v_n, v_res, v_m
      from (select p.provider_id, count(*) n from pipeline.coverage_course_pages p
             where p.read_status in ('fetch_failed', 'blocked') and p.read_attempts >= v_att group by p.provider_id having count(*) >= v_pmin) x;
    if v_n > 0 then
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'provider_failed_attempts:course_pages',
        'title', 'Providers whose course pages keep failing', 'layer', 'Layer 2', 'subsystem', 'pipeline.coverage_course_pages',
        'failure', v_n || ' provider(s) each have at least ' || v_pmin || ' course pages failing (fetch_failed or blocked) after ' || v_att || ' or more attempts (most: ' || v_m || ')',
        'expected', 'A provider whose pages keep failing gets a different acquisition route or is flagged for a person, not retried as before',
        'source', 'integration-validate (yield checks)', 'validation_layer', 'V4', 'provider_ids', v_res,
        'evidence', jsonb_build_object('providers', v_n, 'most_pages', v_m), 'severity', 'P2', 'root_cause_class', 'external', 'workstream', 'A2'), 'integration-validate');
      v_seen := v_seen || 'provider_failed_attempts:course_pages'::text;
    end if;
    select count(*), coalesce(jsonb_agg(d.provider_id), '[]'::jsonb) into v_n, v_res
      from pipeline.scholarship_discovery_providers d where d.status = 'failed' and d.attempts >= v_att;
    if v_n > 0 then
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'provider_failed_attempts:scholarship_discovery',
        'title', 'Scholarship discovery keeps failing for some providers', 'layer', 'Layer 2', 'subsystem', 'pipeline.scholarship_discovery_providers',
        'failure', v_n || ' provider(s) failed scholarship discovery ' || v_att || ' or more times', 'expected', 'Discovery succeeds or the provider is flagged with a cause',
        'source', 'integration-validate (yield checks)', 'validation_layer', 'V4', 'provider_ids', v_res, 'evidence', jsonb_build_object('providers', v_n),
        'severity', 'P2', 'root_cause_class', 'unclassified', 'workstream', 'A2'), 'integration-validate');
      v_seen := v_seen || 'provider_failed_attempts:scholarship_discovery'::text;
    end if;
    for r in select f.reason_code, count(*) n, jsonb_agg(f.provider_id) prov from pipeline.enrichment_flags f
              where f.entity = 'provider' and f.state = 'raised' and f.cleared_at is null and f.tries >= v_att group by f.reason_code loop
      v_fp := 'provider_failed_attempts:flag:' || r.reason_code;
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', v_fp,
        'title', 'Providers flagged ' || r.reason_code || ' after repeated tries', 'layer', 'Layer 2', 'subsystem', 'pipeline.enrichment_flags',
        'failure', r.n || ' provider(s) still flagged ' || r.reason_code || ' after ' || v_att || ' or more tries', 'expected', 'The flag clears or a person decides',
        'source', 'integration-validate (yield checks)', 'validation_layer', 'V4', 'provider_ids', r.prov, 'evidence', jsonb_build_object('providers', r.n),
        'severity', 'P2', 'root_cause_class', 'external', 'workstream', 'A2'), 'integration-validate');
      v_seen := v_seen || v_fp;
    end loop;
    v_ok := v_ok || 'provider_failed_attempts'::text;
  exception when others then v_err := v_err || jsonb_build_object('provider_failed_attempts', left(sqlerrm, 300));
  end;

  -- 5. condition cleared for the checks that ran; P0 alert path (none of these is P0 today)
  for r in select i.id, i.fingerprint, i.condition_cleared_at, i.status from pipeline.integration_issues i
            where i.status <> 'closed' and split_part(i.fingerprint, ':', 1) = any (v_ok) loop
    if r.fingerprint = any (v_seen) then
      perform security.integration_alert_sync_v1(r.id, true);
    else
      if r.condition_cleared_at is null then
        update pipeline.integration_issues set condition_cleared_at = now() where id = r.id;
        insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note)
        values (r.id, 'not_observed', r.status, r.status, 'integration-validate', 'condition no longer observed; close after production verification');
      end if;
      perform security.integration_alert_sync_v1(r.id, false);
    end if;
  end loop;

  delete from pipeline.integration_yield_buckets b where b.bucket < now() - v_keep;
  return v_out || jsonb_build_object('ran', to_jsonb(v_ok), 'errors', v_err, 'observed', cardinality(v_seen));
end $function$;
revoke all on function security.integration_yield_checks_v1() from public, anon, authenticated;
comment on function security.integration_yield_checks_v1() is 'Platform Admin direction 2 Nov 2026 23:24 §3 (job integration-validate): hidden worker errors under succeeded jobs, persistent zero yield, incomplete pagination and whole reads, repeated failed attempts per provider; each feeds the integration queue by fingerprint';

-- 4. per-stage yield for the Admin ---------------------------------------------------------------------------------------------------------------
create or replace function security.pipeline_yield_v1(p_hours int default null) returns jsonb
language plpgsql stable security definer set search_path to '' set statement_timeout to '20s' as $function$
-- Platform Admin direction 2 Nov 2026 23:24 §3: every stage distinguished, per lane, over the window (existing tables only). Read-back is what the
-- consumer projection holds for the records published in the window (search.course_documents for course links; published scholarships and
-- provider descriptions of published providers; active entry rows of published providers).
declare v_h int := coalesce(p_hours, security.pipeline_num_v1('integration.yield_window_hours', 24)::int); v_since timestamptz; v jsonb;
begin
  v_since := now() - make_interval(hours => v_h);
  v := jsonb_build_object('window_hours', v_h, 'since', v_since, 'lanes', jsonb_build_array(
    -- scholarships
    jsonb_build_object('lane', 'scholarships', 'label', 'Scholarships', 'stages', jsonb_build_object(
      'invoked', (select jsonb_build_object('calls', count(*), 'failed_calls', count(*) filter (where l.status >= 400 or l.failed > 0)) from pipeline.mode_outcome_ledger l
                   where l.run_at >= v_since and l.mode in ('scholarship_discover', 'scholarship_listing', 'scholarship_read', 'scholarship_ai')),
      'source_accessed', (select count(*) from pipeline.scholarship_discovery_providers d where d.discovered_at >= v_since)
                         + (select count(*) from pipeline.scholarship_listing_pages p where p.read_at >= v_since),
      'pages_discovered', (select count(*) from pipeline.scholarship_page_candidates c where c.found_at >= v_since),
      'read_completely', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at >= v_since and c.read_status = 'read')
                         + (select count(*) from pipeline.scholarship_pages p where p.read_at >= v_since and p.read_status = 'read'),
      'extracted', (select count(*) from pipeline.scholarship_ai_extractions e where e.at >= v_since and e.error is null),
      'accepted_or_held', (select jsonb_build_object('accepted', count(*) filter (where c.admit_status = 'admitted'), 'held', count(*) filter (where c.admit_status = 'matched_held'),
                                                     'rejected', count(*) filter (where c.admit_status in ('rejected', 'duplicate', 'withdrawn', 'skipped')))
                             from pipeline.scholarship_page_candidates c where c.admitted_at >= v_since or (c.admit_status is not null and c.read_at >= v_since)),
      'published', (select count(*) from scholarship.scholarships s where s.updated_at >= v_since and s.publication_status = 'published' and s.lifecycle_status = 'active'),
      'consumer_read_back', (select count(*) from scholarship.scholarships s where s.updated_at >= v_since and s.publication_status = 'published' and s.lifecycle_status = 'active'
                               and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)))),
    -- course pages (official course links)
    jsonb_build_object('lane', 'course_pages', 'label', 'Course pages and official links', 'stages', jsonb_build_object(
      'invoked', (select jsonb_build_object('calls', count(*), 'failed_calls', count(*) filter (where l.status >= 400 or l.failed > 0)) from pipeline.mode_outcome_ledger l
                   where l.run_at >= v_since and l.mode in ('link_search', 'ai_match', 'read', 'reidentify', 'course_list_read', 'source_find', 'discover')),
      'source_accessed', (select count(*) from pipeline.coverage_course_pages p where p.read_at >= v_since),
      'pages_discovered', (select count(*) from pipeline.coverage_course_pages p where p.bound_at >= v_since),
      'read_completely', (select count(*) from pipeline.coverage_course_pages p where p.read_at >= v_since and p.read_status = 'read'),
      'extracted', (select count(*) from pipeline.coverage_course_pages p where p.l3_handoff_at >= v_since),
      'accepted_or_held', (select jsonb_build_object('accepted', count(*) filter (where k.status = 'active'), 'held', count(*) filter (where k.status = 'unverified'))
                             from catalogue.course_links k where k.link_type = 'official_course' and k.created_at >= v_since)
                          || jsonb_build_object('held_in_layer4', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code = 'official_course_url' and i.created_at >= v_since)),
      'published', (select count(*) from catalogue.course_links k where k.link_type = 'official_course' and k.status = 'active' and k.is_primary and k.updated_at >= v_since),
      'consumer_read_back', (select count(*) from catalogue.course_links k join search.course_documents d on d.course_id = k.course_id and d.official_course_url = k.url and d.publication_status = 'published'
                              where k.link_type = 'official_course' and k.status = 'active' and k.is_primary and k.updated_at >= v_since))),
    -- academic entry requirements (AER)
    jsonb_build_object('lane', 'aer', 'label', 'Academic entry requirements', 'stages', jsonb_build_object(
      'invoked', (select jsonb_build_object('calls', count(*), 'failed_calls', count(*) filter (where l.status >= 400 or l.failed > 0)) from pipeline.mode_outcome_ledger l
                   where l.run_at >= v_since and l.mode in ('entry_ai', 'entry_inspect')),
      'source_accessed', (select count(*) from pipeline.entry_matrix_sources m where m.read_at >= v_since),
      'pages_discovered', (select count(*) from pipeline.entry_matrix_sources m where m.created_at >= v_since),
      'read_completely', (select count(*) from pipeline.entry_matrix_runs m where m.done_at >= v_since and m.state = 'done'),
      'extracted', (select count(*) from catalogue.provider_entry_matrix x where x.created_at >= v_since) + (select count(*) from catalogue.course_entry_requirements x where x.created_at >= v_since),
      'accepted_or_held', (select jsonb_build_object('accepted', count(*) filter (where x.status = 'active'), 'held', count(*) filter (where x.status in ('proposed', 'unverified')))
                             from catalogue.provider_entry_matrix x where x.updated_at >= v_since),
      'published', (select count(*) from catalogue.provider_entry_matrix x where x.status = 'active' and x.updated_at >= v_since)
                   + (select count(*) from catalogue.course_entry_requirements x where x.status = 'active' and x.updated_at >= v_since),
      'consumer_read_back', (select count(*) from catalogue.provider_entry_matrix x where x.status = 'active' and x.updated_at >= v_since
                               and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = x.provider_id)))),
    -- university descriptions
    jsonb_build_object('lane', 'descriptions', 'label', 'University descriptions', 'stages', jsonb_build_object(
      'invoked', (select jsonb_build_object('calls', count(*), 'failed_calls', count(*) filter (where l.status >= 400 or l.failed > 0)) from pipeline.mode_outcome_ledger l
                   where l.run_at >= v_since and l.mode = 'provider_description'),
      'source_accessed', (select count(*) from pipeline.provider_description_reads r where r.source_captured_at >= v_since),
      'pages_discovered', (select count(*) from pipeline.provider_description_reads r where r.created_at >= v_since and r.source_url is not null),
      'read_completely', (select count(*) from pipeline.provider_description_reads r where r.updated_at >= v_since and r.evidence_id is not null),
      'extracted', (select count(*) from pipeline.provider_description_reads r where r.updated_at >= v_since and r.proposal is not null),
      'accepted_or_held', (select jsonb_build_object('accepted', count(*) filter (where r.state in ('admitted', 'verified')), 'held', count(*) filter (where r.state in ('proposed', 'held')),
                                                     'rejected', count(*) filter (where r.state in ('rejected', 'dead_letter')))
                             from pipeline.provider_description_reads r where r.updated_at >= v_since),
      'published', (select count(*) from pipeline.provider_description_reads r where r.published_at >= v_since),
      'consumer_read_back', (select count(*) from pipeline.provider_description_reads r join catalogue.providers p on p.id = r.provider_id
                              where r.published_at >= v_since and nullif(btrim(p.description), '') is not null and p.publication_status = 'published' and p.lifecycle_status = 'active')))));
  return v;
end $function$;
revoke all on function security.pipeline_yield_v1(int) from public, anon, authenticated;

create or replace function public.admin_pipeline_yield(p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'PIM Admin role or above required' using errcode = '42501'; end if;
  return security.pipeline_yield_v1(nullif(p_args->>'hours', '')::int);
end $function$;
revoke all on function public.admin_pipeline_yield(jsonb) from public, anon;
grant execute on function public.admin_pipeline_yield(jsonb) to authenticated;

-- 5. the job runs the yield checks after the integration checks (G1: the catalogue says so; the job keeps its active state) -----------------------
update pipeline.automation_catalogue set description = description || ' Then the yield checks (security.integration_yield_checks_v1): worker answers that failed while the job counts as succeeded, persistent zero yield, incomplete pagination and whole reads, repeated failed attempts per provider.'
 where jobname = 'integration-validate' and description not like '%integration_yield_checks_v1%';
do $c$ begin
  perform cron.alter_job((select jobid from cron.job where jobname = 'integration-validate'),
                         command := $j$select security.integration_validate_v1(), security.integration_yield_checks_v1()$j$);
end $c$;

-- 6. component register --------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.integration_yield_buckets', 'Platform', 'Pipeline yield checks: hourly tallies of worker answers and yield', 'active', '{}', '20261103040000'),
 ('function', 'security.integration_yield_checks_v1', 'Platform', 'Pipeline yield checks: hidden errors, zero yield, incomplete pagination, repeated failures', 'active', '{}', '20261103040000'),
 ('function', 'security.pipeline_yield_v1', 'Platform', 'Pipeline yield: per-stage counts per lane', 'active', '{}', '20261103040000'),
 ('function', 'public.admin_pipeline_yield', 'Platform', 'Pipeline yield screen (PIM Admin and above)', 'active', '{}', '20261103040000')
on conflict do nothing;
