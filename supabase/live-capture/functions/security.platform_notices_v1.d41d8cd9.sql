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
end $function$
