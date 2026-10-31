-- Re-issue of 20261031090000 (not applied: its md5 guard refused the health-check edit on 31 Oct 2026 20:03 AEDT because the expected md5 predated a
-- last change of the alert issue area to 'scheduled jobs'; the transaction rolled back and nothing changed). Same content, expected md5 corrected.
-- CF-247 StudySearch SS-014A to SS-014E (Platform Admin mandate 31 Oct 2026 19:22, "SS-014 Operational Automation and Production
-- Acceptance"; decisions D7 to D11; admin docs/platform/nz-enrichment-brief/2026-10-31-studysearch-transformation.md §31).
-- Why (verified live 31 Oct 2026, 19:30 to 20:10 AEDT):
--   A. The health check (job platform-health, every 10 minutes) took 21.3 s at the median over 144 runs (max 32 s), 53 minutes of
--      database time a day. Its scholarship section took 11.9 s at the median: it worked out the scholarship Firecrawl hold of the same
--      1,138 waiting discovery providers twice (once for the stall count, once for the held count) and again per candidate page, each
--      through nested functions planned on every call. Measured in a cold session: 11.4 s before, 2.3 s after; same three counts (0, 1,138, 0).
--   A2. "Coverage page reading has stopped ... (its scheduled job is missing or paused)" opened as CRITICAL 116 times in 7 days (median
--      10 minutes each). Every one was coverage-read paused on purpose by the flag unit after idle runs, which switches it on again when
--      work waits (security.flag_jobs_v1). A critical that is normal operation would make any alert channel unusable.
--   B. Search refresh requests had no health check: 1,900 requests in 7 days, wait p50 10 min, p95 31 min, max 40 min, none open; a stall
--      would have shown only as stale website data.
--   C. Critical issues reached a person only on the Admin. The existing outbox (pipeline.queue_watch_alerts, delivered by the hourly
--      "Work queue alerts" scheduled task to push and e-mail) covers work queues only and is tied to them by a foreign key.
--   D. Targets T1 to T8 (OPERATIONAL-LIMITS.md 1.1) had no weekly measurement.
-- What:
--   A.  security.platform_health_check_v1: the hold of each provider is worked out once per run and shared by the three counts.
--   A2. security.platform_health_stall_v1: a queue whose job is paused by the flag unit's idle rule is "info" until the critical age (2 h),
--       then critical as before; a job missing or paused by a person stays critical at once. Thresholds unchanged.
--   B.  New check search_refresh (every 10 minutes): slow after health.search_refresh_slow_minutes (40, target T7) with a known reason,
--       stalled (critical) after health.search_refresh_stalled_minutes (90) or at once when the job is missing, paused, failing or not
--       running; the issue names the cause, the writer holding the lock, the job's last result and the next step.
--   C.  Alert framework, external delivery OFF (D7): outbox pipeline.platform_alerts; job platform-alerts (every 10 minutes) raises an
--       alert for an unacknowledged issue at or above alerts.min_severity (critical) open alerts.confirm_minutes (15), suppresses repeats
--       of the same check within alerts.cooldown_minutes (60), escalates warning to critical, reminds after alerts.reminder_hours (12),
--       sends one recovery notice, retries with backoff (alerts.retry_minutes, alerts.max_attempts) and fails visibly. While
--       alerts.delivery_enabled is off every alert is recorded as "held" and nothing leaves the platform. Destinations: the existing
--       scheduled-task path (security.platform_alerts_take_v1 / _confirm_v1) or a webhook (vault secret studysearch_alert_webhook_url,
--       alerts.webhook_enabled). Test mode: alerts.test_mode prefixes [TEST]; a test alert from the screen. Acknowledgement on Platform
--       health (the column existed; nothing could set it). New check alerts watches the outbox itself.
--   D.  security.ops_scorecard_v1 (T1 to T8 and the eight report areas, observed vs incomplete windows); job ops-scorecard (every
--       morning) stores the week so far and finalises the last week in pipeline.ops_scorecards. The scheduler keeps only about three days
--       of run history (log starts 28 Oct 03:47), so job reliability is kept day by day as it is recorded. Platform health shows both weeks.
-- Replaces: security.platform_health_check_v1, security.platform_health_stall_v1 (same names; md5-guarded edits)
-- Retires: nothing (pipeline.queue_watch_alerts and its scheduled task stay for work queues)
-- Nothing dropped, deleted or renamed. Consumer API untouched (G3): no consumer function, table, column or edge function changes.

create or replace function pg_temp.edit_v2(p_sig text, p_before text, p_after text, p_regions text[][], p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text; v_a int; v_b int;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  -- regions: replace from the start of marker 1 up to the start of marker 2; each marker must occur exactly once
  for i in 1 .. coalesce(array_length(p_regions, 1), 0) loop
    if (length(v_def) - length(replace(v_def, p_regions[i][1], ''))) / length(p_regions[i][1]) <> 1
       or (length(v_def) - length(replace(v_def, p_regions[i][2], ''))) / length(p_regions[i][2]) <> 1 then
      raise exception '%: region % markers must each occur once', p_sig, i;
    end if;
    v_a := strpos(v_def, p_regions[i][1]); v_b := strpos(v_def, p_regions[i][2]);
    if v_b <= v_a then raise exception '%: region % markers out of order', p_sig, i; end if;
    v_def := left(v_def, v_a - 1) || replace(p_regions[i][3], chr(13), '') || substr(v_def, v_b);
  end loop;
  for i in 1 .. coalesce(array_length(p_edits, 1), 0) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 1. settings (G2): every threshold, switch and target is a setting with a label, range, unit and used_by line
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'health.search_refresh_slow_minutes', 'Health: search refresh is slow after',
  'A search refresh request waiting longer than this is shown as a warning with its cause (the refresh gap, another writer). Target T7.', 'number',
  to_jsonb(40), 10, 240, 'minutes', 799, 'Platform upkeep', 'security.platform_health_check_v1 (search_refresh check); security.ops_scorecard_v1 (T7)', 'StudySearch SS-014B (31 Oct 2026): T7, refresh requests processed within 40 minutes'),
 ('pipeline', 'health.search_refresh_stalled_minutes', 'Health: search refresh has stalled after',
  'A search refresh request waiting longer than this is critical, whatever the cause. A missing, paused, failing or idle job is critical as soon as a request is slow.', 'number',
  to_jsonb(90), 20, 1440, 'minutes', 800, 'Platform upkeep', 'security.platform_health_check_v1 (search_refresh check)', 'StudySearch SS-014B (31 Oct 2026)'),
 ('pipeline', 'alerts.delivery_enabled', 'Alerts: deliver outside the platform',
  'Off: every alert is recorded on Platform health as held and nothing leaves the platform. On: the approved destination collects them. Switch on only after the Platform Admin approves the destination (decision D7).', 'boolean',
  to_jsonb(false), null, null, null, 964, 'Alerts', 'security.platform_alerts_evaluate_v1, security.platform_alerts_take_v1 (job platform-alerts)', 'StudySearch SS-014C (31 Oct 2026), D7: no external delivery until the destination and credentials are approved'),
 ('pipeline', 'alerts.webhook_enabled', 'Alerts: deliver by webhook',
  'On: alerts are posted to the webhook address stored in the vault (studysearch_alert_webhook_url) instead of the scheduled task. Needs delivery switched on.', 'boolean',
  to_jsonb(false), null, null, null, 965, 'Alerts', 'security.platform_alerts_webhook_v1 (job platform-alerts)', 'StudySearch SS-014C (31 Oct 2026), D7'),
 ('pipeline', 'alerts.test_mode', 'Alerts: test mode',
  'On: every alert title starts with [TEST], so a destination can be tried end to end without being mistaken for a real incident.', 'boolean',
  to_jsonb(false), null, null, null, 966, 'Alerts', 'security.platform_alerts_evaluate_v1', 'StudySearch SS-014C (31 Oct 2026)'),
 ('pipeline', 'alerts.recovery_notice', 'Alerts: send a recovery notice',
  'On: when an alerted issue closes, one notice says it has recovered.', 'boolean',
  to_jsonb(true), null, null, null, 967, 'Alerts', 'security.platform_alerts_evaluate_v1', 'StudySearch SS-014C (31 Oct 2026)'),
 ('pipeline', 'alerts.min_severity', 'Alerts: lowest severity that alerts',
  '3 = critical issues only; 2 = warnings and critical issues.', 'number',
  to_jsonb(3), 2, 3, 'level', 968, 'Alerts', 'security.platform_alerts_evaluate_v1', 'StudySearch SS-014C (31 Oct 2026)'),
 ('pipeline', 'alerts.confirm_minutes', 'Alerts: issue must stay open for',
  'An issue alerts only after it has been open this long (seen on two health runs), so a passing blip does not alert.', 'number',
  to_jsonb(15), 0, 240, 'minutes', 969, 'Alerts', 'security.platform_alerts_evaluate_v1', 'StudySearch SS-014C (31 Oct 2026): flap guard'),
 ('pipeline', 'alerts.cooldown_minutes', 'Alerts: quiet period per check',
  'The same check does not alert again within this time, even if its issue closed and opened again.', 'number',
  to_jsonb(60), 5, 1440, 'minutes', 970, 'Alerts', 'security.platform_alerts_evaluate_v1', 'StudySearch SS-014C (31 Oct 2026): deduplication'),
 ('pipeline', 'alerts.reminder_hours', 'Alerts: remind about an open issue after',
  'An alerted issue that is still open and not acknowledged is alerted again after this many hours. 0 = never.', 'number',
  to_jsonb(12), 0, 168, 'hours', 971, 'Alerts', 'security.platform_alerts_evaluate_v1', 'StudySearch SS-014C (31 Oct 2026)'),
 ('pipeline', 'alerts.max_attempts', 'Alerts: delivery attempts',
  'An alert not confirmed as delivered is tried this many times, then marked failed (shown on Platform health).', 'number',
  to_jsonb(5), 1, 20, 'attempts', 972, 'Alerts', 'security.platform_alerts_evaluate_v1, security.platform_alerts_confirm_v1', 'StudySearch SS-014C (31 Oct 2026)'),
 ('pipeline', 'alerts.retry_minutes', 'Alerts: first retry after',
  'Wait before the first retry of a delivery; each later retry waits twice as long.', 'number',
  to_jsonb(10), 1, 240, 'minutes', 973, 'Alerts', 'security.platform_alerts_evaluate_v1, security.platform_alerts_confirm_v1', 'StudySearch SS-014C (31 Oct 2026)'),
 ('pipeline', 'alerts.collect_within_minutes', 'Alerts: collected within',
  'With delivery on, an alert still waiting after this long means the destination is not collecting: shown as critical on Platform health.', 'number',
  to_jsonb(120), 15, 1440, 'minutes', 974, 'Alerts', 'security.platform_health_check_v1 (alerts check)', 'StudySearch SS-014C (31 Oct 2026)'),
 ('pipeline', 'alerts.webhook_batch', 'Alerts: webhook posts per run',
  'Most alerts posted to the webhook in one run of platform-alerts.', 'number',
  to_jsonb(20), 1, 200, 'alerts', 975, 'Alerts', 'security.platform_alerts_webhook_v1 (job platform-alerts)', 'StudySearch SS-014C (31 Oct 2026)'),
 ('pipeline', 'targets.job_failures_per_day', 'Target T1: failed job runs a day',
  'Failed runs of active scheduled jobs allowed in a day for the weekly scorecard to count T1 as met.', 'number',
  to_jsonb(0), 0, 100, 'runs', 976, 'Operating targets', 'security.ops_scorecard_v1 (T1)', 'StudySearch SS-014D (31 Oct 2026): OPERATIONAL-LIMITS.md 1.1 T1'),
 ('pipeline', 'targets.ai_credit_min_usd', 'Target T2: lowest OpenRouter credit',
  'The OpenRouter credit should stay at or above this. The daily spend target is the AI spend ceiling (budgets.ai_daily_ceiling_usd).', 'number',
  to_jsonb(10), 0, 1000, 'US$', 977, 'Operating targets', 'security.ops_scorecard_v1 (T2)', 'StudySearch SS-014D (31 Oct 2026): T2'),
 ('pipeline', 'targets.futile_items_per_day', 'Target T4: futile enrichment items a day',
  'Enrich items skipped because the course page found is for another course, allowed in a day.', 'number',
  to_jsonb(100), 0, 10000, 'items', 978, 'Operating targets', 'security.ops_scorecard_v1 (T4)', 'StudySearch SS-014D (31 Oct 2026): T4'),
 ('pipeline', 'targets.review_oldest_days', 'Target T5: oldest Layer 4 review item',
  'The oldest pending Layer 4 review item should be younger than this.', 'number',
  to_jsonb(14), 1, 365, 'days', 979, 'Operating targets', 'security.ops_scorecard_v1 (T5)', 'StudySearch SS-014D (31 Oct 2026): T5'),
 ('pipeline', 'targets.api_search_p95_ms', 'Target T6: website search p95',
  'Website search requests (pages up to the page size below) should answer within this at the 95th percentile.', 'number',
  to_jsonb(3000), 100, 60000, 'ms', 980, 'Operating targets', 'security.ops_scorecard_v1 (T6)', 'StudySearch SS-014D (31 Oct 2026): T6'),
 ('pipeline', 'targets.api_search_page_size', 'Target T6: search page size measured',
  'Search requests returning at most this many items are measured against the p95 target (the recommended page size).', 'number',
  to_jsonb(20), 1, 100, 'items', 981, 'Operating targets', 'security.ops_scorecard_v1 (T6)', 'StudySearch SS-014D (31 Oct 2026): T6, recommend 20 per page'),
 ('pipeline', 'targets.reference_bundle_hours', 'Target T7: reference bundle age',
  'The consumer reference bundle should be rebuilt within this many hours.', 'number',
  to_jsonb(2), 1, 48, 'hours', 982, 'Operating targets', 'security.ops_scorecard_v1 (T7)', 'StudySearch SS-014D (31 Oct 2026): T7')
on conflict do nothing;

-- 2. tables
create table if not exists pipeline.platform_alerts (
  id bigserial primary key,
  issue_id uuid references pipeline.platform_issues(id) on delete set null,
  check_key text not null,
  kind text not null check (kind in ('raised', 'escalated', 'reminder', 'recovered', 'test')),
  severity text not null check (severity in ('critical', 'warning', 'info')),
  title text not null,
  body text not null,
  status text not null check (status in ('held', 'pending', 'sending', 'sent', 'failed')),
  attempts int not null default 0,
  next_attempt_at timestamptz not null default now(),
  lease_until timestamptz,
  sent_via text,
  sent_at timestamptz,
  net_request_id bigint,
  last_error text,
  dedupe_key text not null unique,
  created_at timestamptz not null default now()
);
create index if not exists platform_alerts_issue_idx on pipeline.platform_alerts (issue_id, created_at desc);
create index if not exists platform_alerts_check_idx on pipeline.platform_alerts (check_key, created_at desc);
create index if not exists platform_alerts_open_idx on pipeline.platform_alerts (status, next_attempt_at) where status in ('pending', 'sending');
comment on table pipeline.platform_alerts is 'StudySearch SS-014C (Platform Admin 31 Oct 2026, decision D7): outbox of platform health alerts. One row per alert (raised, escalated, reminder, recovered, test) for an issue in pipeline.platform_issues, written by job platform-alerts (security.platform_alerts_evaluate_v1) under the alerts.* settings, deduplicated by dedupe_key and the per-check quiet period. status held = recorded only (external delivery off); pending / sending / sent / failed = delivery by the approved destination (scheduled task: security.platform_alerts_take_v1 and _confirm_v1; or webhook) with retries and backoff. Work-queue alerts stay in pipeline.queue_watch_alerts. Never read by the consumer API.';
alter table pipeline.platform_alerts enable row level security;
revoke all on pipeline.platform_alerts from public, anon, authenticated;
revoke all on sequence pipeline.platform_alerts_id_seq from public, anon, authenticated;

create table if not exists pipeline.ops_scorecards (
  week_start date primary key,
  week_end date not null,
  generated_at timestamptz not null default now(),
  generated_by text not null,
  scorecard jsonb not null
);
comment on table pipeline.ops_scorecards is 'StudySearch SS-014D (Platform Admin 31 Oct 2026): the weekly operational scorecard against targets T1 to T8 (admin docs/platform/OPERATIONAL-LIMITS.md), one row per Monday-to-Sunday week (Melbourne), written by job ops-scorecard (security.ops_scorecard_record_v1) from existing measurements; each target says whether it was observed for the whole week, measured at report time, or not measurable. Never read by the consumer API.';
alter table pipeline.ops_scorecards enable row level security;
revoke all on pipeline.ops_scorecards from public, anon, authenticated;

-- 3. health checks: two new rows (the function below runs them)
insert into pipeline.platform_health_checks(key, area, label, status, detail, cadence_minutes, slow, sort_order) values
 ('search_refresh', 'search/API', 'Search refresh requests', 'skipped', '{}'::jsonb, 10, false, 125),
 ('alerts', 'scheduled jobs', 'Alert outbox', 'skipped', '{}'::jsonb, 10, false, 160)
on conflict (key) do nothing;

-- 4. A2: a job paused by the flag unit's idle rule is information until the critical age
select pg_temp.edit_v2('security.platform_health_stall_v1(text,text,text,text,timestamp with time zone,text,integer)', 'e1c74fa638bd1a52832102122cdfa50c', 'fe27fdb050f8a7385fd7885199da4bc4',
 array[]::text[][], array[
 array[$o$v_age interval:=now()-coalesce(p_last_progress,'-infinity'::timestamptz);$o$, $n$v_age interval:=now()-coalesce(p_last_progress,'-infinity'::timestamptz); v_unit boolean:=false;$n$],
 array[$o$  return jsonb_build_object('queue',p_key,'status','stalled',$o$, $n$  -- SS-014 (31 Oct 2026): a job the flag unit paused because its runs found nothing is switched on again by the flag unit when work
  -- waits (security.flag_jobs_v1, security.waste_idle_guard_v1); until the critical age that is information, not a breakage
  if v_active is false then
    select true into v_unit from pipeline.enrichment_flags f
     where f.entity='job' and f.entity_key=p_job and f.field='' and f.reason_code='idle_paused' and f.cleared_at is null and coalesce(f.state,'raised')='raised' limit 1;
    v_unit:=coalesce(v_unit,false);
  end if;
  return jsonb_build_object('queue',p_key,'status','stalled',$n$],
 array[$o$'job',p_job,'job_active',coalesce(v_active,false),'stalled_minutes'$o$, $n$'job',p_job,'job_active',coalesce(v_active,false),'paused_by_flag_unit',v_unit,'stalled_minutes'$n$],
 array[$o$case when v_age>v_crit or coalesce(v_active,false)=false then 'critical' else 'warning' end$o$, $n$case when v_age>v_crit or (coalesce(v_active,false)=false and not v_unit) then 'critical' when v_unit then 'info' else 'warning' end$n$],
 array[$o$case when v_active is distinct from true then ' (its scheduled job is missing or paused)' else '' end$o$, $n$case when v_unit then ' (its job is paused because its recent runs found nothing; the flag unit switches it on again when work is waiting)' when v_active is distinct from true then ' (its scheduled job is missing or paused)' else '' end$n$]],
 array[1, 1, 1, 1, 1]);

-- 5. A, B, C: the health check (scholarship counts once per provider; search refresh check; alert outbox check)
select pg_temp.edit_v2('security.platform_health_check_v1(boolean)', 'd245c53574b1de0251711b0cb41c47cf', 'b648e6494ccf39dbbe7eea6cec18f993',
 array[
  array[$m$      select max(read_at) into v_ts from pipeline.scholarship_page_candidates;$m$, $m$        'note','Held by the per-university Firecrawl cap$m$,
$r$      -- SS-014A (31 Oct 2026): whether each provider is held by the scholarship Firecrawl rules is worked out once and shared by the candidate,
      -- discovery and held counts (it was worked out up to three times per provider, about 10 s a run); same rules, same counts
      with dp as materialized (select d.provider_id, d.website from pipeline.scholarship_discovery_providers d where d.status='pending' and d.attempts<3),
           cand as materialized (select c.provider_id, c.url from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
                                  where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and c.attempts<3),
           hp as materialized (select x.provider_id, security.fc_sch_held_v1(x.provider_id, true) held from (select dp.provider_id from dp union select cand.provider_id from cand) x)
      select (select count(*) from cand join hp on hp.provider_id=cand.provider_id where not hp.held and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id=cand.provider_id)
                and not security.third_party_host_v1(cand.url) and not security.provider_sch_search_off_v1(cand.provider_id)),
             (select count(*) from dp join hp on hp.provider_id=dp.provider_id where not hp.held and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id=dp.provider_id)
                and not security.third_party_host_v1(coalesce(dp.website, '')) and not security.provider_sch_search_off_v1(dp.provider_id)),
             (select count(*) from dp join hp on hp.provider_id=dp.provider_id where hp.held)
        into v_n, v_n2, v_n3;
      select max(read_at) into v_ts from pipeline.scholarship_page_candidates;
      v_q:=v_q||security.platform_health_stall_v1('scholarship_queues:candidates','scholarships','Scholarship candidate page reading','scholarship-discover',v_ts,'select '||v_n);  -- 16 Oct 2026: only pages a reader can take
      select max(updated_at) into v_ts from pipeline.scholarship_discovery_providers;
      v_q:=v_q||security.platform_health_stall_v1('scholarship_queues:discover','scholarships','Scholarship provider discovery','scholarship-discover',v_ts,'select '||v_n2);  -- 16 Oct 2026: only providers discovery can take
      -- 16 Oct 2026: work held by the per-university cap, by policy (small Australian providers) or by settings, shown apart from stalls
      v_q:=v_q||jsonb_build_object('queue','scholarship_queues:held','status','held',
        'pages_held_by_cap',(select count(*) from pipeline.scholarship_pages p join scholarship.scholarships s on s.id=p.scholarship_id and s.lifecycle_status='active'
            where p.next_read_at<=now() and p.attempts<5 and p.requested_at is null and security.fc_sch_held_v1(s.provider_id, false)),
        'providers_not_searched',v_n3,
$r$],
  array[$m$  -- 5. record issues (dedup on check_key), auto-resolve what cleared, store check status$m$, $m$  for r in select distinct on (x.check_key) x.check_key, x.severity, x.area, x.title, x.detail$m$,
$r$  -- 4.15 SS-014B (31 Oct 2026): search refresh requests. Slow = waiting past the target for a known reason (the refresh gap, another
  -- writer); stalled = nothing is processing them (job missing, paused, failing or not running) or waiting past the stalled limit.
  if security.platform_health_due_v1('search_refresh',p_force) then
    v_t:=clock_timestamp();
    begin
      select count(*), min(q.requested_at) into v_n, v_ts from search.refresh_requests q where q.processed_at is null;
      select max(q.processed_at) into v_ts2 from search.refresh_requests q where q.processed_at is not null;
      v_num:=coalesce(round(extract(epoch from now()-v_ts)/60),0);
      select j.jobid, j.active, j.schedule into r from cron.job j where j.jobname='search-refresh-requested';
      v_x:=null; v_q:=null;
      select jsonb_build_object('at',d.start_time,'status',d.status,'result',left(d.return_message,200)) into v_x
        from cron.job_run_details d where d.jobid=r.jobid order by d.start_time desc limit 1;
      select jsonb_build_object('pid',a.pid,'since',coalesce(a.xact_start,a.query_start),'query',left(regexp_replace(a.query,'\s+',' ','g'),120)) into v_q
        from pg_locks l join pg_stat_activity a on a.pid=l.pid
       where l.locktype='advisory' and l.granted and l.objsubid=1 and l.objid=((hashtext('cf247:search_course_documents_writer')::bigint) & 4294967295)::oid limit 1;  -- fixed: the one writer lock (W27)
      v_txt:=case when r.jobid is null then 'job_missing' when not r.active then 'job_paused'
                  when v_x->>'status'='failed' then 'job_failing'
                  when v_x is null or (v_x->>'at')::timestamptz < now()-make_interval(secs=>3*coalesce(security.platform_cron_interval_seconds(r.schedule),600)) then 'job_not_running'  -- fixed: three missed runs
                  when v_q is not null or v_x->>'result' ilike '%another search-document writer%' then 'writer_busy'
                  when v_x->>'result' ilike '%refresh gap%' then 'refresh_gap'
                  else 'waiting_for_next_run' end;
      if v_n>0 and v_num>security.pipeline_num_v1('health.search_refresh_slow_minutes', 40) then
        v_bool:=v_num>security.pipeline_num_v1('health.search_refresh_stalled_minutes', 90) or v_txt in ('job_missing','job_paused','job_failing','job_not_running');
        v_args:=case v_txt
          when 'job_missing' then 'Schedule the job search-refresh-requested again (Automations); the requests are kept and are processed at its first run.'
          when 'job_paused' then 'Switch on the job search-refresh-requested (Automations); the requests are kept and are processed at its next run.'
          when 'job_failing' then 'Its last run failed ('||coalesce(v_x->>'result','no message')||'). Fix the error; the requests are kept and are processed at the next successful run.'
          when 'job_not_running' then 'The job is switched on but has not run since '||coalesce(to_char((v_x->>'at')::timestamptz at time zone 'Australia/Melbourne','DD Mon HH24:MI'),'it was scheduled')||'. Check the scheduler and the database connections.'
          when 'writer_busy' then 'Another search-document writer holds the writer lock'||coalesce(' since '||to_char((v_q->>'since')::timestamptz at time zone 'Australia/Melbourne','HH24:MI')||' (process '||(v_q->>'pid')||')','')||'. The requests are processed when it finishes; if it has run for over an hour, look at that writer.'
          when 'refresh_gap' then 'Automatic requests wait for the refresh gap (setting search.refresh_min_gap_minutes, '||security.pipeline_num_v1('search.refresh_min_gap_minutes', 30)||' minutes). No action unless the gap was raised by mistake.'
          else 'The job ran without processing them; they are processed at its next run. If this persists, look at its last result.' end;
        v_found:=v_found||security.platform_health_issue_v1('search_refresh:waiting', case when v_bool then 'critical' else 'warning' end, 'search/API',
          'Search refresh '||case when v_bool then 'has stalled' else 'is slow' end||': '||v_n||' request(s) waiting, the oldest for '||v_num||' minutes ('||replace(v_txt,'_',' ')||')',
          jsonb_build_object('pending',v_n,'oldest_requested_at',v_ts,'oldest_minutes',v_num,'cause',v_txt,'next_step',v_args,'last_processed_at',v_ts2,
            'job_active',coalesce(r.active,false),'last_run',v_x,'writer',v_q,
            'slow_after_minutes',security.pipeline_num_v1('health.search_refresh_slow_minutes', 40),'stalled_after_minutes',security.pipeline_num_v1('health.search_refresh_stalled_minutes', 90)));
      end if;
      v_det:=v_det||jsonb_build_object('search_refresh',jsonb_build_object('pending',v_n,'oldest_minutes',case when v_n>0 then v_num end,'last_processed_at',v_ts2,'cause',case when v_n>0 then v_txt end));
      v_ok:=array_append(v_ok,'search_refresh');
    exception when others then
      v_ok:=array_append(v_ok,'search_refresh');
      v_found:=v_found||security.platform_health_issue_v1('search_refresh:check_error','warning','search/API','The search refresh check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('search_refresh',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.16 SS-014C (31 Oct 2026): the alert outbox itself: deliveries that failed, and alerts nobody collects while delivery is on
  if security.platform_health_due_v1('alerts',p_force) then
    v_t:=clock_timestamp();
    begin
      select count(*) filter (where a.status='failed' and a.created_at>=now()-interval '24 hours'),  -- fixed: health check observation window
             count(*) filter (where a.status in ('pending','sending')), min(a.created_at) filter (where a.status in ('pending','sending')),
             count(*) filter (where a.status='held' and a.created_at>=now()-interval '24 hours')  -- fixed: health check observation window
        into v_n, v_n2, v_ts, v_n3 from pipeline.platform_alerts a;
      v_bool:=coalesce((security.toolset_setting('pipeline','alerts.delivery_enabled') #>> '{}')::boolean,false);
      if v_n>0 then
        v_found:=v_found||security.platform_health_issue_v1('alerts:delivery_failed','warning','scheduled jobs',
          v_n||' alert(s) could not be delivered in the last 24 hours (every attempt used)',jsonb_build_object('failed_24h',v_n,'resolve','Platform health › Alerts'));
      end if;
      if v_bool and v_n2>0 and v_ts<now()-make_interval(mins=>security.pipeline_num_v1('alerts.collect_within_minutes', 120)::int) then
        v_found:=v_found||security.platform_health_issue_v1('alerts:not_collected','critical','scheduled jobs',
          v_n2||' alert(s) have waited since '||to_char(v_ts at time zone 'Australia/Melbourne','DD Mon HH24:MI')||': the alert destination is not collecting them',
          jsonb_build_object('waiting',v_n2,'since',v_ts,'resolve','Check the alert destination (scheduled task or webhook)'));
      end if;
      v_det:=v_det||jsonb_build_object('alerts',jsonb_build_object('delivery',case when v_bool then 'on' else 'off (recorded only)' end,'waiting',v_n2,'held_24h',v_n3,'failed_24h',v_n,
        'last_sent_at',(select max(a.sent_at) from pipeline.platform_alerts a)));
      v_ok:=array_append(v_ok,'alerts');
    exception when others then
      v_ok:=array_append(v_ok,'alerts');
      v_found:=v_found||security.platform_health_issue_v1('alerts:check_error','warning','scheduled jobs','The alert outbox check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('alerts',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 5. record issues (dedup on check_key), auto-resolve what cleared, store check status
$r$]
 ]::text[][], array[]::text[][], array[]::int[]);

-- 6. C: alert functions
create or replace function security.platform_alerts_add_v1(p_issue_id uuid, p_check_key text, p_kind text, p_severity text, p_title text, p_body text, p_dedupe text)
returns boolean language plpgsql security definer set search_path to '' as $function$
declare v_on boolean := coalesce((security.toolset_setting('pipeline', 'alerts.delivery_enabled') #>> '{}')::boolean, false);
        v_test boolean := coalesce((security.toolset_setting('pipeline', 'alerts.test_mode') #>> '{}')::boolean, false); v_id bigint;
begin
  insert into pipeline.platform_alerts(issue_id, check_key, kind, severity, title, body, status, dedupe_key)
  values (p_issue_id, p_check_key, p_kind, p_severity,
          left(case when v_test or p_kind = 'test' then '[TEST] ' else '' end || p_title, 300), left(p_body, 1500),
          case when v_on then 'pending' else 'held' end, p_dedupe)
  on conflict (dedupe_key) do nothing returning id into v_id;
  return v_id is not null;
end $function$;
revoke all on function security.platform_alerts_add_v1(uuid, text, text, text, text, text, text) from public, anon, authenticated;

create or replace function security.platform_alerts_evaluate_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_min int := security.pipeline_num_v1('alerts.min_severity', 3)::int;
        v_confirm int := security.pipeline_num_v1('alerts.confirm_minutes', 15)::int;
        v_cool int := security.pipeline_num_v1('alerts.cooldown_minutes', 60)::int;
        v_remind int := security.pipeline_num_v1('alerts.reminder_hours', 12)::int;
        v_max int := security.pipeline_num_v1('alerts.max_attempts', 5)::int;
        v_retry numeric := security.pipeline_num_v1('alerts.retry_minutes', 10);
        v_recover boolean := coalesce((security.toolset_setting('pipeline', 'alerts.recovery_notice') #>> '{}')::boolean, true);
        v_on boolean := coalesce((security.toolset_setting('pipeline', 'alerts.delivery_enabled') #>> '{}')::boolean, false);
        v_hook boolean := coalesce((security.toolset_setting('pipeline', 'alerts.webhook_enabled') #>> '{}')::boolean, false);
        i record; v_lkind text; v_lsev text; v_lat timestamptz; v_raised int := 0; v_esc int := 0; v_rem int := 0; v_rec int := 0; v_supp int := 0; v_exp int := 0; v_hook_out jsonb;
        v_word text; v_body text;
begin
  -- 1. a delivery not confirmed before its lease ended goes back for another try, or is marked failed after the last attempt
  update pipeline.platform_alerts a set status = case when a.attempts >= v_max then 'failed' else 'pending' end,
         last_error = coalesce(a.last_error, 'delivery not confirmed before the lease ended'), lease_until = null,
         next_attempt_at = now() + make_interval(mins => (v_retry * power(2, greatest(a.attempts - 1, 0)))::int)
   where a.status = 'sending' and a.lease_until < now() and a.net_request_id is null;
  get diagnostics v_exp = row_count;
  -- 2. open, unacknowledged issues at or above the alert severity that have stayed open long enough
  for i in select p.id, p.check_key, p.severity, p.area, p.title, p.detail, p.first_seen, p.occurrences
             from pipeline.platform_issues p
            where p.resolved_at is null and p.acknowledged_at is null
              and (case p.severity when 'critical' then 3 when 'warning' then 2 else 1 end) >= v_min
              and p.first_seen <= now() - make_interval(mins => v_confirm)
            order by p.first_seen loop
    v_lkind := null; v_lsev := null; v_lat := null;
    select a.kind, a.severity, a.created_at into v_lkind, v_lsev, v_lat from pipeline.platform_alerts a
     where a.issue_id = i.id and a.kind in ('raised', 'escalated', 'reminder') order by a.created_at desc limit 1;
    v_word := case i.severity when 'critical' then 'Critical' when 'warning' then 'Warning' else 'Notice' end;
    v_body := 'Area: ' || i.area || '. First seen ' || to_char(i.first_seen at time zone 'Australia/Melbourne', 'DD Mon HH24:MI') || ' (Melbourne), seen '
              || i.occurrences || ' time(s).' || coalesce(' Next step: ' || (i.detail ->> 'next_step'), '') || coalesce(' Where: ' || (i.detail ->> 'resolve'), '')
              || ' Acknowledge it on PIM Admin › Platform health to stop reminders.';
    if v_lkind is null then
      -- deduplication: the same check alerted within the quiet period (an issue that closed and opened again) is not alerted again
      if exists (select 1 from pipeline.platform_alerts a where a.check_key = i.check_key and a.kind in ('raised', 'escalated', 'reminder')
                  and a.created_at > now() - make_interval(mins => v_cool)) then
        v_supp := v_supp + 1; continue;
      end if;
      if security.platform_alerts_add_v1(i.id, i.check_key, 'raised', i.severity, '[StudySearch] ' || v_word || ': ' || i.title, v_body, i.id::text || ':raised') then v_raised := v_raised + 1; end if;
    elsif v_lsev <> 'critical' and i.severity = 'critical' then
      if security.platform_alerts_add_v1(i.id, i.check_key, 'escalated', i.severity, '[StudySearch] Now critical: ' || i.title, v_body, i.id::text || ':escalated') then v_esc := v_esc + 1; end if;
    elsif v_remind > 0 and v_lat < now() - make_interval(hours => v_remind) then
      if security.platform_alerts_add_v1(i.id, i.check_key, 'reminder', i.severity, '[StudySearch] Still open: ' || i.title, v_body,
                                         i.id::text || ':reminder:' || to_char(now(), 'YYYYMMDDHH24MI')) then v_rem := v_rem + 1; end if;
    end if;
  end loop;
  -- 3. one recovery notice for an alerted issue that has closed
  if v_recover then
    for i in select p.id, p.check_key, p.severity, p.title, p.first_seen, p.resolved_at from pipeline.platform_issues p
              where p.resolved_at is not null and p.resolved_at > now() - interval '1 day'  -- fixed: recovery notices look back one day
                and exists (select 1 from pipeline.platform_alerts a where a.issue_id = p.id and a.kind in ('raised', 'escalated', 'reminder'))
                and not exists (select 1 from pipeline.platform_alerts a where a.issue_id = p.id and a.kind = 'recovered') loop
      if security.platform_alerts_add_v1(i.id, i.check_key, 'recovered', 'info', '[StudySearch] Recovered: ' || i.title,
           'Closed ' || to_char(i.resolved_at at time zone 'Australia/Melbourne', 'DD Mon HH24:MI') || ' (Melbourne), open for '
           || round(extract(epoch from i.resolved_at - i.first_seen) / 60) || ' minutes. No action needed.', i.id::text || ':recovered') then v_rec := v_rec + 1; end if;
    end loop;
  end if;
  -- 4. webhook delivery, only with delivery and the webhook switched on
  if v_on and v_hook then v_hook_out := security.platform_alerts_webhook_v1(); end if;
  return jsonb_build_object('raised', v_raised, 'escalated', v_esc, 'reminders', v_rem, 'recovered', v_rec, 'suppressed', v_supp, 'lease_expired', v_exp,
                            'delivery', case when not v_on then 'off (recorded as held)' when v_hook then 'webhook' else 'scheduled task' end, 'webhook', v_hook_out);
end $function$;
revoke all on function security.platform_alerts_evaluate_v1() from public, anon, authenticated;

create or replace function security.platform_alerts_webhook_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_url text; a record; r record; v_id bigint; v_sent int := 0; v_ok int := 0; v_bad int := 0;
        v_max int := security.pipeline_num_v1('alerts.max_attempts', 5)::int; v_retry numeric := security.pipeline_num_v1('alerts.retry_minutes', 10);
begin
  select s.decrypted_secret into v_url from vault.decrypted_secrets s where s.name = 'studysearch_alert_webhook_url';
  if v_url is null then return jsonb_build_object('webhook', 'no address stored'); end if;
  -- reconcile earlier posts from their pg_net responses
  for a in select x.id, x.attempts, x.net_request_id, x.lease_until from pipeline.platform_alerts x where x.status = 'sending' and x.net_request_id is not null loop
    select h.status_code, h.timed_out, h.error_msg into r from net._http_response h where h.id = a.net_request_id;
    if found and r.status_code between 200 and 299 then
      update pipeline.platform_alerts set status = 'sent', sent_at = now(), lease_until = null where id = a.id; v_ok := v_ok + 1;
    elsif found or a.lease_until < now() then
      update pipeline.platform_alerts set status = case when a.attempts >= v_max then 'failed' else 'pending' end, lease_until = null, net_request_id = null,
             last_error = coalesce('HTTP ' || r.status_code, case when r.timed_out then 'timed out' end, r.error_msg, 'no response'),
             next_attempt_at = now() + make_interval(mins => (v_retry * power(2, greatest(a.attempts - 1, 0)))::int)
       where id = a.id;
      v_bad := v_bad + 1;
    end if;
  end loop;
  for a in select x.* from pipeline.platform_alerts x where x.status = 'pending' and x.next_attempt_at <= now() order by x.created_at
            limit security.pipeline_num_v1('alerts.webhook_batch', 20)::int loop
    v_id := net.http_post(url := v_url,
              body := jsonb_build_object('text', a.title || E'\n' || a.body, 'source', 'StudySearch', 'alert_id', a.id, 'kind', a.kind, 'severity', a.severity,
                                         'check', a.check_key, 'title', a.title, 'body', a.body, 'created_at', a.created_at),
              params := '{}'::jsonb, headers := jsonb_build_object('Content-Type', 'application/json'),
              timeout_milliseconds := 5000);  -- fixed: API time-out
    update pipeline.platform_alerts set status = 'sending', sent_via = 'webhook', net_request_id = v_id, attempts = attempts + 1,
           lease_until = now() + interval '15 minutes'  -- fixed: delivery lease
     where id = a.id;
    v_sent := v_sent + 1;
  end loop;
  return jsonb_build_object('posted', v_sent, 'confirmed', v_ok, 'retrying', v_bad);
end $function$;
revoke all on function security.platform_alerts_webhook_v1() from public, anon, authenticated;

create or replace function security.platform_alerts_take_v1(p_via text default 'scheduled task') returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v jsonb;
begin
  if not coalesce((security.toolset_setting('pipeline', 'alerts.delivery_enabled') #>> '{}')::boolean, false) then
    return jsonb_build_object('count', 0, 'alerts', '[]'::jsonb, 'delivery', 'off: alerts are recorded on Platform health only');
  end if;
  if coalesce((security.toolset_setting('pipeline', 'alerts.webhook_enabled') #>> '{}')::boolean, false) then
    return jsonb_build_object('count', 0, 'alerts', '[]'::jsonb, 'delivery', 'webhook');
  end if;
  with t as (update pipeline.platform_alerts a set status = 'sending', attempts = a.attempts + 1, sent_via = p_via,
                    lease_until = now() + interval '15 minutes'  -- fixed: delivery lease
              where a.status = 'pending' and a.next_attempt_at <= now() returning a.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'kind', t.kind, 'severity', t.severity, 'title', t.title, 'body', t.body, 'raised_at', t.created_at) order by t.created_at), '[]'::jsonb)
    into v from t;
  return jsonb_build_object('count', jsonb_array_length(v), 'alerts', v, 'confirm', 'select security.platform_alerts_confirm_v1(<ids>, true)');
end $function$;
revoke all on function security.platform_alerts_take_v1(text) from public, anon, authenticated;

create or replace function security.platform_alerts_confirm_v1(p_ids bigint[], p_ok boolean default true, p_error text default null) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_n int; v_max int := security.pipeline_num_v1('alerts.max_attempts', 5)::int; v_retry numeric := security.pipeline_num_v1('alerts.retry_minutes', 10);
begin
  if p_ok then
    update pipeline.platform_alerts set status = 'sent', sent_at = now(), lease_until = null where id = any (p_ids) and status = 'sending';
  else
    update pipeline.platform_alerts a set status = case when a.attempts >= v_max then 'failed' else 'pending' end, lease_until = null, last_error = left(coalesce(p_error, 'not delivered'), 300),
           next_attempt_at = now() + make_interval(mins => (v_retry * power(2, greatest(a.attempts - 1, 0)))::int)
     where a.id = any (p_ids) and a.status = 'sending';
  end if;
  get diagnostics v_n = row_count;
  return jsonb_build_object('updated', v_n, 'delivered', p_ok);
end $function$;
revoke all on function security.platform_alerts_confirm_v1(bigint[], boolean, text) from public, anon, authenticated;

-- 7. D: weekly operational scorecard (T1 to T8 and the eight report areas)
create or replace function security.ops_scorecard_v1(p_week_start date default null, p_prior jsonb default null) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '120s' as $function$
declare
  v_tz text := 'Australia/Melbourne';  -- fixed: the platform's reporting time zone
  v_ws_d date := coalesce(p_week_start, date_trunc('week', (now() at time zone 'Australia/Melbourne'))::date);
  v_ws timestamptz; v_we timestamptz; v_end timestamptz; v_complete boolean; v_days numeric;
  t1 jsonb; t2 jsonb; t3 jsonb; t4 jsonb; t5 jsonb; t6 jsonb; t7 jsonb; t8 jsonb; v_thr jsonb; v_idq jsonb; v_inc jsonb;
  v_n bigint; v_n2 bigint; v_n3 bigint; v_num numeric; v_num2 numeric; v_num3 numeric; v_x jsonb; v_ts timestamptz; v_first timestamptz;
  v_txt8 text; v_jobs jsonb; v_cov int; v_elapsed int; v_runs bigint; v_failed bigint; v_worst bigint;
begin
  v_ws := (v_ws_d::timestamp at time zone v_tz);
  v_we := ((v_ws_d + 7)::timestamp at time zone v_tz);
  v_end := least(v_we, now()); v_complete := v_we <= now();
  v_days := greatest(extract(epoch from v_end - v_ws) / 86400.0, 0.0001);

  -- T1: failed runs of active scheduled jobs, by day. The scheduler keeps about three days of run history, so the daily record keeps each
  -- day once it is fully in the log (p_prior: this week's stored scorecard) and a later run only adds or completes days.
  select min(d.start_time) into v_first from cron.job_run_details d;
  with r as (select (d.start_time at time zone v_tz)::date dy, d.status, j.jobname from cron.job_run_details d join cron.job j on j.jobid = d.jobid
              where j.active and d.start_time >= v_ws and d.start_time < v_end)
  select coalesce(jsonb_object_agg(x.dy, jsonb_build_object('runs', x.runs, 'failed', x.failed) order by x.dy), '{}'::jsonb),
         coalesce((select jsonb_agg(jsonb_build_object('job', y.jobname, 'failed', y.n) order by y.n desc) from
                    (select r.jobname, count(*) n from r where r.status = 'failed' group by r.jobname order by count(*) desc limit 5) y), '[]'::jsonb)
    into v_x, v_jobs
    from (select r.dy, count(*) runs, count(*) filter (where r.status = 'failed') failed from r where r.dy > (v_first at time zone v_tz)::date group by r.dy) x;
  v_x := coalesce(p_prior -> 'targets' -> 'T1' -> 'by_day', '{}'::jsonb) || v_x;
  select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb), coalesce(sum((e.value ->> 'runs')::bigint), 0), coalesce(sum((e.value ->> 'failed')::bigint), 0),
         coalesce(max((e.value ->> 'failed')::bigint), 0), count(*)
    into v_x, v_runs, v_failed, v_worst, v_cov
    from jsonb_each(v_x) e where e.key::date >= v_ws_d and e.key::date < v_ws_d + 7;  -- fixed: a week is seven days
  v_elapsed := least(7, ((v_end at time zone v_tz)::date - v_ws_d) + 1);  -- fixed: a week is seven days
  t1 := jsonb_build_object('runs', v_runs, 'failed', v_failed, 'worst_day', v_worst, 'by_day', v_x, 'days_recorded', v_cov, 'failing_jobs_in_log', v_jobs,
        'target', 'At most ' || security.pipeline_num_v1('targets.job_failures_per_day', 0) || ' failed run(s) a day',
        'status', case when v_worst > security.pipeline_num_v1('targets.job_failures_per_day', 0) then 'missed' when v_cov < v_elapsed then 'not fully observed'
                       when not v_complete then 'on track so far' else 'met' end,
        'basis', case when v_cov < v_elapsed then 'incomplete: ' || v_cov || ' of ' || v_elapsed || ' days recorded (the scheduler keeps about three days of run history; the scorecard now records each day)'
                      when v_complete then 'observed for the whole week' else 'observed so far (week in progress)' end);

  -- T2: AI spend from the OpenRouter credit balance (every decrease; a top-up is not spend), and the credit
  with o as (select x.observed_at, x.remaining_usd, lag(x.remaining_usd) over (order by x.observed_at) prev from pipeline.layer3_openrouter_observations x
              where x.kind = 'credits' and x.remaining_usd is not null and x.observed_at >= v_ws - interval '1 hour' and x.observed_at < v_end),  -- fixed: one observation before the week for the first difference
       dd as (select (o.observed_at at time zone v_tz)::date dy, sum(greatest(coalesce(o.prev, o.remaining_usd) - o.remaining_usd, 0)) spend, count(*) obs from o where o.observed_at >= v_ws group by 1)
  select jsonb_build_object('spend_usd', round(coalesce(sum(spend), 0), 2), 'worst_day_usd', round(coalesce(max(spend), 0), 2),
           'spend_by_day', coalesce(jsonb_object_agg(dy, round(spend, 2) order by dy), '{}'::jsonb), 'observations', coalesce(sum(obs), 0),
           'expected_observations', round(v_days * 96))  -- fixed: the openrouter-balance job records every 15 minutes
    into t2 from dd;
  select o.remaining_usd into v_num from pipeline.layer3_openrouter_observations o where o.kind = 'credits' and o.remaining_usd is not null and o.observed_at < v_end order by o.observed_at desc limit 1;
  t2 := t2 || jsonb_build_object('credit_usd', v_num, 'ceiling_usd', security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14), 'credit_floor_usd', security.pipeline_num_v1('targets.ai_credit_min_usd', 10),
        'target', 'At most US$' || security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14) || ' a day; credit US$' || security.pipeline_num_v1('targets.ai_credit_min_usd', 10) || ' or more',
        'status', case when (t2->>'worst_day_usd')::numeric > security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14) or coalesce(v_num, 0) < security.pipeline_num_v1('targets.ai_credit_min_usd', 10) then 'missed'
                       when not v_complete then 'on track so far' else 'met' end,
        'basis', case when (t2->>'observations')::numeric < 0.8 * (t2->>'expected_observations')::numeric then 'incomplete: ' || (t2->>'observations') || ' of about ' || (t2->>'expected_observations') || ' balance readings'
                      when v_complete then 'observed for the whole week' else 'observed so far (week in progress)' end);  -- fixed: 80% of readings counts as complete

  -- T3: Firecrawl
  select coalesce(sum(u.units), 0) into v_num from pipeline.coverage_vendor_usage u where u.at >= v_ws and u.at < v_end;
  select security.layer2_provider_budget_status(p.id, 0) into v_x from pipeline.layer2_acquisition_providers p where p.provider_key = 'firecrawl';
  t3 := jsonb_build_object('credits_week', v_num, 'month_used', v_x->'used_units', 'month_limit', v_x->'limit_units', 'reserve', v_x->'stop_at_remaining_units',
        'target', 'Within the monthly limit, keeping the reserve',
        'status', case when v_x is null then 'not measurable' when coalesce((v_x->>'used_units')::numeric, 0) > coalesce((v_x->>'limit_units')::numeric, 0) - coalesce((v_x->>'stop_at_remaining_units')::numeric, 0) then 'missed' else 'met' end,
        'basis', 'week credits observed; month position measured at report time');

  -- T4: futile enrichment items (the course page found is for another course)
  with f as (select (i.created_at at time zone v_tz)::date dy, count(*) n from pipeline.field_enrich_items i
              where i.created_at >= v_ws and i.created_at < v_end and i.state = 'skipped' and i.reason like 'no correct course page%' group by 1)
  select jsonb_build_object('items', coalesce(sum(n), 0), 'worst_day', coalesce(max(n), 0), 'by_day', coalesce(jsonb_object_agg(dy, n order by dy), '{}'::jsonb)) into t4 from f;
  t4 := t4 || jsonb_build_object('target', 'Under ' || security.pipeline_num_v1('targets.futile_items_per_day', 100) || ' a day',
        'status', case when (t4->>'worst_day')::int >= security.pipeline_num_v1('targets.futile_items_per_day', 100) then 'missed' when not v_complete then 'on track so far' else 'met' end,
        'basis', case when v_complete then 'observed for the whole week' else 'observed so far (week in progress)' end);

  -- T5: Layer 4 review backlog (only the current position is stored)
  select count(*) filter (where r.status = 'pending'), min(r.created_at) filter (where r.status = 'pending'),
         count(*) filter (where r.created_at >= v_ws and r.created_at < v_end), count(*) filter (where r.decided_at >= v_ws and r.decided_at < v_end)
    into v_n, v_ts, v_n2, v_n3 from pipeline.layer4_review_items r;
  v_num := round(extract(epoch from now() - v_ts) / 86400.0, 1);
  t5 := jsonb_build_object('pending_now', v_n, 'oldest_pending_days', v_num, 'oldest_pending_since', v_ts, 'created_week', v_n2, 'decided_week', v_n3,
        'target', 'Oldest pending item under ' || security.pipeline_num_v1('targets.review_oldest_days', 14) || ' days',
        'status', case when v_n = 0 or v_num < security.pipeline_num_v1('targets.review_oldest_days', 14) then 'met' else 'missed' end,
        'basis', 'measured at report time (the backlog age is not stored by day)');

  -- T6: consumer API (website and Zoho requests, contract drift)
  select count(*), count(*) filter (where a.status >= 500), count(*) filter (where a.action = 'search' and coalesce(a.items, 0) <= security.pipeline_num_v1('targets.api_search_page_size', 20)),
         percentile_cont(0.5) within group (order by a.elapsed_ms) filter (where a.action = 'search' and coalesce(a.items, 0) <= security.pipeline_num_v1('targets.api_search_page_size', 20)),
         percentile_cont(0.95) within group (order by a.elapsed_ms) filter (where a.action = 'search' and coalesce(a.items, 0) <= security.pipeline_num_v1('targets.api_search_page_size', 20)),
         percentile_cont(0.95) within group (order by a.elapsed_ms) filter (where a.action = 'search')
    into v_n, v_n2, v_n3, v_num, v_num2, v_num3 from pipeline.api_requests a where a.at >= v_ws and a.at < v_end;
  v_x := security.consumer_api_check_v1();
  t6 := jsonb_build_object('requests', v_n, 'server_errors', v_n2, 'search_requests_measured', v_n3, 'search_p50_ms', round(v_num), 'search_p95_ms', round(v_num2), 'search_p95_ms_all_sizes', round(v_num3),
        'by_platform', coalesce((select jsonb_object_agg(x.platform, x.n) from (select a.platform, count(*) n from pipeline.api_requests a where a.at >= v_ws and a.at < v_end group by 1) x), '{}'::jsonb),
        'contract_drift_now', jsonb_array_length(coalesce(v_x->'drift', '[]'::jsonb)),
        'guard_runs_failed', (select count(*) from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname = 'consumer-api-guard' and d.start_time >= v_ws and d.start_time < v_end and d.status = 'failed'),
        'target', '0 server errors; no contract drift; search p95 under ' || security.pipeline_num_v1('targets.api_search_p95_ms', 3000) || ' ms for pages of ' || security.pipeline_num_v1('targets.api_search_page_size', 20),
        'status', case when v_n2 > 0 or jsonb_array_length(coalesce(v_x->'drift', '[]'::jsonb)) > 0 then 'missed'
                       when v_n3 = 0 then 'no search traffic: latency not measurable'
                       when v_num2 > security.pipeline_num_v1('targets.api_search_p95_ms', 3000) then 'missed' when not v_complete then 'on track so far' else 'met' end,
        'basis', case when v_n3 = 0 then 'errors and drift observed; no measured search requests in the window' when v_complete then 'observed for the whole week' else 'observed so far (week in progress)' end);

  -- T7: data freshness (search refresh requests; reference bundle)
  select count(*), count(*) filter (where q.processed_at is null), percentile_cont(0.5) within group (order by extract(epoch from coalesce(q.processed_at, now()) - q.requested_at) / 60),
         percentile_cont(0.95) within group (order by extract(epoch from coalesce(q.processed_at, now()) - q.requested_at) / 60), max(extract(epoch from coalesce(q.processed_at, now()) - q.requested_at) / 60),
         count(*) filter (where extract(epoch from coalesce(q.processed_at, now()) - q.requested_at) / 60 > security.pipeline_num_v1('health.search_refresh_slow_minutes', 40))
    into v_n, v_n2, v_num, v_num2, v_num3, v_n3 from search.refresh_requests q where q.requested_at >= v_ws and q.requested_at < v_end;
  select max(b.built_at) into v_ts from pipeline.consumer_reference_bundle_cache b;
  t7 := jsonb_build_object('refresh_requests', v_n, 'open', v_n2, 'wait_p50_min', round(v_num, 1), 'wait_p95_min', round(v_num2, 1), 'wait_max_min', round(v_num3, 1), 'over_target', v_n3,
        'bundle_age_hours_now', round(extract(epoch from now() - v_ts) / 3600.0, 2),
        'bundle_stale_issues', (select count(*) from pipeline.platform_issues p where p.check_key = 'reference_bundle:stale' and p.first_seen >= v_ws and p.first_seen < v_end),
        'target', 'Refresh requests processed within ' || security.pipeline_num_v1('health.search_refresh_slow_minutes', 40) || ' minutes; reference bundle under ' || security.pipeline_num_v1('targets.reference_bundle_hours', 2) || ' hours old',
        'status', case when v_n3 > 0 or (select count(*) from pipeline.platform_issues p where p.check_key = 'reference_bundle:stale' and p.first_seen >= v_ws and p.first_seen < v_end) > 0
                         or extract(epoch from now() - v_ts) / 3600.0 > security.pipeline_num_v1('targets.reference_bundle_hours', 2) then 'missed'
                       when not v_complete then 'on track so far' else 'met' end,
        'basis', case when v_complete then 'observed for the whole week' else 'observed so far (week in progress)' end);

  -- T8: releases (the database holds the migrations and contract re-baselines; suite and workflow results are on the release record)
  select count(*), max(m.version || ' ' || m.name) into v_n, v_txt8 from supabase_migrations.schema_migrations m
   where m.version >= to_char(v_ws at time zone v_tz, 'YYYYMMDD') and m.version < to_char(v_we at time zone v_tz, 'YYYYMMDD');
  t8 := jsonb_build_object('migrations_dated_in_week', v_n, 'latest_migration', v_txt8,
        'target', 'Full suite and post-merge workflows green; live checksums verified; rollback on record',
        'status', 'see the release record', 'basis', 'migrations dated in the week; suite, workflow and checksum results are recorded in the Admin release record, not in the database');

  -- report areas without a target: throughput, page identity and evidence, incidents and recovery
  v_thr := jsonb_build_object(
    'enrich_values_filled', (select count(*) from pipeline.field_enrich_items i where i.state = 'filled' and i.updated_at >= v_ws and i.updated_at < v_end),
    'enrich_values_to_review', (select count(*) from pipeline.field_enrich_items i where i.state = 'review' and i.updated_at >= v_ws and i.updated_at < v_end),
    'layer4_decided', t5->'decided_week', 'search_refreshes_processed', (select count(*) from search.refresh_requests q where q.processed_at >= v_ws and q.processed_at < v_end),
    'enrich_ai_cost_usd', (select round(coalesce(sum(i.cost_usd), 0), 2) from pipeline.field_enrich_items i where i.updated_at >= v_ws and i.updated_at < v_end));
  v_idq := jsonb_build_object(
    'course_pages_now', coalesce((select jsonb_object_agg(x.status, x.n) from (select p.status, count(*) n from pipeline.coverage_course_pages p group by 1) x), '{}'::jsonb),
    'remediation_holds_open', (select count(*) from pipeline.course_remediation_holds h where h.lifted_at is null),
    'futile_items_week', t4->'items');
  v_inc := jsonb_build_object(
    'critical_opened', (select count(*) from pipeline.platform_issues p where p.severity = 'critical' and p.first_seen >= v_ws and p.first_seen < v_end),
    'warning_opened', (select count(*) from pipeline.platform_issues p where p.severity = 'warning' and p.first_seen >= v_ws and p.first_seen < v_end),
    'critical_by_check', coalesce((select jsonb_object_agg(x.k, x.n) from (select split_part(p.check_key, ':', 1) || ':' || split_part(p.check_key, ':', 2) k, count(*) n from pipeline.platform_issues p
                                    where p.severity = 'critical' and p.first_seen >= v_ws and p.first_seen < v_end group by 1 order by 2 desc limit 8) x), '{}'::jsonb),
    'critical_minutes_to_close_median', (select round(percentile_cont(0.5) within group (order by extract(epoch from p.resolved_at - p.first_seen) / 60)) from pipeline.platform_issues p
                                          where p.severity = 'critical' and p.first_seen >= v_ws and p.first_seen < v_end and p.resolved_at is not null),
    'critical_open_now', (select count(*) from pipeline.platform_issues p where p.severity = 'critical' and p.resolved_at is null),
    'unacknowledged_open_now', (select count(*) from pipeline.platform_issues p where p.severity in ('critical', 'warning') and p.resolved_at is null and p.acknowledged_at is null),
    'alerts', coalesce((select jsonb_object_agg(x.k, x.n) from (select a.kind || ':' || a.status k, count(*) n from pipeline.platform_alerts a where a.created_at >= v_ws and a.created_at < v_end group by 1) x), '{}'::jsonb),
    'health_run_ms_median', (select round(percentile_cont(0.5) within group (order by h.duration_ms)) from pipeline.platform_health_runs h where h.started_at >= v_ws and h.started_at < v_end));

  return jsonb_build_object('week_start', v_ws_d, 'week_end', v_ws_d + 6, 'complete', v_complete, 'generated_at', now(),
    'targets', jsonb_build_object('T1', t1, 'T2', t2, 'T3', t3, 'T4', t4, 'T5', t5, 'T6', t6, 'T7', t7, 'T8', t8),
    'met', (select count(*) from jsonb_each(jsonb_build_object('T1', t1, 'T2', t2, 'T3', t3, 'T4', t4, 'T5', t5, 'T6', t6, 'T7', t7)) e where e.value->>'status' = 'met'),
    'missed', (select count(*) from jsonb_each(jsonb_build_object('T1', t1, 'T2', t2, 'T3', t3, 'T4', t4, 'T5', t5, 'T6', t6, 'T7', t7)) e where e.value->>'status' = 'missed'),
    'areas', jsonb_build_object('1_job_reliability', 'T1', '2_throughput', v_thr, '3_page_identity_and_evidence', v_idq, '4_review_backlog', 'T5',
                                '5_api_performance', 'T6', '6_ai_and_firecrawl', 'T2, T3', '7_freshness', 'T7', '8_incidents_and_recovery', v_inc));
end $function$;
revoke all on function security.ops_scorecard_v1(date, jsonb) from public, anon, authenticated;

create or replace function security.ops_scorecard_record_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_cur date := date_trunc('week', (now() at time zone 'Australia/Melbourne'))::date; v jsonb; v_old jsonb; v_out jsonb := '[]'::jsonb; w date;
begin
  -- the current week every day (so each day's job runs are kept while the scheduler still has them), and the last week once more after it ends
  foreach w in array array[v_cur - 7, v_cur] loop  -- fixed: Monday-to-Sunday weeks
    v_old := null;
    select s.scorecard into v_old from pipeline.ops_scorecards s where s.week_start = w;
    continue when w < v_cur and coalesce((v_old ->> 'complete')::boolean, false);  -- a finished week is recorded once after it ends, then kept
    v := security.ops_scorecard_v1(w, v_old);
    insert into pipeline.ops_scorecards(week_start, week_end, generated_at, generated_by, scorecard)
    values (w, w + 6, now(), 'job ops-scorecard', v)
    on conflict (week_start) do update set generated_at = excluded.generated_at, generated_by = excluded.generated_by, scorecard = excluded.scorecard;
    v_out := v_out || jsonb_build_object('week_start', w, 'complete', v -> 'complete', 'met', v -> 'met', 'missed', v -> 'missed');
  end loop;
  return v_out;
end $function$;
revoke all on function security.ops_scorecard_record_v1() from public, anon, authenticated;

-- 8. screen: alerts, acknowledgement, test alert, scorecard (Platform health)
create or replace function public.admin_platform_alerts(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_id uuid; v_n int;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_action = 'read' then
    return jsonb_build_object(
      'can_change', coalesce(v_rank, 0) >= 6,
      'settings', jsonb_build_object(
        'delivery_enabled', coalesce((security.toolset_setting('pipeline', 'alerts.delivery_enabled') #>> '{}')::boolean, false),
        'webhook_enabled', coalesce((security.toolset_setting('pipeline', 'alerts.webhook_enabled') #>> '{}')::boolean, false),
        'webhook_address_stored', exists (select 1 from vault.secrets s where s.name = 'studysearch_alert_webhook_url'),
        'test_mode', coalesce((security.toolset_setting('pipeline', 'alerts.test_mode') #>> '{}')::boolean, false),
        'min_severity', security.pipeline_num_v1('alerts.min_severity', 3), 'confirm_minutes', security.pipeline_num_v1('alerts.confirm_minutes', 15),
        'cooldown_minutes', security.pipeline_num_v1('alerts.cooldown_minutes', 60), 'reminder_hours', security.pipeline_num_v1('alerts.reminder_hours', 12)),
      'counts', coalesce((select jsonb_object_agg(x.status, x.n) from (select a.status, count(*) n from pipeline.platform_alerts a where a.created_at > now() - interval '7 days' group by 1) x), '{}'::jsonb),
      'recent', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select a.id, a.kind, a.severity, a.title, a.status, a.created_at, a.sent_at, a.attempts, a.last_error
                                                                                           from pipeline.platform_alerts a order by a.created_at desc limit 12) x), '[]'::jsonb),
      'scorecards', coalesce((select jsonb_agg(s.scorecard order by s.week_start desc) from (select x.week_start, x.scorecard from pipeline.ops_scorecards x order by x.week_start desc limit 2) s), '[]'::jsonb));
  elsif p_action = 'scorecard' then
    return security.ops_scorecard_v1(coalesce(nullif(p_args->>'week_start', '')::date, date_trunc('week', (now() at time zone 'Australia/Melbourne'))::date),
             (select s.scorecard from pipeline.ops_scorecards s where s.week_start = coalesce(nullif(p_args->>'week_start', '')::date, date_trunc('week', (now() at time zone 'Australia/Melbourne'))::date)));
  end if;
  if coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'acknowledge' then
    update pipeline.platform_issues set acknowledged_at = now(), acknowledged_by = auth.uid(), acknowledged_note = left(v_reason, 300)
     where id = (p_args->>'id')::uuid and resolved_at is null returning id into v_id;
    if v_id is null then raise exception 'this issue is closed or does not exist'; end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('platform health', 'acknowledge', v_id::text, jsonb_build_object('reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'id', v_id);
  elsif p_action = 'test' then
    perform security.platform_alerts_add_v1(null, 'alerts:test', 'test', 'info', '[StudySearch] Test alert',
      'A test alert from Platform health: ' || v_reason || '. If it reached you, the alert destination works.', 'test:' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'));
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('platform health', 'alert_test', 'alerts', jsonb_build_object('reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action';
end $function$;
revoke all on function public.admin_platform_alerts(text, jsonb) from public, anon;
grant execute on function public.admin_platform_alerts(text, jsonb) to authenticated;
comment on function public.admin_platform_alerts(text, jsonb) is 'StudySearch SS-014C/D (31 Oct 2026): Platform health › Alerts and weekly scorecard. read and scorecard rank 4+; acknowledge an issue and send a test alert: Platform Admin (rank 6) with a reason, logged in admin_control_events. Admin only; never part of the consumer API.';

-- 9. jobs (G1): catalogued first, then scheduled
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('platform-alerts', 'Platform upkeep', 41, 'Platform alerts',
  'Every 10 minutes, two minutes after the health check: turns open critical issues into alerts (deduplicated, escalated, reminded, one recovery notice) under Pipeline settings › Alerts, retries undelivered alerts and fails them visibly. External delivery is off until the Platform Admin approves a destination (decision D7): alerts are then recorded on Platform health only. Admits, reads, queues and spends nothing.',
  6, false, null),
 ('ops-scorecard', 'Reports', 63, 'Weekly operational scorecard',
  'Every morning (Melbourne): records the week so far against targets T1 to T8 (Pipeline settings › Operating targets) from existing measurements, keeping each day of job runs before the scheduler forgets it (about three days), and finalises the last week once after it ends. Shown on Platform health. Read only: it admits, reads, queues and spends nothing.',
  6, false, null)
on conflict (jobname) do nothing;
select cron.schedule('platform-alerts', '10-59/10 * * * *', $$select security.platform_alerts_evaluate_v1()$$);
select cron.schedule('ops-scorecard', '29 19 * * *', $$select security.ops_scorecard_record_v1()$$);

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'platform-alerts', 'Platform', 'Platform upkeep', 'SS-014C: platform health alerts (delivery off until D7 destination approval)', 'active', '{}', '20261031091000'),
 ('job', 'ops-scorecard', 'Platform', 'Reports', 'SS-014D: daily record of the weekly operational scorecard T1 to T8', 'active', '{}', '20261031091000'),
 ('table', 'pipeline.platform_alerts', 'Platform', 'Platform upkeep', 'SS-014C: alert outbox for platform health issues', 'active', '{}', '20261031091000'),
 ('table', 'pipeline.ops_scorecards', 'Platform', 'Reports', 'SS-014D: one weekly scorecard per week', 'active', '{}', '20261031091000'),
 ('function', 'security.platform_alerts_add_v1', 'Platform', 'Platform upkeep', 'SS-014C: records one alert (held or pending, test prefix)', 'active', '{}', '20261031091000'),
 ('function', 'security.platform_alerts_evaluate_v1', 'Platform', 'Platform upkeep', 'SS-014C: job platform-alerts', 'active', '{}', '20261031091000'),
 ('function', 'security.platform_alerts_webhook_v1', 'Platform', 'Platform upkeep', 'SS-014C: webhook delivery and reconciliation (off)', 'active', '{}', '20261031091000'),
 ('function', 'security.platform_alerts_take_v1', 'Platform', 'Platform upkeep', 'SS-014C: scheduled-task delivery: take pending alerts', 'active', '{}', '20261031091000'),
 ('function', 'security.platform_alerts_confirm_v1', 'Platform', 'Platform upkeep', 'SS-014C: scheduled-task delivery: confirm or retry', 'active', '{}', '20261031091000'),
 ('function', 'security.ops_scorecard_v1', 'Platform', 'Reports', 'SS-014D: computes the weekly scorecard', 'active', '{}', '20261031091000'),
 ('function', 'security.ops_scorecard_record_v1', 'Platform', 'Reports', 'SS-014D: job ops-scorecard', 'active', '{}', '20261031091000'),
 ('function', 'public.admin_platform_alerts', 'Platform', 'Platform upkeep', 'SS-014C/D: Platform health alerts, acknowledgement, test alert, scorecard', 'active', '{}', '20261031091000')
on conflict do nothing;

-- 10. first scorecards: the last full week (a baseline before the targets were set) and this week so far, then post-check
select security.ops_scorecard_record_v1();
do $$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and (key like 'alerts.%' or key like 'targets.%' or key like 'health.search_refresh_%')) <> 21 then
    raise exception 'SS-014 post-check: settings are not all present'; end if;
  if coalesce((security.toolset_setting('pipeline', 'alerts.delivery_enabled') #>> '{}')::boolean, true) then
    raise exception 'SS-014 post-check: external alert delivery must be off (D7)'; end if;
  if (select count(*) from cron.job j join pipeline.automation_catalogue a on a.jobname = j.jobname where j.jobname in ('platform-alerts', 'ops-scorecard') and j.active) <> 2 then
    raise exception 'SS-014 post-check: the two jobs are not scheduled and catalogued'; end if;
  if (select count(*) from pipeline.ops_scorecards) < 2 then raise exception 'SS-014 post-check: no scorecard recorded'; end if;
  if (select prosrc from pg_proc where oid = 'security.platform_health_check_v1(boolean)'::regprocedure) not like '%hp as materialized%'
     or (select prosrc from pg_proc where oid = 'security.platform_health_check_v1(boolean)'::regprocedure) not like '%search_refresh:waiting%' then
    raise exception 'SS-014 post-check: the health check edits are missing'; end if;
  if has_function_privilege('anon', 'public.admin_platform_alerts(text, jsonb)', 'execute') or not has_function_privilege('authenticated', 'public.admin_platform_alerts(text, jsonb)', 'execute') then
    raise exception 'SS-014 post-check: grants on admin_platform_alerts'; end if;
end $$;
