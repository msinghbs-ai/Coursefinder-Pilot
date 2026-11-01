-- SS-014 D14 and monitoring accuracy: isolated fixture database (Platform Admin 2 Nov 2026 07:41). Run on a scratch PostgreSQL only
-- (never on a Supabase project): see run.sh. The smallest set of schemas, tables and helpers that the flag unit's idle guard
-- (security.flag_jobs_v1), the queue watchdog (security.queue_watch_run_v1) and the two readers (public.svc_coverage_read_next,
-- public.svc_course_link_search_next) need, with the columns they use. Helpers whose answer the readers take as given (focus, stop gate,
-- person task, site checks, Firecrawl budget) read small fixture tables (schema fx), so each case sets them. Nothing here is live data.
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists auth;
create schema if not exists cron; create schema if not exists net; create schema if not exists fx;
do $$ begin create role anon; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
create function auth.role() returns text language sql stable as $f$ select 'service_role'::text $f$;
create function auth.uid() returns uuid language sql stable as $f$ select null::uuid $f$;

-- settings (G2)
create table pipeline.platform_toolset_settings(toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric,
  unit text, sort int, section text, used_by text, reason text, updated_at timestamptz default now(), primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as
  $f$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $f$;
create function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable as
  $f$ select value from pipeline.platform_toolset_settings where toolset_key = p_toolset and key = p_key $f$;
create function security.firecrawl_setting(p_key text) returns jsonb language sql stable as
  $f$ select value from pipeline.platform_toolset_settings where toolset_key = 'firecrawl' and key = p_key $f$;
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values
  ('pipeline', 'flag.empty_calls_to_pause', 'number', '30'), ('pipeline', 'flag.never_pause_modes', 'list', '["openrouter_balance"]'),
  ('pipeline', 'flag.job_recheck_hours', 'list', '[1, 2, 4, 6]'), ('pipeline', 'tick.backoff_max_minutes', 'number', '15'),
  ('pipeline', 'search.daily_picked_cap', 'number', '200'), ('pipeline', 'search.person_task_bypass', 'number', '1'),
  ('pipeline', 'search.priority_countries', 'list', '["NZ"]'), ('pipeline', 'search.skip_providers', 'list', '["skip-me"]'),
  ('firecrawl', 'target_only', 'flag', 'true');

-- scheduler and HTTP answers (pg_cron, pg_net)
create table cron.job(jobid bigserial primary key, jobname text unique, schedule text, command text, active boolean not null default true);
create function cron.alter_job(job_id bigint, schedule text default null, command text default null, database text default null, username text default null, active boolean default null)
returns void language sql as $f$ update cron.job set schedule = coalesce(alter_job.schedule, cron.job.schedule), command = coalesce(alter_job.command, cron.job.command),
  active = coalesce(alter_job.active, cron.job.active) where jobid = job_id $f$;
create table net._http_response(id bigint primary key, status_code int, content text, timed_out boolean, error_msg text, created timestamptz not null default now());
create table pipeline.edge_request_log(id bigserial primary key, function_name text, mode text, request_id bigint, created_at timestamptz not null default now());

-- flag unit tables (columns the flag functions use)
create table pipeline.enrichment_flags(id bigserial primary key, entity text not null, entity_key text not null, provider_id uuid, field text not null default '',
  reason_code text not null, reason text, source text, kind text, state text, tries int not null default 0, checks int not null default 0, evidence jsonb,
  next_check_at timestamptz, input_mark text, raised_by_kind text, flagged_at timestamptz not null default now(), cleared_at timestamptz, released_at timestamptz,
  released_by text, release_kind text, release_reason text, unique (entity, entity_key, field, reason_code));
create table pipeline.enrichment_flag_events(id bigserial primary key, flag_id bigint, action text, actor text, actor_kind text, reason text, evidence jsonb, at timestamptz not null default now());
create table pipeline.job_idle_watch(jobname text primary key, paused_at timestamptz, resumed_at timestamptz);
create table pipeline.provider_logo_finds(provider_id uuid, status text, updated_at timestamptz);
create table pipeline.provider_central_search(provider_id uuid, state text, attempts int, leased_until timestamptz, updated_at timestamptz);

-- providers, courses and the hidden-provider view (security.provider_hidden_v1 is a view live; here it lists fx.hidden)
create table catalogue.providers(id uuid primary key, stable_key text, lifecycle_status text default 'active', website text);
create table catalogue.courses(id uuid primary key, provider_id uuid, canonical_title text, course_code text);
create table fx.hidden(provider_id uuid primary key);
-- what each provider-level and course-level helper answers is set per case
create table fx.provider(provider_id uuid primary key, focus boolean default true, few boolean default false, unchecked boolean default false, tier int default 1,
  country text default 'AU', stopped boolean default false);
create table fx.course(course_id uuid primary key, stop_reason text, person_task boolean default false, site_list_done boolean default true);
create table fx.budget(purpose text primary key, left_units numeric);
create view security.provider_hidden_v1 as select provider_id from fx.hidden;

-- course page reading (public.svc_coverage_read_next)
create table pipeline.coverage_course_pages(course_id uuid primary key, provider_id uuid, url text, status text default 'bound', basis text, read_status text,
  next_read_at timestamptz, leased_until timestamptz, read_attempts int not null default 0, bound_at timestamptz default now(), read_at timestamptz,
  fetched_via text, evidence_id uuid, http_status int, candidates jsonb);
create table pipeline.provider_priority(provider_id uuid primary key, rank int);
create table pipeline.course_priority(course_id uuid primary key, sort int);
create table pipeline.page_reread_pilot(course_id uuid, outcome_at timestamptz);
create table pipeline.page_link_repairs(course_id uuid, reason text);
create function security.coverage_country(p uuid) returns text language sql stable as $f$ select coalesce((select country from fx.provider where provider_id = p), 'AU') $f$;
create function security.render_country_v1(p uuid) returns boolean language sql stable as $f$ select false $f$;

-- course page search (public.svc_course_link_search_next): what each provider-level and course-level helper answers is set per case
create table pipeline.course_link_search_settings(id int primary key, enabled boolean, monthly_credit_cap numeric);
insert into pipeline.course_link_search_settings values (1, true, 100000);
create table pipeline.coverage_vendor_usage(purpose text, units numeric, provider_id uuid, at timestamptz default now());
create table pipeline.course_link_search(course_id uuid primary key, provider_id uuid, stage text default 'cricos', state text default 'queued', requested_at timestamptz,
  sent_at timestamptz, req_id bigint, query text, done_at timestamptz);
create index on pipeline.course_link_search (sent_at);
create table pipeline.course_link_recipes(provider_id uuid primary key, active boolean default true, search_domain text);
create table pipeline.provider_onboarding(provider_id uuid, source text, created_at timestamptz default now());
create table pipeline.firecrawl_search_resumes(provider_id uuid, resumed_at timestamptz);
create table pipeline.firecrawl_target_cache(provider_id uuid primary key, included boolean);
create function security.fc_budget_left_v1(p text) returns numeric language sql stable as $f$ select coalesce((select left_units from fx.budget where purpose = p), 100000) $f$;
create function security.fc_search_stopped_v1() returns table(provider_id uuid) language sql stable as $f$ select provider_id from fx.provider where stopped $f$;
create function security.enrich_focus_v1(p uuid) returns boolean language sql stable as $f$ select coalesce((select focus from fx.provider where provider_id = p), false) $f$;
create function security.site_few_course_pages_v1(p uuid) returns boolean language sql stable as $f$ select coalesce((select few from fx.provider where provider_id = p), false) $f$;
create function security.site_not_checked_v1(p uuid) returns boolean language sql stable as $f$ select coalesce((select unchecked from fx.provider where provider_id = p), false) $f$;
create function security.fc_provider_tier_v1(p uuid) returns int language sql stable as $f$ select coalesce((select tier from fx.provider where provider_id = p), 9) $f$;
create function security.third_party_host_v1(p_url text) returns boolean language sql stable as $f$ select p_url like '%directory.example%' $f$;
-- the one stop gate: a stopped university holds every search unless a person asked; a course stop holds that course
create function security.search_stop_gate_v1(p uuid, c uuid, p_stopped boolean) returns text language sql stable as $f$
  select coalesce((select stop_reason from fx.course where course_id = c),
                  case when p_stopped and not coalesce((select person_task from fx.course where course_id = c), false) then 'university stopped' end) $f$;
create function security.link_search_person_task_v1(p uuid, c uuid) returns boolean language sql stable as $f$ select coalesce((select person_task from fx.course where course_id = c), false) $f$;
create function security.site_list_match_done_v1(c uuid, p uuid) returns boolean language sql stable as $f$ select coalesce((select site_list_done from fx.course where course_id = c), true) $f$;

-- AI page matching queue and the re-arm's "work is waiting" test (security.worker_mode_waiting_v1: its ai_match branch as live; other lanes false)
create table pipeline.coverage_ai_match(id bigserial primary key, provider_id uuid, course_id uuid, state text, leased_until timestamptz, decided_at timestamptz, created_at timestamptz default now());
create function security.worker_mode_waiting_v1(p_mode text) returns boolean language sql stable security definer set search_path = '' as $f$
  select case p_mode
    when 'ai_match' then exists (select 1 from pipeline.coverage_ai_match q
                              where (q.state = 'ready' or (q.state = 'leased' and q.leased_until < now()))
                                and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id))
    else false end $f$;
-- the worker jobs the idle guard looks after (commands as live, sizes from settings)
insert into cron.job(jobname, schedule, command) values
 ('coverage-ai-match', '* * * * *', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'ai_match', 'limit', security.pipeline_num_v1('batch.ai_match', 80)::int))$c$),
 ('openrouter-balance', '*/15 * * * *', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'openrouter_balance'))$c$);

-- watchdog tables (as created by 20261022033000; upstream_key added live later)
create table pipeline.queue_watch(key text primary key, label text not null, area text not null, purpose text not null, jobnames text[] not null default '{}',
  tools text[] not null default '{}', pending_sql text not null, progress_sql text not null, done_sql text not null, failed_sql text not null default 'select 0::bigint',
  exhausted_sql text not null default 'select 0::bigint', exhausted_label text, retry_sql text, retry_label text, fix_at text, sort int not null default 100,
  enabled boolean not null default true, created_at timestamptz not null default now(), upstream_key text);
create table pipeline.queue_watch_state(key text primary key references pipeline.queue_watch(key), state text not null, since timestamptz not null default now(), reason text,
  pending bigint, done_window bigint, failed_window bigint, exhausted bigint, last_progress timestamptz, per_hour numeric, eta_hours numeric,
  tools_out text[] not null default '{}', tools_waiting text[] not null default '{}', jobs_paused text[] not null default '{}', check_ms int, checked_at timestamptz not null default now(), error text);
create table pipeline.queue_watch_events(id bigserial primary key, key text, from_state text, to_state text, reason text, detail jsonb, at timestamptz not null default now());
create table pipeline.queue_watch_alerts(id bigserial primary key, key text, state text, channel text, title text, body text, raised_at timestamptz not null default now(), sent_at timestamptz, sent_via text);
create table pipeline.queue_watch_fixes(id bigserial primary key, key text, fix text, items int, detail jsonb, at timestamptz not null default now());
create table pipeline.queue_watch_retries(queue_key text, item_key text, retried_at timestamptz not null default now(), times int not null default 1, primary key (queue_key, item_key));
create table pipeline.platform_issues(id bigserial primary key, check_key text, severity text, area text, title text, detail jsonb, first_seen timestamptz default now(),
  last_seen timestamptz default now(), occurrences int not null default 1, resolved_at timestamptz);
create unique index on pipeline.platform_issues (check_key) where resolved_at is null;
create table pipeline.platform_health_checks(key text primary key, status text, detail jsonb, checked_at timestamptz, duration_ms int);
insert into pipeline.platform_health_checks(key) values ('queue_watch');
create function security.queue_watch_tool_state_v1(p_tool text) returns text language sql stable as $f$ select 'ok'::text $f$;
-- the component register the housekeeping rule writes to
create table pipeline.component_register(kind text, name text, layer text, area text, purpose text, status text, replaces text[], introduced_in text, replaced_by text, retire_after date, primary key (kind, name));
create table pipeline.automation_catalogue(key text primary key);

-- the two watched queues as they are live (pending_sql exactly as read on 2 Nov 2026: md5 faa7842a and 78fb1655; the migration checks them)
insert into pipeline.queue_watch(key, label, area, purpose, jobnames, tools, pending_sql, progress_sql, done_sql, sort) values
('course_page_search', 'Find course pages (search)', 'Course pages', 'Searches the web for the official page of each course without one.', '{course-link-search,course-link-search-worker}', '{firecrawl:course_search}',
 $q$select count(*) from pipeline.course_link_search q where q.state = 'queued' and not exists (select 1 from pipeline.enrichment_flags f where f.entity = 'course' and f.entity_key = q.course_id::text and f.kind = 'hard' and f.state = 'raised')$q$,
 $q$select max(done_at) from pipeline.course_link_search$q$, $q$select count(*) from pipeline.course_link_search where done_at >= $1$q$, 10),
('course_page_read', 'Read course pages', 'Course pages', 'Reads each matched course page and keeps the evidence.', '{coverage-read}', '{firecrawl:reads}',
 $q$select count(*) from pipeline.coverage_course_pages p where p.status in ('bound', 'ambiguous') and coalesce(p.next_read_at, now()) <= now() and p.read_attempts < 3$q$,
 $q$select max(read_at) from pipeline.coverage_course_pages where read_status is not null and read_status not in ('fetch_failed', 'blocked')$q$,
 $q$select count(*) from pipeline.coverage_course_pages where read_at >= $1 and read_status not in ('fetch_failed', 'blocked')$q$, 30);
insert into cron.job(jobname, schedule, command) values
 ('course-link-search', '* * * * *', 'select 1'), ('course-link-search-worker', '* * * * *', 'select 1'), ('coverage-read', '30 seconds', 'select 1');
