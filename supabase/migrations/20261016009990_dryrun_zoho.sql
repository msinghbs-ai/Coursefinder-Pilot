-- CF-247 (22 Oct 2026). Platform Admin 19:42: "I wanted the platform to self maintain work job or queue until it completes the data
-- enrichment or notify when it runs out of toolset or get stuck." Choices at 19:53 (all the recommended option):
--   Alerts "Health page + phone/email": push or email only for Stuck and Out of toolset; Done and Nothing left to try in the daily report.
--   Build order "Watchdog, rules, workspace, clean-up": this is step 1, the progress watchdog.
--   Self-fix "Safe fixes only, logged": items that gave up on a passing error get one more try; anything that changes course data or
--   spends extra credits stays with a person (Layer 4).
-- 1 pipeline.queue_watch: the enrichment queues watched, each with how to count work waiting, work finished, failures and items with
--   nothing left to try, the jobs and tools it uses, and an optional one-more-try fix for items that gave up on a passing error.
-- 2 security.queue_watch_run_v1 (job queue-watch, every 15 minutes) gives each queue one state:
--     Moving, Waiting for today's budget, Stuck, Failing, Out of toolset, Nothing left to try, Done, Paused (switched off by a person).
--   A change of state is kept (pipeline.queue_watch_events). Stuck, Failing and Out of toolset open an issue on Platform health
--   (check_key queue_watch:<queue>) that closes by itself when the queue moves again.
--   Stuck and Out of toolset go to the alert outbox for phone and email; Done and Nothing left to try go to the daily report.
-- 3 Safe fixes (pipeline.queue_watch_fixes, pipeline.queue_watch_retries): only queue bookkeeping, never course data; at most
--   queue_watch.retry_batch items a queue a run, each item once per queue_watch.retry_days, and never while one of the queue's tools is
--   out or waiting for budget.
-- 4 security.queue_watch_alerts_take_v1 hands unsent alerts to the delivery (a scheduled task sends them as push and email);
--   security.queue_watch_report_v1 is the daily report. public.admin_queue_watch: list, report (Curator and above), run now (Pipeline
--   Operator and above, with a reason).
-- Replaces: nothing (the coverage and scholarship queue stall checks on Platform health stay; the watchdog adds per-queue progress,
--   tool state, alerts and safe fixes across the enrichment queues)
-- Retires: nothing

-- settings ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'queue_watch.window_minutes', 'Watchdog: progress window', 'Work finished and failures are counted over this many minutes to work out how fast each queue moves and whether it is failing.', 'number', to_jsonb(60), 15, 1440, 'minutes', 760, 'CF-247 22 Oct 2026 (progress watchdog)', 'Platform upkeep', 'security.queue_watch_run_v1'),
 ('pipeline', 'queue_watch.stuck_minutes', 'Watchdog: stuck after', 'A queue with work waiting and nothing finished for this many minutes is Stuck (or Out of toolset, or Waiting for budget, when that is why).', 'number', to_jsonb(120), 30, 2880, 'minutes', 761, 'CF-247 22 Oct 2026 (progress watchdog)', 'Platform upkeep', 'security.queue_watch_run_v1'),
 ('pipeline', 'queue_watch.fail_percent', 'Watchdog: failing at', 'A queue is Failing when at least this share of what it tried in the progress window failed.', 'number', to_jsonb(50), 10, 100, '%', 762, 'CF-247 22 Oct 2026 (progress watchdog)', 'Platform upkeep', 'security.queue_watch_run_v1'),
 ('pipeline', 'queue_watch.fail_min', 'Watchdog: failures before Failing', 'A queue needs at least this many failures in the progress window before it can be called Failing.', 'number', to_jsonb(5), 1, 1000, 'failures', 763, 'CF-247 22 Oct 2026 (progress watchdog)', 'Platform upkeep', 'security.queue_watch_run_v1'),
 ('pipeline', 'queue_watch.alert_repeat_hours', 'Watchdog: alert again after', 'A queue that stays Stuck or Out of toolset is alerted again after this many hours.', 'number', to_jsonb(12), 1, 168, 'hours', 764, 'CF-247 22 Oct 2026 (progress watchdog)', 'Platform upkeep', 'security.queue_watch_run_v1'),
 ('pipeline', 'queue_watch.retry_batch', 'Watchdog: one more try, per queue per run', 'At most this many items that gave up on a passing error (time-out, server busy) get one more try in each queue at each watchdog run.', 'number', to_jsonb(25), 0, 500, 'items', 765, 'CF-247 22 Oct 2026 (progress watchdog)', 'Platform upkeep', 'security.queue_watch_run_v1'),
 ('pipeline', 'queue_watch.retry_days', 'Watchdog: one more try, at most every', 'An item gets the watchdog''s one more try at most once in this many days.', 'number', to_jsonb(7), 1, 90, 'days', 766, 'CF-247 22 Oct 2026 (progress watchdog)', 'Platform upkeep', 'security.queue_watch_run_v1'),
 ('pipeline', 'queue_watch.retry_after_hours', 'Watchdog: one more try after', 'An item that gave up is only tried again once its last failure is at least this many hours old.', 'number', to_jsonb(6), 1, 168, 'hours', 767, 'CF-247 22 Oct 2026 (progress watchdog)', 'Platform upkeep', 'security.queue_watch_run_v1'),
 ('pipeline', 'queue_watch.report_hours', 'Watchdog: daily report covers', 'The watchdog''s daily report covers this many hours.', 'number', to_jsonb(24), 1, 168, 'hours', 768, 'CF-247 22 Oct 2026 (progress watchdog)', 'Platform upkeep', 'security.queue_watch_report_v1')
on conflict do nothing;

-- 1 tables ---------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.queue_watch (
  key text primary key,
  label text not null,
  area text not null,
  purpose text not null,
  jobnames text[] not null default '{}',
  tools text[] not null default '{}',
  pending_sql text not null,
  progress_sql text not null,
  done_sql text not null,
  failed_sql text not null default 'select 0::bigint',
  exhausted_sql text not null default 'select 0::bigint',
  exhausted_label text,
  retry_sql text,
  retry_label text,
  fix_at text,
  sort int not null default 100,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);
comment on table pipeline.queue_watch is 'CF-247 22 Oct 2026 (progress watchdog): the enrichment queues the watchdog watches. pending_sql counts work a tool can take now, progress_sql gives the time the last item finished, done_sql and failed_sql count since $1, exhausted_sql counts items with nothing left to try, retry_sql gives items that gave up on a passing error one more try ($1 limit, $2 not retried since, $3 failed before). Written by migrations only.';

create table if not exists pipeline.queue_watch_state (
  key text primary key references pipeline.queue_watch(key),
  state text not null,
  since timestamptz not null default now(),
  reason text,
  pending bigint, done_window bigint, failed_window bigint, exhausted bigint,
  last_progress timestamptz, per_hour numeric, eta_hours numeric,
  tools_out text[] not null default '{}', tools_waiting text[] not null default '{}',
  jobs_paused text[] not null default '{}',
  check_ms int, checked_at timestamptz not null default now(), error text
);
comment on table pipeline.queue_watch_state is 'CF-247 22 Oct 2026 (progress watchdog): the latest state of each watched queue (moving, waiting, stuck, failing, out_of_toolset, nothing_left, done, paused) with the figures behind it.';

create table if not exists pipeline.queue_watch_events (
  id bigserial primary key,
  key text not null references pipeline.queue_watch(key),
  at timestamptz not null default now(),
  from_state text, to_state text not null, reason text,
  detail jsonb not null default '{}'::jsonb
);
create index if not exists queue_watch_events_at_idx on pipeline.queue_watch_events(at desc);
comment on table pipeline.queue_watch_events is 'CF-247 22 Oct 2026 (progress watchdog): every change of a watched queue''s state, for the history on Platform health and the daily report.';

create table if not exists pipeline.queue_watch_alerts (
  id bigserial primary key,
  key text not null references pipeline.queue_watch(key),
  state text not null,
  channel text not null check (channel in ('notify', 'report')),
  title text not null, body text not null,
  raised_at timestamptz not null default now(),
  sent_at timestamptz, sent_via text
);
create index if not exists queue_watch_alerts_unsent_idx on pipeline.queue_watch_alerts(channel, raised_at) where sent_at is null;
comment on table pipeline.queue_watch_alerts is 'CF-247 22 Oct 2026 (progress watchdog): alert outbox. channel notify (Stuck, Out of toolset) is sent as push and email; channel report (Done, Nothing left to try) goes in the daily report. sent_at is set when handed to the delivery.';

create table if not exists pipeline.queue_watch_fixes (
  id bigserial primary key,
  key text not null references pipeline.queue_watch(key),
  at timestamptz not null default now(),
  fix text not null, items int not null,
  detail jsonb not null default '{}'::jsonb
);
create index if not exists queue_watch_fixes_at_idx on pipeline.queue_watch_fixes(at desc);
comment on table pipeline.queue_watch_fixes is 'CF-247 22 Oct 2026 (progress watchdog): log of the safe fixes the watchdog made by itself (one more try for items that gave up on a passing error).';

create table if not exists pipeline.queue_watch_retries (
  queue_key text not null references pipeline.queue_watch(key),
  item_key text not null,
  retried_at timestamptz not null default now(),
  times int not null default 1,
  primary key (queue_key, item_key)
);
comment on table pipeline.queue_watch_retries is 'CF-247 22 Oct 2026 (progress watchdog): items the watchdog gave one more try, so each gets it at most once per queue_watch.retry_days.';

-- 1b the queues ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.queue_watch(key, label, area, purpose, jobnames, tools, pending_sql, progress_sql, done_sql, failed_sql, exhausted_sql, exhausted_label, retry_sql, retry_label, fix_at, sort) values
('course_page_search', 'Find course pages (search)', 'Course pages', 'Searches the web for the official page of each course without one, by CRICOS code and then by title.',
 '{course-link-search,course-link-search-worker}', '{firecrawl:course_search}',
 $q$select count(*) from pipeline.course_link_search q where q.state = 'queued' and not exists (select 1 from pipeline.enrichment_flags f where f.entity = 'course' and f.entity_key = q.course_id::text and f.kind = 'hard' and f.state = 'raised')$q$,
 $q$select max(done_at) from pipeline.course_link_search$q$,
 $q$select count(*) from pipeline.course_link_search where done_at >= $1$q$,
 'select 0::bigint',
 $q$select count(*) from pipeline.enrichment_flags f where f.entity = 'course' and f.state = 'raised' and f.cleared_at is null and f.reason_code in ('page_not_found', 'not_on_provider_site')$q$,
 'Courses whose page was not found by any search', null, null, '#layer-2-discovery?tab=operations', 10),
('course_page_discover', 'Discover course pages (site maps)', 'Course pages', 'Maps each provider''s website for course pages.',
 '{coverage-discover,coverage-discover-2}', '{firecrawl:other}',
 $q$select count(*) from pipeline.coverage_provider_discovery d where (d.status = 'pending' or (d.status in ('mapped', 'failed') and d.next_due_at <= now())) and d.attempts < 3 and security.enrich_focus_v1(d.provider_id) and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id)$q$,
 $q$select max(coalesce(mapped_at, updated_at)) from pipeline.coverage_provider_discovery where status <> 'pending'$q$,
 $q$select count(*) from pipeline.coverage_provider_discovery where mapped_at >= $1$q$,
 $q$select count(*) from pipeline.coverage_provider_discovery where status = 'failed' and updated_at >= $1$q$,
 $q$select count(*) from pipeline.enrichment_flags f where f.entity = 'provider' and f.state = 'raised' and f.cleared_at is null and f.reason_code in ('course_pages_not_found', 'course_pages_not_listed', 'site_unreachable')$q$,
 'Providers whose site gave no course pages or could not be reached', null, null, '#layer-2-discovery?tab=operations', 20),
('course_page_read', 'Read course pages', 'Course pages', 'Reads each matched course page and keeps the evidence.',
 '{coverage-read}', '{firecrawl:reads}',
 $q$select count(*) from pipeline.coverage_course_pages p where p.status in ('bound', 'ambiguous') and coalesce(p.next_read_at, now()) <= now() and p.read_attempts < 3$q$,
 $q$select max(read_at) from pipeline.coverage_course_pages where read_status = 'read'$q$,
 $q$select count(*) from pipeline.coverage_course_pages where read_at >= $1 and read_status = 'read'$q$,
 $q$select count(*) from pipeline.coverage_course_pages where read_at >= $1 and read_status in ('fetch_failed', 'blocked')$q$,
 $q$select count(*) from pipeline.coverage_course_pages where status = 'bound' and read_attempts >= 3 and coalesce(read_status, '') <> 'read'$q$,
 'Matched pages given up after three failed reads',
 $q$with c as (select p.course_id from pipeline.coverage_course_pages p
                where p.status in ('bound', 'ambiguous') and p.read_attempts >= 3
                  and (p.read_status is null or (p.read_status = 'fetch_failed' and (p.http_status is null or p.http_status in (408, 425, 429, 500, 502, 503, 504, 520, 522, 524))))
                  and coalesce(p.read_at, p.bound_at, '-infinity') < $3
                  and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)
                  and not exists (select 1 from pipeline.queue_watch_retries r where r.queue_key = 'course_page_read' and r.item_key = p.course_id::text and r.retried_at > $2)
                order by p.read_at nulls first limit $1),
        u as (update pipeline.coverage_course_pages p set read_attempts = 2, next_read_at = now() from c where p.course_id = c.course_id returning p.course_id),
        i as (insert into pipeline.queue_watch_retries(queue_key, item_key) select 'course_page_read', u.course_id::text from u
              on conflict (queue_key, item_key) do update set retried_at = now(), times = pipeline.queue_watch_retries.times + 1 returning 1)
   select count(*)::int from i$q$,
 'Pages that gave up on a time-out or a busy server (no answer, 408, 429, 5xx) or never got an answer: one more read', '#layer-2-discovery?tab=operations', 30),
('ai_page_match', 'AI course page matching', 'Course pages', 'Asks the AI which of the provider''s pages is the course''s page.',
 '{coverage-ai-match,coverage-ai-match-prepare}', '{ai:course_match}',
 $q$select count(*) from pipeline.coverage_ai_match where state = 'ready' or (state = 'leased' and leased_until < now())$q$,
 $q$select max(decided_at) from pipeline.coverage_ai_match where state <> 'error'$q$,
 $q$select count(*) from pipeline.coverage_ai_match where decided_at >= $1 and state <> 'error'$q$,
 $q$select count(*) from pipeline.coverage_ai_match where state = 'error' and coalesce(decided_at, created_at) >= $1$q$,
 'select 0::bigint', null, null, null, '#layer-2-discovery?tab=operations', 40),
('course_list_read', 'Course list pages', 'Course pages', 'Reads the course list pages people entered for providers and adds their course links.',
 '{course-list-read}', '{firecrawl:reads}',
 $q$select count(*) from pipeline.provider_course_lists l where l.status <> 'stopped' and l.next_read_at <= now() and l.read_attempts < security.pipeline_num_v1('course_list.max_attempts', 4)$q$,
 $q$select max(read_at) from pipeline.provider_course_lists$q$,
 $q$select count(*) from pipeline.provider_course_lists where read_at >= $1$q$,
 $q$select count(*) from pipeline.provider_course_lists where status = 'failed' and updated_at >= $1$q$,
 $q$select count(*) from pipeline.provider_course_lists where status = 'failed' and read_attempts >= security.pipeline_num_v1('course_list.max_attempts', 4)$q$,
 'Course list pages given up after repeated failed reads',
 $q$with c as (select l.id from pipeline.provider_course_lists l
                where l.status = 'failed' and l.read_attempts >= security.pipeline_num_v1('course_list.max_attempts', 4)
                  and (l.http_status is null or l.http_status in (408, 425, 429, 500, 502, 503, 504, 520, 522, 524)) and l.updated_at < $3
                  and not exists (select 1 from pipeline.queue_watch_retries r where r.queue_key = 'course_list_read' and r.item_key = l.id::text and r.retried_at > $2)
                order by l.updated_at limit $1),
        u as (update pipeline.provider_course_lists l set status = 'due', read_attempts = greatest(0, security.pipeline_num_v1('course_list.max_attempts', 4)::int - 1), next_read_at = now(), updated_at = now() from c where l.id = c.id returning l.id),
        i as (insert into pipeline.queue_watch_retries(queue_key, item_key) select 'course_list_read', u.id::text from u
              on conflict (queue_key, item_key) do update set retried_at = now(), times = pipeline.queue_watch_retries.times + 1 returning 1)
   select count(*)::int from i$q$,
 'Course list pages that gave up on a time-out or a busy server: one more read', '#layer-2-discovery?tab=builder', 50),
('companion_read', 'Companion pages', 'Enrichment', 'Reads the pages that sit beside a course page (entry requirements, course data files).',
 '{companion-read}', '{firecrawl:reads}',
 $q$select count(*) from pipeline.course_companion_pages p where p.next_read_at <= now() and (p.leased_until is null or p.leased_until < now()) and p.read_attempts < security.pipeline_num_v1('companion.max_attempts', 4) and p.status <> 'gone' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)$q$,
 $q$select max(read_at) from pipeline.course_companion_pages$q$,
 $q$select count(*) from pipeline.course_companion_pages where read_at >= $1$q$,
 $q$select count(*) from pipeline.course_companion_pages where status in ('failed', 'blocked') and updated_at >= $1$q$,
 $q$select count(*) from pipeline.course_companion_pages where status in ('failed', 'blocked', 'too_thin') and read_attempts >= security.pipeline_num_v1('companion.max_attempts', 4)$q$,
 'Companion pages given up after repeated failed reads',
 $q$with c as (select p.course_id from pipeline.course_companion_pages p
                where p.status = 'failed' and p.read_attempts >= security.pipeline_num_v1('companion.max_attempts', 4)
                  and (p.http_status is null or p.http_status in (408, 425, 429, 500, 502, 503, 504, 520, 522, 524)) and p.updated_at < $3
                  and not exists (select 1 from pipeline.queue_watch_retries r where r.queue_key = 'companion_read' and r.item_key = p.course_id::text and r.retried_at > $2)
                order by p.updated_at limit $1),
        u as (update pipeline.course_companion_pages p set read_attempts = greatest(0, security.pipeline_num_v1('companion.max_attempts', 4)::int - 1), next_read_at = now(), updated_at = now() from c where p.course_id = c.course_id returning p.course_id),
        i as (insert into pipeline.queue_watch_retries(queue_key, item_key) select 'companion_read', u.course_id::text from u
              on conflict (queue_key, item_key) do update set retried_at = now(), times = pipeline.queue_watch_retries.times + 1 returning 1)
   select count(*)::int from i$q$,
 'Companion pages that gave up on a time-out or a busy server: one more read', '#layer-2-discovery?tab=builder', 60),
('fee_reader', 'Fee reader (AI)', 'Enrichment', 'Reads fee pages and schedules with the AI and records each fee row with its quote.',
 '{fee-reader}', '{ai:fee_ai}',
 $q$select count(*) from pipeline.fee_reader_queue q where q.state = 'queued' or (q.state = 'leased' and q.leased_until < now())$q$,
 $q$select max(finished_at) from pipeline.fee_reader_queue where state = 'done'$q$,
 $q$select count(*) from pipeline.fee_reader_queue where state = 'done' and finished_at >= $1$q$,
 $q$select count(*) from pipeline.fee_reader_queue where state = 'failed' and coalesce(finished_at, created_at) >= $1$q$,
 $q$select count(*) from pipeline.fee_reader_queue where state = 'failed'$q$,
 'Fee pages the AI could not read',
 $q$with c as (select q.id from pipeline.fee_reader_queue q
                where q.state = 'failed' and coalesce(q.finished_at, q.created_at) < $3
                  and coalesce(q.error, '') ~* '(time.?out|timed out|429|50[0234]|rate limit|overloaded|network|fetch failed|econnreset|unterminated string|unexpected end of json)'
                  and not exists (select 1 from pipeline.queue_watch_retries r where r.queue_key = 'fee_reader' and r.item_key = q.id::text and r.retried_at > $2)
                order by q.created_at limit $1),
        u as (update pipeline.fee_reader_queue q set state = 'queued', leased_until = null, error = null from c where q.id = c.id returning q.id),
        i as (insert into pipeline.queue_watch_retries(queue_key, item_key) select 'fee_reader', u.id::text from u
              on conflict (queue_key, item_key) do update set retried_at = now(), times = pipeline.queue_watch_retries.times + 1 returning 1)
   select count(*)::int from i$q$,
 'Fee pages that failed on a time-out, a busy service or a cut-off AI answer: asked once more', '#layer-2-discovery?tab=operations', 70),
('central_find', 'Find central pages', 'Enrichment', 'Searches each provider''s site for its fee schedule, English policy and calendar pages.',
 '{provider-facts}', '{firecrawl:central}',
 $q$select count(*) from pipeline.provider_central_search s where s.state = 'queued' and not exists (select 1 from pipeline.enrichment_flags f where f.entity = 'provider' and f.entity_key = s.provider_id::text and f.state = 'raised' and f.reason_code in ('central_not_due', 'central_budget'))$q$,
 $q$select max(searched_at) from pipeline.provider_central_search$q$,
 $q$select count(*) from pipeline.provider_central_search where searched_at >= $1$q$,
 $q$select count(*) from pipeline.provider_central_search where state = 'failed' and updated_at >= $1$q$,
 $q$select count(*) from pipeline.provider_central_search where state = 'failed'$q$,
 'Providers whose central page search failed', null, null, '#layer-2-discovery?tab=operations', 80),
('central_ai', 'Read central pages (AI)', 'Enrichment', 'Reads fee schedules, English policies and calendars with the AI.',
 '{central-ai}', '{ai:central_ai}',
 $q$select count(*) from pipeline.central_ai_queue q where (q.state = 'queued' or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3$q$,
 $q$select max(done_at) from pipeline.central_ai_queue where state = 'done'$q$,
 $q$select count(*) from pipeline.central_ai_queue where state = 'done' and done_at >= $1$q$,
 $q$select count(*) from pipeline.central_ai_queue where state = 'failed' and coalesce(done_at, created_at) >= $1$q$,
 $q$select count(*) from pipeline.central_ai_queue where state = 'failed'$q$,
 'Central pages the AI could not read',
 $q$with c as (select q.id from pipeline.central_ai_queue q
                where q.state = 'failed' and coalesce(q.done_at, q.created_at) < $3
                  and coalesce(q.error, '') ~* '(time.?out|timed out|429|50[0234]|rate limit|overloaded|network|fetch failed|econnreset|unterminated string|unexpected end of json)'
                  and not exists (select 1 from pipeline.queue_watch_retries r where r.queue_key = 'central_ai' and r.item_key = q.id::text and r.retried_at > $2)
                order by q.created_at limit $1),
        u as (update pipeline.central_ai_queue q set state = 'queued', attempts = least(q.attempts, 2), leased_until = null from c where q.id = c.id returning q.id),
        i as (insert into pipeline.queue_watch_retries(queue_key, item_key) select 'central_ai', u.id::text from u
              on conflict (queue_key, item_key) do update set retried_at = now(), times = pipeline.queue_watch_retries.times + 1 returning 1)
   select count(*)::int from i$q$,
 'Central pages that failed on a time-out, a busy service or a cut-off AI answer: asked once more', '#layer-2-discovery?tab=operations', 90),
('onboarding', 'Onboard universities', 'Course pages', 'Takes each provider through website check, course pages, adapter and scholarships.',
 '{provider-onboarding}', '{}',
 $q$select count(*) from pipeline.provider_onboarding where status not in ('done', 'stopped')$q$,
 $q$select max(at) from pipeline.provider_onboarding_events$q$,
 $q$select count(*) from pipeline.provider_onboarding_events where at >= $1$q$,
 'select 0::bigint',
 $q$select count(*) from pipeline.provider_onboarding where status = 'stopped' and coalesce(stop_reason, '') <> 'no_courses'$q$,
 'Providers stopped in onboarding for a reason a person must look at', null, null, '#layer-2-discovery?tab=universities', 100),
('enrich_plans', 'Enrichment plans', 'Enrichment', 'Runs the per-provider enrichment plans step by step.',
 '{enrich-plan-run,enrich-plan-auto}', '{}',
 $q$select count(*) from pipeline.enrich_plan_runs where state in ('queued', 'running')$q$,
 $q$select max(updated_at) from pipeline.enrich_plan_runs where state in ('running', 'done')$q$,
 $q$select count(*) from pipeline.enrich_plan_runs where state = 'done' and finished_at >= $1$q$,
 $q$select count(*) from pipeline.enrich_plan_runs where state = 'failed' and updated_at >= $1$q$,
 $q$select count(*) from pipeline.enrich_plan_runs where needs_person and state not in ('done', 'cancelled')$q$,
 'Plans waiting for a person', null, null, '#layer-2-discovery?tab=plan', 110),
('scholarship_read', 'Read scholarship pages', 'Scholarships', 'Reads each scholarship''s own page.',
 '{scholarship-read,scholarship-ai-extract}', '{firecrawl:scholarships,ai:scholarship_ai}',
 $q$select count(*) from pipeline.scholarship_pages p join scholarship.scholarships s on s.id = p.scholarship_id and s.lifecycle_status = 'active' where p.next_read_at <= now() and p.attempts < 5 and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id) and (p.requested_at is not null or not security.fc_sch_held_v1(s.provider_id, false))$q$,
 $q$select max(read_at) from pipeline.scholarship_pages$q$,
 $q$select count(*) from pipeline.scholarship_pages where read_at >= $1$q$,
 'select 0::bigint', 'select 0::bigint', null, null, null, '#layer-2-discovery?tab=scholarships', 120),
('scholarship_candidates', 'Scholarship candidate pages', 'Scholarships', 'Reads pages that may be scholarships found on provider sites.',
 '{scholarship-discover}', '{firecrawl:scholarships}',
 $q$select count(*) from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id = c.provider_id and d.priority in (0, 1, 3, 4) where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at <= now() and c.attempts < 3 and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id) and not security.fc_sch_held_v1(c.provider_id, true) and not security.third_party_host_v1(c.url) and not security.provider_sch_search_off_v1(c.provider_id)$q$,
 $q$select max(read_at) from pipeline.scholarship_page_candidates$q$,
 $q$select count(*) from pipeline.scholarship_page_candidates where read_at >= $1$q$,
 'select 0::bigint', 'select 0::bigint', null, null, null, '#layer-2-discovery?tab=scholarships', 130),
('scholarship_discover', 'Scholarship provider discovery', 'Scholarships', 'Maps provider sites for scholarship pages.',
 '{scholarship-discover,scholarship-discover-refill}', '{firecrawl:scholarships}',
 $q$select count(*) from pipeline.scholarship_discovery_providers d where d.status = 'pending' and d.attempts < 3 and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id) and not security.fc_sch_held_v1(d.provider_id, true) and not security.third_party_host_v1(coalesce(d.website, '')) and not security.provider_sch_search_off_v1(d.provider_id)$q$,
 $q$select max(updated_at) from pipeline.scholarship_discovery_providers where status <> 'pending'$q$,
 $q$select count(*) from pipeline.scholarship_discovery_providers where status <> 'pending' and updated_at >= $1$q$,
 'select 0::bigint', 'select 0::bigint', null, null, null, '#layer-2-discovery?tab=scholarships', 140)
on conflict (key) do nothing;

-- 2 tools ----------------------------------------------------------------------------------------------------------------------------
-- 'out': the tool cannot be used until a person acts (Firecrawl monthly credit down to its reserve; OpenRouter balance under its floor).
-- 'waiting': today's share is used up and comes back by itself (Firecrawl daily group budget; OpenRouter daily guard for that use).
create or replace function security.queue_watch_tool_state_v1(p_tool text)
returns text language plpgsql stable security definer set search_path = '' as $function$
declare v_kind text := split_part(p_tool, ':', 1); v_part text := split_part(p_tool, ':', 2); v_fc jsonb; v_bal numeric; v_floor numeric; v_mode text; g record;
begin
  if v_kind = 'firecrawl' then
    select c.detail->'firecrawl' into v_fc from pipeline.platform_health_checks c where c.key = 'budgets';
    if v_fc ? 'remaining' and v_fc ? 'reserve' and (v_fc->>'remaining')::numeric <= (v_fc->>'reserve')::numeric then return 'out'; end if;
    if security.fc_budget_left_v1(case v_part when 'course_search' then 'course_link_search' when 'reads' then 'scrape' when 'central' then 'central_map'
                                             when 'scholarships' then 'sch_map' else 'map' end) <= 0 then return 'waiting'; end if;
    return 'ok';
  elsif v_kind = 'ai' then
    select t.enforcement into v_mode from pipeline.platform_toolsets t where t.key = 'openrouter';
    if coalesce(v_mode, 'observe') <> 'stop' then return 'ok'; end if;
    select o.remaining_usd into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;  -- fixed: the latest reading
    v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
    if v_bal is not null and v_bal < v_floor then return 'out'; end if;
    select * into g from security.ai_spend_today_v1() x where x.use = v_part;
    if coalesce(g.guard, 0) > 0 and coalesce(g.spent, 0) >= g.guard then return 'waiting'; end if;
    return 'ok';
  end if;
  return 'ok';
end $function$;
revoke all on function security.queue_watch_tool_state_v1(text) from public, anon, authenticated;

-- 2b the watchdog run ----------------------------------------------------------------------------------------------------------------
create or replace function security.queue_watch_run_v1(p_fix boolean default true)
returns jsonb language plpgsql security definer set search_path = '' set statement_timeout to '120s' as $function$
declare
  q record; v_prev record; v_t0 timestamptz := clock_timestamp(); v_t timestamptz;
  v_win interval := make_interval(mins => security.pipeline_num_v1('queue_watch.window_minutes', 60)::int);
  v_stuck_default interval := make_interval(mins => security.pipeline_num_v1('queue_watch.stuck_minutes', 120)::int);
  v_fail_pct numeric := security.pipeline_num_v1('queue_watch.fail_percent', 50);
  v_fail_min numeric := security.pipeline_num_v1('queue_watch.fail_min', 5);
  v_repeat interval := make_interval(hours => security.pipeline_num_v1('queue_watch.alert_repeat_hours', 12)::int);
  v_retry_n int := security.pipeline_num_v1('queue_watch.retry_batch', 25)::int;
  v_retry_since timestamptz := now() - make_interval(days => security.pipeline_num_v1('queue_watch.retry_days', 7)::int);
  v_retry_before timestamptz := now() - make_interval(hours => security.pipeline_num_v1('queue_watch.retry_after_hours', 6)::int);
  v_pending bigint; v_done bigint; v_failed bigint; v_exh bigint; v_last timestamptz; v_state text; v_reason text;
  v_out text[]; v_wait text[]; v_paused text[]; v_idle text[]; v_tool text; v_ts text; v_fixed int; v_err text;
  v_rate numeric; v_eta numeric; v_summary jsonb := '[]'::jsonb; v_fixes int := 0; v_alerts int := 0; v_changes int := 0; v_title text; v_body text;
begin
  for q in select * from pipeline.queue_watch w where w.enabled order by w.sort loop
    v_t := clock_timestamp(); v_err := null; v_out := '{}'; v_wait := '{}'; v_paused := '{}'; v_idle := '{}'; v_fixed := 0;
    select * into v_prev from pipeline.queue_watch_state s where s.key = q.key;
    begin
      execute q.pending_sql into v_pending;
      execute q.progress_sql into v_last;
      execute q.done_sql into v_done using now() - v_win;
      execute q.failed_sql into v_failed using now() - v_win;
      execute q.exhausted_sql into v_exh;
      foreach v_tool in array q.tools loop
        v_ts := security.queue_watch_tool_state_v1(v_tool);
        if v_ts = 'out' then v_out := v_out || v_tool; elsif v_ts = 'waiting' then v_wait := v_wait || v_tool; end if;
      end loop;
      -- a job switched off by a person (no open waste-guard flag) pauses the queue; a job paused by the waste guard does not
      select coalesce(array_agg(j.jobname) filter (where not j.active and not exists (select 1 from pipeline.enrichment_flags f where f.entity = 'job' and f.entity_key = j.jobname and f.state = 'raised')), '{}'),
             coalesce(array_agg(j.jobname) filter (where exists (select 1 from pipeline.enrichment_flags f where f.entity = 'job' and f.entity_key = j.jobname and f.state = 'raised')), '{}')
        into v_paused, v_idle
        from cron.job j where j.jobname = any(q.jobnames);
      if cardinality(q.jobnames) > 0 and cardinality(v_paused) = cardinality(q.jobnames) then
        v_state := 'paused'; v_reason := 'Switched off by a person: ' || array_to_string(v_paused, ', ');
      elsif v_pending > 0 and coalesce(v_last, '-infinity') < now() - v_stuck_default and cardinality(v_out) > 0 then
        v_state := 'out_of_toolset'; v_reason := 'Work is waiting but ' || array_to_string(v_out, ', ') || ' cannot be used until a person acts (credit or balance used up)';
      elsif v_pending > 0 and coalesce(v_last, '-infinity') < now() - v_stuck_default and cardinality(v_wait) > 0 then
        v_state := 'waiting'; v_reason := 'Today''s budget for ' || array_to_string(v_wait, ', ') || ' is used up; it carries on when the budget comes back';
      elsif v_failed >= v_fail_min and v_failed * 100.0 / greatest(1, v_failed + v_done) >= v_fail_pct then
        v_state := 'failing'; v_reason := v_failed || ' of ' || (v_failed + v_done) || ' tried in the last ' || extract(epoch from v_win)::int / 60 || ' minutes failed';
      elsif v_pending > 0 and coalesce(v_last, '-infinity') < now() - v_stuck_default then
        v_state := 'stuck'; v_reason := v_pending || ' waiting and nothing finished since ' || coalesce(to_char(v_last at time zone 'Australia/Melbourne', 'DD Mon HH24:MI'), 'it started')
          || case when cardinality(v_idle) > 0 then '; paused by the waste guard: ' || array_to_string(v_idle, ', ') else '' end;
      elsif v_pending > 0 then
        v_state := 'moving'; v_reason := null;
      elsif v_exh > 0 then
        v_state := 'nothing_left'; v_reason := v_exh || ' ' || lower(coalesce(q.exhausted_label, 'items with nothing left to try'));
      else
        v_state := 'done'; v_reason := null;
      end if;
      -- safe fix: one more try for items that gave up on a passing error, never while a tool of the queue is out or waiting
      if p_fix and q.retry_sql is not null and v_retry_n > 0 and cardinality(v_out) = 0 and cardinality(v_wait) = 0 and v_state <> 'paused' then
        execute q.retry_sql into v_fixed using v_retry_n, v_retry_since, v_retry_before;
        if coalesce(v_fixed, 0) > 0 then
          insert into pipeline.queue_watch_fixes(key, fix, items, detail) values (q.key, 'one_more_try', v_fixed, jsonb_build_object('what', q.retry_label, 'state', v_state));
          v_fixes := v_fixes + v_fixed;
          if v_state in ('nothing_left', 'done') then v_state := 'moving'; v_reason := v_fixed || ' given one more try'; v_pending := v_pending + v_fixed; end if;
        end if;
      end if;
    exception when others then
      v_err := left(sqlerrm, 300); v_state := coalesce(v_prev.state, 'moving'); v_reason := 'The watchdog could not check this queue: ' || v_err;
    end;
    v_rate := round(v_done * 60.0 / greatest(1, extract(epoch from v_win) / 60), 1);
    v_eta := case when v_pending > 0 and v_rate > 0 then round(v_pending / v_rate, 1) end;
    insert into pipeline.queue_watch_state as s(key, state, since, reason, pending, done_window, failed_window, exhausted, last_progress, per_hour, eta_hours,
                                               tools_out, tools_waiting, jobs_paused, check_ms, checked_at, error)
    values (q.key, v_state, now(), v_reason, v_pending, v_done, v_failed, v_exh, v_last, v_rate, v_eta, v_out, v_wait, v_paused || v_idle,
            round(extract(epoch from clock_timestamp() - v_t) * 1000), now(), v_err)
    on conflict (key) do update set state = excluded.state, since = case when s.state = excluded.state then s.since else now() end, reason = excluded.reason,
      pending = excluded.pending, done_window = excluded.done_window, failed_window = excluded.failed_window, exhausted = excluded.exhausted,
      last_progress = excluded.last_progress, per_hour = excluded.per_hour, eta_hours = excluded.eta_hours, tools_out = excluded.tools_out,
      tools_waiting = excluded.tools_waiting, jobs_paused = excluded.jobs_paused, check_ms = excluded.check_ms, checked_at = now(), error = excluded.error;

    if v_err is null and (v_prev.state is null or v_prev.state is distinct from v_state) then
      insert into pipeline.queue_watch_events(key, from_state, to_state, reason, detail)
      values (q.key, v_prev.state, v_state, v_reason, jsonb_build_object('pending', v_pending, 'finished_window', v_done, 'failed_window', v_failed, 'nothing_left', v_exh));
      v_changes := v_changes + 1;
    end if;

    -- alerts: Stuck and Out of toolset to phone and email (again after queue_watch.alert_repeat_hours); Done and Nothing left to try to the report
    if v_err is null then
      v_title := q.label || ': ' || case v_state when 'stuck' then 'stuck' when 'out_of_toolset' then 'out of toolset' when 'done' then 'done'
                                                 when 'nothing_left' then 'nothing left to try' else v_state end;
      v_body := coalesce(v_reason, '') || case when v_pending > 0 then ' · ' || v_pending || ' waiting' else '' end;
      if v_state in ('stuck', 'out_of_toolset')
         and not exists (select 1 from pipeline.queue_watch_alerts a where a.key = q.key and a.state = v_state and a.channel = 'notify' and a.raised_at > now() - v_repeat
                           and a.raised_at >= (select max(e.at) from pipeline.queue_watch_events e where e.key = q.key)) then
        insert into pipeline.queue_watch_alerts(key, state, channel, title, body) values (q.key, v_state, 'notify', v_title, v_body);
        v_alerts := v_alerts + 1;
      elsif v_state in ('done', 'nothing_left') and v_prev.state is distinct from v_state and v_prev.state is not null then
        insert into pipeline.queue_watch_alerts(key, state, channel, title, body) values (q.key, v_state, 'report', v_title, v_body);
      end if;
      -- Platform health issue while Stuck, Failing or Out of toolset; closed when it is not
      if v_state in ('stuck', 'failing', 'out_of_toolset') then
        insert into pipeline.platform_issues as i(check_key, severity, area, title, detail)
        values ('queue_watch:' || q.key, case when v_state = 'out_of_toolset' then 'critical' else 'warning' end,
                case when q.area = 'Scholarships' then 'scholarships' else 'coverage sweep' end, left(v_title, 300),  -- the issue areas the health page groups by
                jsonb_build_object('reason', v_reason, 'waiting', v_pending, 'last_progress', v_last, 'resolve', q.fix_at))
        on conflict (check_key) where resolved_at is null do update set severity = excluded.severity, title = excluded.title, detail = excluded.detail,
          last_seen = now(), occurrences = i.occurrences + 1;
      else
        update pipeline.platform_issues i set resolved_at = now() where i.check_key = 'queue_watch:' || q.key and i.resolved_at is null;
      end if;
    end if;
    v_summary := v_summary || jsonb_build_object('queue', q.key, 'state', v_state, 'pending', v_pending);
  end loop;

  update pipeline.platform_health_checks c set
    status = case when exists (select 1 from pipeline.queue_watch_state s where s.state = 'out_of_toolset') then 'critical'
                  when exists (select 1 from pipeline.queue_watch_state s where s.state in ('stuck', 'failing')) then 'warning' else 'ok' end,
    detail = (select jsonb_build_object('queues', count(*), 'moving', count(*) filter (where s.state = 'moving'), 'stuck', count(*) filter (where s.state = 'stuck'),
                     'failing', count(*) filter (where s.state = 'failing'), 'out_of_toolset', count(*) filter (where s.state = 'out_of_toolset'),
                     'waiting_for_budget', count(*) filter (where s.state = 'waiting'), 'nothing_left', count(*) filter (where s.state = 'nothing_left'),
                     'done', count(*) filter (where s.state = 'done'), 'paused', count(*) filter (where s.state = 'paused'))
                from pipeline.queue_watch_state s join pipeline.queue_watch w on w.key = s.key and w.enabled),
    checked_at = now(), duration_ms = round(extract(epoch from clock_timestamp() - v_t0) * 1000)
   where c.key = 'queue_watch';
  return jsonb_build_object('queues', v_summary, 'changes', v_changes, 'alerts', v_alerts, 'fixed', v_fixes, 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $function$;
revoke all on function security.queue_watch_run_v1(boolean) from public, anon, authenticated;

-- 3 delivery and report --------------------------------------------------------------------------------------------------------------
create or replace function security.queue_watch_alerts_take_v1(p_channel text default 'notify', p_via text default 'scheduled task')
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v jsonb;
begin
  with t as (update pipeline.queue_watch_alerts a set sent_at = now(), sent_via = p_via
              where a.sent_at is null and a.channel = p_channel returning a.*)
  select coalesce(jsonb_agg(jsonb_build_object('queue', t.key, 'state', t.state, 'title', t.title, 'body', t.body, 'raised_at', t.raised_at) order by t.raised_at), '[]'::jsonb)
    into v from t;
  return jsonb_build_object('channel', p_channel, 'alerts', v, 'count', jsonb_array_length(v));
end $function$;
revoke all on function security.queue_watch_alerts_take_v1(text, text) from public, anon, authenticated;

create or replace function security.queue_watch_report_v1(p_hours int default null)
returns jsonb language sql stable security definer set search_path = '' as $function$
  with h as (select now() - make_interval(hours => coalesce(p_hours, security.pipeline_num_v1('queue_watch.report_hours', 24)::int)) since)
  select jsonb_build_object(
    'since', (select since from h), 'generated_at', now(),
    'queues', (select coalesce(jsonb_agg(jsonb_build_object('queue', w.key, 'label', w.label, 'area', w.area, 'state', s.state, 'since', s.since, 'reason', s.reason,
                       'waiting', s.pending, 'finished_per_hour', s.per_hour, 'eta_hours', s.eta_hours, 'nothing_left', s.exhausted,
                       'nothing_left_is', w.exhausted_label, 'last_progress', s.last_progress) order by w.sort), '[]'::jsonb)
                 from pipeline.queue_watch w join pipeline.queue_watch_state s on s.key = w.key where w.enabled),
    'changes', (select coalesce(jsonb_agg(jsonb_build_object('queue', e.key, 'at', e.at, 'from', e.from_state, 'to', e.to_state, 'reason', e.reason) order by e.at), '[]'::jsonb)
                  from pipeline.queue_watch_events e, h where e.at >= h.since),
    'fixes', (select coalesce(jsonb_agg(jsonb_build_object('queue', f.key, 'at', f.at, 'items', f.items, 'what', f.detail->>'what') order by f.at), '[]'::jsonb)
                from pipeline.queue_watch_fixes f, h where f.at >= h.since),
    'alerts', (select coalesce(jsonb_agg(jsonb_build_object('queue', a.key, 'state', a.state, 'channel', a.channel, 'title', a.title, 'body', a.body, 'raised_at', a.raised_at, 'sent_at', a.sent_at) order by a.raised_at), '[]'::jsonb)
                 from pipeline.queue_watch_alerts a, h where a.raised_at >= h.since))
$function$;
revoke all on function security.queue_watch_report_v1(integer) from public, anon, authenticated;

-- 4 admin ----------------------------------------------------------------------------------------------------------------------------
create or replace function public.admin_queue_watch(p_action text default 'list', p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_action = 'list' then
    return jsonb_build_object(
      'queues', (select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object('label', w.label, 'area', w.area, 'purpose', w.purpose, 'jobs', w.jobnames, 'tools', w.tools,
                         'nothing_left_is', w.exhausted_label, 'fix', w.retry_label, 'fix_at', w.fix_at) order by w.sort), '[]'::jsonb)
                   from pipeline.queue_watch w left join pipeline.queue_watch_state s on s.key = w.key where w.enabled),
      'events', (select coalesce(jsonb_agg(to_jsonb(e) order by e.at desc), '[]'::jsonb) from (select * from pipeline.queue_watch_events order by at desc limit 50) e),  -- fixed: screen list length
      'fixes', (select coalesce(jsonb_agg(to_jsonb(f) order by f.at desc), '[]'::jsonb) from (select * from pipeline.queue_watch_fixes order by at desc limit 30) f),  -- fixed: screen list length
      'alerts', (select coalesce(jsonb_agg(to_jsonb(a) order by a.raised_at desc), '[]'::jsonb) from (select * from pipeline.queue_watch_alerts order by raised_at desc limit 30) a),  -- fixed: screen list length
      'settings', jsonb_build_object('window_minutes', security.pipeline_num_v1('queue_watch.window_minutes', 60), 'stuck_minutes', security.pipeline_num_v1('queue_watch.stuck_minutes', 120)),
      'can_run', v_rank >= 4);
  elsif p_action = 'report' then
    return security.queue_watch_report_v1(null);
  elsif p_action = 'run' then
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    v := security.queue_watch_run_v1(true);
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('queue_watch', 'run', null, jsonb_build_object('reason', v_reason, 'result', v), auth.uid());
    return v;
  end if;
  raise exception 'unknown action';
end $function$;
revoke all on function public.admin_queue_watch(text, jsonb) from public, anon;
grant execute on function public.admin_queue_watch(text, jsonb) to authenticated;

-- 5 health check row, job, register --------------------------------------------------------------------------------------------------
insert into pipeline.platform_health_checks(key, area, label, status, detail, cadence_minutes, slow, sort_order)
values ('queue_watch', 'coverage sweep', 'Work queues are moving (progress watchdog)', 'ok', '{}'::jsonb, 15, false, 150)
on conflict (key) do nothing;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('queue-watch', 'Platform upkeep', 15, 'Progress watchdog', 'Every 15 minutes: gives each enrichment queue a state (Moving, Waiting for budget, Stuck, Failing, Out of toolset, Nothing left to try, Done, Paused), opens a Platform health issue while one is Stuck, Failing or Out of toolset, puts Stuck and Out of toolset in the alert outbox for phone and email, and gives items that gave up on a passing error one more try (logged). Settings queue_watch.*.', 4, false, null)
on conflict (jobname) do nothing;
select cron.schedule('queue-watch', '4-59/15 * * * *', $c$select security.queue_watch_run_v1(true)$c$);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.queue_watch', 'Platform', 'Progress watchdog: the watched queues', 'active', '{}', '20261022033000'),
 ('table', 'pipeline.queue_watch_state', 'Platform', 'Progress watchdog: latest state per queue', 'active', '{}', '20261022033000'),
 ('table', 'pipeline.queue_watch_events', 'Platform', 'Progress watchdog: state changes', 'active', '{}', '20261022033000'),
 ('table', 'pipeline.queue_watch_alerts', 'Platform', 'Progress watchdog: alert outbox', 'active', '{}', '20261022033000'),
 ('table', 'pipeline.queue_watch_fixes', 'Platform', 'Progress watchdog: safe fixes log', 'active', '{}', '20261022033000'),
 ('table', 'pipeline.queue_watch_retries', 'Platform', 'Progress watchdog: one more try per item', 'active', '{}', '20261022033000'),
 ('function', 'security.queue_watch_run_v1', 'Platform', 'Progress watchdog run', 'active', '{}', '20261022033000'),
 ('function', 'security.queue_watch_tool_state_v1', 'Platform', 'Progress watchdog: tool out, waiting or ok', 'active', '{}', '20261022033000'),
 ('function', 'security.queue_watch_alerts_take_v1', 'Platform', 'Progress watchdog: alerts to the delivery', 'active', '{}', '20261022033000'),
 ('function', 'security.queue_watch_report_v1', 'Platform', 'Progress watchdog: daily report', 'active', '{}', '20261022033000'),
 ('function', 'public.admin_queue_watch', 'Platform', 'Work queues screen: list, report, run now', 'active', '{}', '20261022033000')
on conflict (kind, name) do nothing;

 ('function', 'public.admin_queue_watch', 'Platform', 'Work queues screen: list, report, run now', 'active', '{}', '20261022033000')
on conflict (kind, name) do nothing;

do $dry$
declare r jsonb; t timestamptz := clock_timestamp(); s text;
begin
  r := security.queue_watch_run_v1(true);
  select string_agg(key||'='||state||' p'||coalesce(pending,-1)||' d'||coalesce(done_window,-1)||' f'||coalesce(failed_window,-1)||' x'||coalesce(exhausted,-1)||' '||coalesce(check_ms,-1)||'ms'||coalesce(' ERR '||error,''), ' | ' order by key) into s from pipeline.queue_watch_state;
  raise exception 'DRYRUN OK ms=% fixed=% alerts=% changes=% STATES % FIXES % ISSUES %', round(extract(epoch from clock_timestamp()-t)*1000), r->>'fixed', r->>'alerts', r->>'changes', s,
    (select string_agg(key||':'||items, ',') from pipeline.queue_watch_fixes),
    (select string_agg(check_key||'/'||severity, ',') from pipeline.platform_issues where check_key like 'queue_watch:%' and resolved_at is null);
end $dry$;
