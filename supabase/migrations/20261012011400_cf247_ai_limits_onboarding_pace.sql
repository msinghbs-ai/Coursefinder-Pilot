-- CF-247 v2.15.258 (12 Oct 2026). Platform Admin bug 12/10-01: "Models and services are missing Layer 3 limits functionality".
-- Found: the OpenRouter limits still read Layer 3, retired on 12 Oct 2026 — the balance was read by the Layer 3 route guard job (gone,
-- so "balance has not been read recently"), the daily guards and credit floor were edited in the removed Layer 3 settings section, and
-- spend was counted from Layer 3 calls only. Nothing measured the AI that runs now.
-- 1. AI limits without Layer 3: a daily guard per AI use (scholarship AI, adapter proposals, central pages, course-page matching) and a
--    credit floor, as OpenRouter settings on Models & services; spend today per use (security.ai_spend_today_v1); notices for refused
--    calls, a low balance, the floor, a stale reading and a guard passed. Observe only stays the mode (Decision 252; Platform Admin
--    12 Oct 2026); in Stop at limits the scholarship AI and the central pages AI stop at their guard or the floor.
-- 2. The balance is read every 15 minutes by a new catalogued job, openrouter-balance (worker mode openrouter_balance).
-- 3. Onboarding: "How many at once" 100 (Platform Admin 12 Oct 2026); the read gives how many are not yet queued and the pace.
-- Guarded on the live definitions; nothing dropped.
do $guard$
declare v_expected jsonb := '{"security.platform_notices_v1()": "a3f2caceece225e3c0710119fc76fe38", "security.scholarship_ai_fire_v1()": "8db54bb2f9334f3e63947524dccff0b5", "security.central_ai_fire_v1()": "ac7082e062b4e7b99ba593f5970eba99", "public.admin_toolsets_read()": "ba108d9abcac0af663f31869e776fcd0", "public.admin_provider_onboarding(text, jsonb)": "9f609f60fe7b79fb39c312abbb0bb3cf"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

update pipeline.platform_toolsets set layers = array[2], updated_at = now(), reason = 'CF-247 v2.15.258: AI limits without Layer 3 (bug 12/10-01)',
       help = 'AI models for scholarship pages, adapter proposals, central pages and course-page matching. Observe only: the daily guards and the credit floor raise notices but stop nothing. Stop at limits: the scholarship AI and the central pages AI stop for the day at their guard and stop entirely below the credit floor; adapter proposals stop at their own daily allowance (Adapter builder). OpenRouter''s own key limits apply either way.'
 where key = 'openrouter';
update pipeline.platform_toolset_settings set help = 'A notice is raised when the OpenRouter balance falls below this. It does not stop anything.', updated_at = now()
 where toolset_key = 'openrouter' and key = 'low_balance_warn_usd';
update pipeline.platform_toolset_settings set help = 'The balance is read every 15 minutes (job openrouter-balance); if no reading is newer than this, a notice is raised.', updated_at = now()
 where toolset_key = 'openrouter' and key = 'balance_stale_minutes';
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, unit, min_value, max_value, sort, section, reason, updated_at) values
  ('openrouter', 'credit_floor_usd', 'Credit floor', 'Below this balance a high notice is raised; in Stop at limits the scholarship AI and the central pages AI stop.', 'number', '5', 'US$', 0, 500, 40, 'Daily guards', 'CF-247 v2.15.258', now()),
  ('openrouter', 'guard_scholarship_ai', 'Daily guard: read scholarship pages with AI', 'Spend in a UTC day by the scholarship AI (Qwen3 30B, GPT-4.1 mini and any third reader).', 'number', '20', 'US$ a day', 0, 500, 41, 'Daily guards', 'CF-247 v2.15.258', now()),
  ('openrouter', 'guard_adapter_builder', 'Daily guard: adapter proposals', 'Spend in a UTC day by AI adapter proposals (onboarding and the Adapter builder). They also stop at the Adapter builder''s own daily allowance.', 'number', '5', 'US$ a day', 0, 500, 42, 'Daily guards', 'CF-247 v2.15.258', now()),
  ('openrouter', 'guard_central_ai', 'Daily guard: central pages with AI', 'Spend in a UTC day reading English policies and academic calendars with AI.', 'number', '5', 'US$ a day', 0, 500, 43, 'Daily guards', 'CF-247 v2.15.258', now()),
  ('openrouter', 'guard_course_match', 'Daily guard: AI course-page matching', 'Spend in a UTC day by AI course-page matching (observed only).', 'number', '5', 'US$ a day', 0, 500, 44, 'Daily guards', 'CF-247 v2.15.258', now())
on conflict (toolset_key, key) do nothing;

-- spend today (UTC day) per AI use, with its guard
create or replace function security.ai_spend_today_v1() returns table(use text, label text, spent numeric, guard numeric, calls bigint)
language sql stable security definer set search_path to '' as $f$
  with d as (select (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') t),
  s as (
    select 'scholarship_ai' u, coalesce(sum(x.cost_usd), 0) spent, count(*) calls from pipeline.scholarship_ai_extractions x, d where x.at >= d.t
    union all select 'adapter_builder', coalesce(sum(x.cost_usd), 0), count(*) from pipeline.uni_adapter_drafts x, d where x.created_at >= d.t and coalesce(x.cost_usd, 0) > 0
    union all select 'central_ai', coalesce(sum(x.cost_usd), 0), count(*) from pipeline.central_ai_queue x, d where x.created_at >= d.t and coalesce(x.cost_usd, 0) > 0
    union all select 'course_match', coalesce(sum(x.cost_usd), 0), count(*) from pipeline.coverage_ai_match x, d where coalesce(x.decided_at, x.created_at) >= d.t and coalesce(x.cost_usd, 0) > 0)
  select s.u, l.label, round(s.spent, 4), (security.toolset_setting('openrouter', 'guard_' || s.u))::text::numeric, s.calls
    from s join (values ('scholarship_ai', 'Read scholarship pages with AI', 1), ('adapter_builder', 'Adapter proposals', 2), ('central_ai', 'Central pages with AI', 3),
                        ('course_match', 'AI course-page matching', 4)) l(u, label, sort) on l.u = s.u
   order by l.sort
$f$;
revoke all on function security.ai_spend_today_v1() from public, anon, authenticated;

-- whether an AI use may run now: always in Observe only; in Stop at limits not past its guard and not below the credit floor
create or replace function security.ai_use_allowed_v1(p_use text) returns boolean language plpgsql stable security definer set search_path to '' as $f$
declare v_mode text; v_bal numeric; v_floor numeric; g record;
begin
  select t.enforcement into v_mode from pipeline.platform_toolsets t where t.key = 'openrouter';
  if coalesce(v_mode, 'observe') <> 'stop' then return true; end if;
  select o.remaining_usd into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  if v_bal is not null and v_bal < v_floor then return false; end if;
  select * into g from security.ai_spend_today_v1() x where x.use = p_use;
  return not (coalesce(g.guard, 0) > 0 and coalesce(g.spent, 0) >= g.guard);
end $f$;
revoke all on function security.ai_use_allowed_v1(text) from public, anon, authenticated;

-- the balance, read by the worker (mode openrouter_balance) every 15 minutes
create or replace function public.svc_openrouter_balance_record(p_payload jsonb) returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_rem numeric;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  v_rem := (p_payload->>'total_credits')::numeric - (p_payload->>'total_usage')::numeric;
  if v_rem is null then raise exception 'no balance in the reading'; end if;
  insert into pipeline.layer3_openrouter_observations(kind, payload, remaining_usd) values ('credits', p_payload, v_rem);
  return jsonb_build_object('remaining_usd', round(v_rem, 4));
end $f$;
revoke all on function public.svc_openrouter_balance_record(jsonb) from public, anon, authenticated;
grant execute on function public.svc_openrouter_balance_record(jsonb) to service_role;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('openrouter-balance', 'Platform upkeep', 11, 'Read the OpenRouter balance',
        'Every 15 minutes: reads the OpenRouter balance the AI uses (scholarship pages, adapter proposals, central pages, course-page matching) for the credit bar, the notices and the credit floor.', 6, false)
on conflict (jobname) do nothing;
do $c$ begin
  if not exists (select 1 from cron.job where jobname = 'openrouter-balance') then
    perform cron.schedule('openrouter-balance', '*/15 * * * *', $j$select pipeline.svc_pilot_submit_nonce('coverage-sweep', '{"mode":"openrouter_balance"}'::jsonb)$j$);
  end if;
end $c$;

CREATE OR REPLACE FUNCTION security.platform_notices_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w_or int := coalesce((security.toolset_setting('openrouter', 'notice_window_hours'))::text::int, 24);
  w_job int := coalesce((security.toolset_setting('scheduled_jobs', 'notice_window_hours'))::text::int, 24);
  w_edge int := coalesce((security.toolset_setting('edge_functions', 'notice_window_hours'))::text::int, 6);
  v_or_mode text := coalesce((select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter'), 'stop');
  v jsonb := '[]'::jsonb;
begin
  -- v2.15.258 (bug 12/10-01): OpenRouter notices for the AI uses that run now (Layer 3 retired on 12 Oct 2026). Refused calls
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'openrouter:2:refused:' || z.code, 'layer', 2, 'toolset', 'openrouter', 'kind', 'refused', 'severity', 'high',
      'title', case z.code when 'credit' then 'OpenRouter refused calls: out of credit'
                           when 'key_limit' then 'OpenRouter refused calls: the key''s own spending limit was reached'
                           when 'rate' then 'OpenRouter refused calls: rate limit'
                           else 'OpenRouter refused calls: key not accepted' end,
      'detail', format('%s AI calls in the last %s hours were refused; those pages are read again later.', z.n, w_or),
      'hint', case z.code when 'credit' then 'Top up the OpenRouter balance; the refused pages are read again by themselves.'
                          when 'key_limit' then 'The limit is set on the key at OpenRouter (Workspaces › Keys), not in StudySearch. Raise or clear it there.'
                          when 'rate' then 'Usually clears by itself; the pages are read again.'
                          else 'Check the OpenRouter key on Settings.' end,
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select case when r.e ilike '%key limit%' or r.e ilike '%weekly limit%' then 'key_limit' when r.e ~ 'HTTP 402' or r.e ilike '%credit%' then 'credit'
                      when r.e ~ 'HTTP 429' then 'rate' else 'key' end code, count(*) n, min(r.at) first_at, max(r.at) last_at
          from (select x.error e, x.at from pipeline.scholarship_ai_extractions x where x.at > now() - make_interval(hours => w_or) and x.error ~ 'HTTP (40[123]|429)'
                union all
                select q.error, coalesce(q.done_at, q.created_at) from pipeline.central_ai_queue q where q.created_at > now() - make_interval(hours => w_or) and q.error ~ 'HTTP (40[123]|429)') r
          group by 1) z), '[]'::jsonb);

  -- OpenRouter balance: below the warning level, below the credit floor, or not read recently (read by the openrouter-balance job)
  v := v || coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('key', 'openrouter:2:low_balance', 'layer', 2, 'toolset', 'openrouter', 'kind', 'low_balance',
      'severity', case when o.remaining_usd < coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0) then 'high' else 'warning' end,
      'title', format('OpenRouter balance is US$%s', round(o.remaining_usd, 2)),
      'detail', case when o.remaining_usd < coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0)
                     then format('Below the credit floor of US$%s. AI is set to %s.', security.toolset_setting('openrouter', 'credit_floor_usd'),
                                 case v_or_mode when 'observe' then 'observe only, so it keeps running until OpenRouter refuses calls' else 'stop at limits, so the scholarship AI and central pages AI have stopped' end)
                     else format('Below the warning level of US$%s. AI is set to %s.', security.toolset_setting('openrouter', 'low_balance_warn_usd'),
                                 case v_or_mode when 'observe' then 'observe only' else 'stop at limits' end) end,
      'hint', 'Top up the OpenRouter account the platform''s key uses.',
      'count', 1, 'first_at', o.observed_at, 'last_at', o.observed_at) x
    from (select * from pipeline.layer3_openrouter_observations where kind = 'credits' order by observed_at desc limit 1) o
    where o.remaining_usd < greatest(coalesce((security.toolset_setting('openrouter', 'low_balance_warn_usd'))::text::numeric, 0),
                                     coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0))
    union all
    select jsonb_build_object('key', 'openrouter:2:not_observed', 'layer', 2, 'toolset', 'openrouter', 'kind', 'not_observed', 'severity', 'warning',
      'title', 'OpenRouter balance has not been read recently',
      'detail', format('Last reading %s.', coalesce(to_char(o.observed_at at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'), 'never')),
      'hint', 'The balance is read every 15 minutes by the scheduled job "Read the OpenRouter balance" (openrouter-balance); check it in Scheduled jobs.',
      'count', 1, 'first_at', o.observed_at, 'last_at', now())
    from (select max(observed_at) observed_at from pipeline.layer3_openrouter_observations where kind = 'credits') o
    where o.observed_at is null or o.observed_at < now() - make_interval(mins => coalesce((security.toolset_setting('openrouter', 'balance_stale_minutes'))::text::int, 30))
  ) q), '[]'::jsonb);

  -- An AI use past its daily guard today (UTC day)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'openrouter:2:over_guard:' || g.use || ':' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD'), 'layer', 2, 'toolset', 'openrouter', 'kind', 'over_guard',
      'severity', case v_or_mode when 'observe' then 'info' else 'warning' end,
      'title', format('%s spent US$%s today, past its guard of US$%s', g.label, g.spent, g.guard),
      'detail', case v_or_mode when 'observe' then 'Observe only: it keeps running. This is recorded for the top-up review.'
                     else 'Stop at limits: it has stopped until the UTC day changes (adapter proposals stop at their own allowance; course-page matching is observed only).' end,
      'hint', 'Change the guard or the mode on Models & services › OpenRouter (AI models) › Daily guards.',
      'count', 1, 'first_at', now(), 'last_at', now()))
    from security.ai_spend_today_v1() g where g.guard > 0 and g.spent >= g.guard), '[]'::jsonb);

  -- Firecrawl balance, scholarship share, course-link search cap (Layer 2)
  v := v || coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('key', 'firecrawl:2:low_balance', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'low_balance', 'severity', 'warning',
      'title', format('Firecrawl has %s credits left this month', o.remaining_units),
      'detail', format('Below the warning level of %s. The period ends %s.', security.toolset_setting('firecrawl', 'low_balance_warn_units'), to_char(o.period_end at time zone 'Australia/Melbourne', 'DD Mon YYYY')),
      'hint', 'Work that needs Firecrawl stops at the reserve set on Scrapers & fetchers.', 'count', 1, 'first_at', o.observed_at, 'last_at', o.observed_at) x
    from (select v2.* from pipeline.vendor_credit_observations v2 join pipeline.layer2_acquisition_providers p on p.id = v2.provider_id and p.provider_key = 'firecrawl' order by v2.observed_at desc limit 1) o
    where o.remaining_units < coalesce((security.toolset_setting('firecrawl', 'low_balance_warn_units'))::text::numeric, 0)
    union all
    select jsonb_build_object('key', 'firecrawl:2:scholarship_share', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'cap_reached', 'severity', 'warning',
      'title', format('Scholarship Firecrawl share: %s of %s credits used', s.used, s.cap),
      'detail', format('Fewer than the reserve of %s are left, so newly found scholarship pages that refuse a direct read are not read.', s.reserve),
      'hint', 'Raise the cap on Layer 2 › Scholarships if you want them read.', 'count', 1, 'first_at', now(), 'last_at', now())
    from (select (b->>'used')::numeric used, (b->>'cap')::numeric cap, (b->>'reserve')::numeric reserve
          from (select jsonb_build_object(
                  'used', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape')),
                  'cap', (select s2.value from pipeline.scholarship_layer_settings s2 where s2.key = 'firecrawl_cap'),
                  'reserve', (select s2.value from pipeline.scholarship_layer_settings s2 where s2.key = 'firecrawl_reserve')) b) q) s
    where s.cap - s.used <= s.reserve
    union all
    select jsonb_build_object('key', 'firecrawl:2:course_link_cap:' || to_char(now(), 'YYYY-MM'), 'layer', 2, 'toolset', 'firecrawl', 'kind', 'cap_reached', 'severity', 'warning',
      'title', format('Course-link search used %s of its %s monthly credits', l.used, l.cap),
      'detail', 'Course-link search stops for the rest of the month.', 'hint', 'Change the monthly cap on Jobs › Priority.',
      'count', 1, 'first_at', now(), 'last_at', now())
    from (select (select monthly_credit_cap from pipeline.course_link_search_settings limit 1) cap,
                 (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose = 'course_link_search' and u.at >= date_trunc('month', now())) used) l
    where l.used >= l.cap
  ) q), '[]'::jsonb);

  -- Scheduled jobs that timed out or failed (the job's layer)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'scheduled_jobs:' || z.layer || ':' || z.kind || ':' || z.jobname, 'layer', z.layer, 'toolset', 'scheduled_jobs', 'kind', z.kind,
      'severity', case when z.n >= 5 then 'high' else 'warning' end,
      'title', case z.kind when 'timeout' then format('Job "%s" hit the database time limit %s times', z.jobname, z.n)
                           else format('Job "%s" failed %s times', z.jobname, z.n) end,
      'detail', format('In the last %s hours (%s runs in all). Last message: %s', w_job, z.runs, z.msg),
      'hint', case z.kind when 'timeout' then 'Lower the job''s batch size setting so each run finishes inside the limit.' else 'Usually clears by itself (for example a deadlock); if it repeats, the job needs a fix.' end,
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    -- (11 Oct 2026: the run history is read once, last 7 days; only the jobs that failed are ranked for "last three runs succeeded")
    from (with hist as materialized (select h.jobid, h.status, h.return_message, h.start_time, h.end_time
                                       from cron.job_run_details h where h.start_time > now() - interval '7 days'),
               fd as materialized (select * from hist where status = 'failed' and end_time > now() - make_interval(hours => w_job)),
               fj as materialized (select distinct jobid from fd),
               last3 as (select f.jobid, bool_and(t.status = 'succeeded') ok, count(*) c from fj f
                           cross join lateral (select x.status from hist x where x.jobid = f.jobid and x.status in ('succeeded', 'failed')
                                               order by x.start_time desc limit 3) t group by f.jobid),
               runs as (select x.jobid, count(*) n from hist x where x.jobid in (select jobid from fj)
                          and x.end_time > now() - make_interval(hours => w_job) group by x.jobid)
          select j.jobname, coalesce(l.layer, 2) layer,
                 case when d.return_message ilike '%statement timeout%' then 'timeout' else 'failed' end kind,
                 count(*) n, min(d.end_time) first_at, max(d.end_time) last_at, left(max(d.return_message), 140) msg,
                 max(coalesce(rn.n, 0)) runs
          from fd d join cron.job j on j.jobid = d.jobid left join pipeline.platform_job_layers l on l.jobname = j.jobname
          left join last3 l3 on l3.jobid = d.jobid left join runs rn on rn.jobid = d.jobid
          where not (coalesce(l3.ok, false) and coalesce(l3.c, 0) = 3)
          group by j.jobid, j.jobname, l.layer, 3
          having count(*) >= coalesce((security.toolset_setting('scheduled_jobs', 'min_failures'))::text::int, 1)) z), '[]'::jsonb);

  -- Edge function calls that timed out (platform)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'edge_functions:0:timeout', 'layer', 0, 'toolset', 'edge_functions', 'kind', 'timeout', 'severity', 'warning',
      'title', format('%s edge function calls timed out or hit the worker limit', z.n),
      'detail', format('In the last %s hours.', w_edge), 'hint', 'The worker runs too long per call; lower its per-run limit.',
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select count(*) n, min(r.created) first_at, max(r.created) last_at from net._http_response r
          where r.created > now() - make_interval(hours => w_edge) and (r.timed_out or r.status_code in (504, 546))) z
    where z.n >= coalesce((security.toolset_setting('edge_functions', 'min_timeouts'))::text::int, 1)), '[]'::jsonb);

  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.scholarship_ai_fire_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_open int; v_max int; v_due int; v_sent int := 0;
begin
  -- v2.15.258: in Stop at limits, not past the daily guard or below the credit floor
  if not security.ai_use_allowed_v1('scholarship_ai') then return 0; end if;
  select calls_at_once into v_max from pipeline.scholarship_ai_extract_settings where id = 1;
  select count(*) into v_due from pipeline.scholarship_ai_queue q where (q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now());
  if v_due = 0 then return 0; end if;
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'scholarship_ai' and l.created_at > now() - interval '3 minutes'
     and not exists (select 1 from net._http_response r where r.id = l.request_id);
  while v_open + v_sent < coalesce(v_max, 3) and v_sent * 8 < v_due loop
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'scholarship_ai'));
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end $function$;

CREATE OR REPLACE FUNCTION security.central_ai_fire_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_open int; v_max int; v_due int; v_sent int := 0;
begin
  -- v2.15.258: in Stop at limits, not past the daily guard or below the credit floor
  if not security.ai_use_allowed_v1('central_ai') then return 0; end if;
  select calls_at_once into v_max from pipeline.central_ai_settings where id = 1 and enabled;
  select count(*) into v_due from pipeline.central_ai_queue q where (q.state = 'queued' or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3;
  if v_due = 0 or coalesce(v_max, 0) = 0 then return 0; end if;
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'central_ai' and l.created_at > now() - interval '3 minutes'
     and not exists (select 1 from net._http_response r where r.id = l.request_id);
  while v_open + v_sent < v_max and v_sent * 6 < v_due loop
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'central_ai', 'limit', 6));
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end $function$;

CREATE OR REPLACE FUNCTION public.admin_toolsets_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'toolsets', (select coalesce(jsonb_agg(jsonb_build_object('key', t.key, 'label', t.label, 'kind', t.kind, 'layers', t.layers, 'enforcement', t.enforcement, 'help', t.help,
        'updated_at', t.updated_at, 'reason', t.reason,
        'key_saved', (select p.vault_secret_id is not null from pipeline.layer2_acquisition_providers p where p.provider_key = t.provider_key),
        'switched_on', (select p.enabled from pipeline.layer2_acquisition_providers p where p.provider_key = t.provider_key),
        'plan', case when exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = t.key and s.key = 'plan_credits') then security.toolset_plan_status(t.key) end,
        'settings', (select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'help', s.help, 'kind', s.kind, 'value', s.value, 'min', s.min_value, 'max', s.max_value,
                        'unit', s.unit, 'section', s.section, 'updated_at', s.updated_at, 'reason', s.reason) order by s.sort, s.key), '[]'::jsonb)
                     from pipeline.platform_toolset_settings s where s.toolset_key = t.key)) order by t.sort), '[]'::jsonb)
      from pipeline.platform_toolsets t),
    'openrouter', jsonb_build_object(
      'balance', (select jsonb_build_object('remaining_usd', o.remaining_usd, 'observed_at', o.observed_at, 'total_credits', o.payload->'total_credits', 'total_usage', o.payload->'total_usage')
                  from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1),
      -- v2.15.258 (bug 12/10-01): the AI uses that run now, with their daily guards and the credit floor (Layer 3 retired)
      'credit_floor_usd', (security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric,
      'uses', (select coalesce(jsonb_agg(jsonb_build_object('use', g.use, 'label', g.label, 'spent_today', g.spent, 'guard', g.guard, 'calls', g.calls,
                    'allowed', security.ai_use_allowed_v1(g.use))), '[]'::jsonb) from security.ai_spend_today_v1() g),
      'spend_by_day', (select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'usd', d.usd, 'calls', d.calls) order by d.day), '[]'::jsonb)
                       from (select r.day, round(sum(r.usd), 4) usd, sum(r.calls) calls from (
                               select (x.at at time zone 'UTC')::date as day, sum(x.cost_usd) usd, count(*) calls from pipeline.scholarship_ai_extractions x where x.at > now() - interval '14 days' group by 1
                               union all select (x.created_at at time zone 'UTC')::date, sum(x.cost_usd), count(*) from pipeline.uni_adapter_drafts x where x.created_at > now() - interval '14 days' and coalesce(x.cost_usd, 0) > 0 group by 1
                               union all select (x.created_at at time zone 'UTC')::date, sum(x.cost_usd), count(*) from pipeline.central_ai_queue x where x.created_at > now() - interval '14 days' and coalesce(x.cost_usd, 0) > 0 group by 1
                               union all select (coalesce(x.decided_at, x.created_at) at time zone 'UTC')::date, sum(x.cost_usd), count(*) from pipeline.coverage_ai_match x where x.created_at > now() - interval '14 days' and coalesce(x.cost_usd, 0) > 0 group by 1) r
                             group by 1) d)),
    'job_layers', (select coalesce(jsonb_object_agg(l.jobname, l.layer), '{}'::jsonb) from pipeline.platform_job_layers l));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_provider_onboarding(p_action text DEFAULT 'read'::text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_ids uuid[]; v_n int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  -- v2.15.255: one university's journey: steps, tasks, AI drafts, and the scholarships found with their state
  if p_action = 'journey' then
    return (select jsonb_build_object('id', o.id, 'status', o.status, 'stop_reason', o.stop_reason, 'started_at', o.started_at, 'ai_attempts', coalesce((o.result->>'ai_attempts')::int, 0),
      'qualify', o.result->'qualify', 'held', o.result->'held', 'ready', o.result->'ready', 'central_pages', o.result->'central_pages', 'scholarship_search', o.result->'scholarships',
      'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'status', e.status, 'stop_reason', e.stop_reason, 'note', e.note) order by e.at), '[]'::jsonb)
                   from pipeline.provider_onboarding_events e where e.onboarding_id = o.id),
      'tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'kind', j.kind, 'title', j.title, 'state', j.state, 'created_at', j.created_at, 'finished_at', j.finished_at,
                   'note', left(coalesce(j.result->>'note', j.error, ''), 300)) order by j.created_at), '[]'::jsonb)
                  from pipeline.admin_jobs j where j.scope = o.provider_id::text and j.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute'),
      'drafts', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'status', d.status, 'created_at', d.created_at, 'updated_at', d.updated_at, 'samples', jsonb_array_length(coalesce(d.samples, '[]'::jsonb)),
                   'proposals', jsonb_array_length(coalesce(d.proposals, '[]'::jsonb)), 'model', d.model, 'cost_usd', d.cost_usd, 'reason', d.reason) order by d.created_at), '[]'::jsonb)
                  from pipeline.uni_adapter_drafts d where d.provider_id = o.provider_id and d.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute'),
      'scholarships', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'publication_status', s.publication_status, 'lifecycle_status', s.lifecycle_status,
                   'created_at', s.created_at, 'url', s.source_url) order by s.created_at desc), '[]'::jsonb)
                  from scholarship.scholarships s where s.provider_id = o.provider_id and s.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute'),
      'ai_waiting', (select count(*) from pipeline.scholarship_ai_queue q where q.provider_id = o.provider_id and q.state = 'queued'),
      'ai_read', (select coalesce(jsonb_object_agg(t.v, t.n), '{}'::jsonb) from (select coalesce(x.verdict, 'failed') v, count(*) n from pipeline.scholarship_ai_extractions x
                   where x.provider_id = o.provider_id and x.at >= coalesce(o.started_at, o.created_at) group by 1) t))
      from pipeline.provider_onboarding o where o.id = nullif(p_args->>'id', '')::uuid);
  end if;
  if p_action <> 'read' then
    if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    if p_action = 'start' then
      v_ids := case when p_args->>'scope' = 'no_adapter' then array(
                 select pr.id from catalogue.providers pr
                  where pr.lifecycle_status = 'active' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = pr.id)
                    and exists (select 1 from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active')
                    and not exists (select 1 from pipeline.uni_adapters a where a.provider_id = pr.id and a.enabled and coalesce(a.admit, false)))
               else array(select x::uuid from jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) x) end;
      if coalesce(cardinality(v_ids), 0) = 0 then raise exception 'choose universities'; end if;
      insert into pipeline.provider_onboarding(provider_id, source, requested_by, reason, priority)
      select i, case when p_args->>'scope' = 'no_adapter' then 'backfill' else 'manual' end, auth.uid(), v_reason,
             case when p_args->>'scope' = 'no_adapter' then (select least(count(*), 99999)::int from catalogue.courses c where c.provider_id = i and c.lifecycle_status = 'active') else 200000 end
        from unnest(v_ids) i
      on conflict do nothing;
      get diagnostics v_n = row_count;
    elsif p_action = 'stop' then
      update pipeline.provider_onboarding set status = 'cancelled', note = 'Stopped by a person: ' || v_reason, finished_at = now(), updated_at = now()
       where id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(p_args->'ids', '[]'::jsonb)) x)) and status not in ('done', 'cancelled');
      get diagnostics v_n = row_count;
    elsif p_action = 'retry' then
      update pipeline.provider_onboarding set status = case when stop_reason in ('capture_failed', 'proposal_failed') then 'course_pages' else 'website' end,
             stop_reason = null, attempts = 0, job_id = null, step_started_at = now(), note = 'Retried by a person: ' || v_reason, requested_by = auth.uid(), updated_at = now()
       where id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(p_args->'ids', '[]'::jsonb)) x)) and status = 'stopped';
      get diagnostics v_n = row_count;
    elsif p_action = 'settings' then
      update pipeline.provider_onboarding_settings set enabled = coalesce((p_args->>'enabled')::boolean, enabled), auto_start_new = coalesce((p_args->>'auto_start_new')::boolean, auto_start_new),
             max_active = coalesce((p_args->>'max_active')::int, max_active), run_as = case when (p_args->>'run_as_me')::boolean then auth.uid() else run_as end,
             changed_by = auth.uid(), changed_at = now(), reason = v_reason where id = 1;
      v_n := 1;
    else raise exception 'unknown action';
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('onboarding', p_action, coalesce(p_args->>'scope', ''), p_args || jsonb_build_object('count', v_n), auth.uid());
  end if;
  return jsonb_build_object(
    'can_manage', v_rank >= 6,
    'settings', (select to_jsonb(s) - 'id' from pipeline.provider_onboarding_settings s where s.id = 1),
    'counts', (select coalesce(jsonb_object_agg(t.status, t.n), '{}'::jsonb) from (select status, count(*) n from pipeline.provider_onboarding group by 1) t),
    'stops', (select coalesce(jsonb_object_agg(t.r, t.n), '{}'::jsonb) from (select stop_reason r, count(*) n from pipeline.provider_onboarding where status = 'stopped' group by 1) t),
    'without_adapter', (select count(*) from catalogue.providers pr where pr.lifecycle_status = 'active'
                          and exists (select 1 from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active')
                          and not exists (select 1 from pipeline.uni_adapters a where a.provider_id = pr.id and a.enabled and coalesce(a.admit, false))),
    -- v2.15.258: universities without an admitting adapter that are not in onboarding yet (what "Onboard all" would add), and the pace
    'not_queued', (select count(*) from catalogue.providers pr where pr.lifecycle_status = 'active'
                     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = pr.id)
                     and exists (select 1 from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active')
                     and not exists (select 1 from pipeline.uni_adapters a where a.provider_id = pr.id and a.enabled and coalesce(a.admit, false))
                     and not exists (select 1 from pipeline.provider_onboarding o where o.provider_id = pr.id and o.status not in ('done', 'cancelled'))),
    'pace', (select jsonb_build_object('finished_last_hour', count(distinct e.onboarding_id) filter (where e.at > now() - interval '1 hour'),
                                       'finished_last_6_hours', count(distinct e.onboarding_id))
               from pipeline.provider_onboarding_events e where e.at > now() - interval '6 hours' and e.status in ('waiting_admit', 'stopped', 'done')),
    'approvals_waiting', (select count(*) from pipeline.provider_fact_sources fs where fs.decision is null and fs.status = 'parsed' and fs.kind = 'fee_schedule')
                         + (select count(*) from pipeline.provider_policy_proposals pp where pp.status = 'proposed'),
    'rows', (select coalesce(jsonb_agg(x order by x->>'sort'), '[]'::jsonb) from (
       select jsonb_build_object('sort', lpad((case o.status when 'stopped' then 1 when 'waiting_admit' then 2 else 3 end)::text, 2, '0') || to_char(o.updated_at, 'YYYYMMDDHH24MISS'),
              'id', o.id, 'provider_id', o.provider_id, 'name', coalesce(nullif(pr.display_name, ''), pr.canonical_name), 'country', (select k.iso_alpha2 from ref.countries k where k.id = pr.country_id),
              'website', pr.website, 'status', o.status, 'stop_reason', o.stop_reason, 'note', o.note, 'source', o.source, 'job_id', o.job_id,
              'ready', o.result->'ready', 'held', o.result->'held', 'central_pages', o.result->'central_pages', 'scholarships', o.result->'scholarships'->'new_scholarships', 'ai_attempts', coalesce((o.result->>'ai_attempts')::int, 0),
              'scholarships_live', jsonb_build_object('found', (select count(*) from scholarship.scholarships s where s.provider_id = o.provider_id and s.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute'),
                 'published', (select count(*) from scholarship.scholarships s where s.provider_id = o.provider_id and s.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute' and s.publication_status = 'published'),
                 'waiting_ai', (select count(*) from pipeline.scholarship_ai_queue q where q.provider_id = o.provider_id and q.state = 'queued'),
                 'searched', o.result ? 'scholarships'),
              'courses', (select count(*) from catalogue.courses c where c.provider_id = o.provider_id and c.lifecycle_status = 'active'),
              'pages_read', (select count(*) from pipeline.coverage_course_pages pg where pg.provider_id = o.provider_id and pg.read_status = 'read'),
              'started_at', o.started_at, 'step_started_at', o.step_started_at, 'updated_at', o.updated_at, 'finished_at', o.finished_at, 'created_at', o.created_at) x
         from pipeline.provider_onboarding o join catalogue.providers pr on pr.id = o.provider_id
        where (p_args->>'status' is null or o.status = p_args->>'status' or (p_args->>'status' = 'active' and o.status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying', 'scholarships')))
          and (p_args->>'q' is null or coalesce(pr.display_name, pr.canonical_name) ilike '%' || (p_args->>'q') || '%')
        order by case o.status when 'stopped' then 1 when 'waiting_admit' then 2 else 3 end, o.updated_at desc
        limit least(greatest(coalesce((p_args->>'limit')::int, 200), 1), 500)) t));
end $function$;

update pipeline.provider_onboarding_settings set max_active = 100, changed_at = now(), reason = 'Platform Admin 12 Oct 2026 16:17: 100 universities at once' where id = 1;

do $post$
declare v_expected jsonb := '{"security.platform_notices_v1()": "e2d636a28c72efbe828eee385da67f00", "security.scholarship_ai_fire_v1()": "0a432552546d2031d1dcacbed71dc4bf", "security.central_ai_fire_v1()": "0a6dba98be083e4e5a91c613c2a8fd22", "public.admin_toolsets_read()": "75ed6d4d7150010164f985689a326fc4", "public.admin_provider_onboarding(text, jsonb)": "19e2f3bb5d42ebaeb48a4a0126c4f1d7"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.258 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
