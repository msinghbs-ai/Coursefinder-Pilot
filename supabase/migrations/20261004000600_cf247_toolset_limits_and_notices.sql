-- CF-247 (4 Oct 2026, 14:30 AEDT). Decision 252. Platform Admin, 13:37: "stay put with openrouter credits for now and
-- dont cap it from ui or platform end. I want to collect logs, analyse and then top up when required. Plan notification
-- on ui for the layer which hits the toolset timeout or limits ... Ui control and variable settings is must, nothing
-- should be hardcoded which platform admin cant change from ui."
--   1. A register of the toolsets each layer depends on (OpenRouter, Firecrawl, Serper, ScrapingBee, scheduled jobs,
--      edge function calls) with their settings as rows the Platform Admin changes from the UI.
--   2. OpenRouter set to "observe only": the daily spend guards and the credit floor no longer stop Layer 3. They are
--      still read and shown; going past them raises a notice. Switching back to "stop at limits" is one change in the UI.
--      The routing worker's fixed US$5 credit floor (a constant in code) now comes from this register.
--   3. Notices per layer, worked out when the page is read from the logs that already exist (no new scheduled job):
--      OpenRouter refusals, low balance, spend past a guard, Firecrawl balance, scholarship and course-link caps,
--      scheduled jobs that time out or fail, edge function calls that time out, and vendor trials stopped by a limit.
--      A notice can be acknowledged; it comes back if it happens again after that.
-- Nothing here changes any admitted value.

create table if not exists pipeline.platform_toolsets (
  key text primary key,
  label text not null,
  kind text not null check (kind in ('ai', 'fetch', 'search', 'platform')),
  layers int[] not null default '{}',
  provider_key text,
  enforcement text check (enforcement in ('observe', 'stop')),
  help text not null default '',
  sort int not null default 100,
  reason text,
  updated_by uuid,
  updated_at timestamptz not null default now()
);

create table if not exists pipeline.platform_toolset_settings (
  toolset_key text not null references pipeline.platform_toolsets(key),
  key text not null,
  label text not null,
  help text not null default '',
  kind text not null check (kind in ('number', 'text', 'boolean', 'list')),
  value jsonb not null,
  min_value numeric,
  max_value numeric,
  unit text,
  sort int not null default 100,
  reason text,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  primary key (toolset_key, key)
);

create table if not exists pipeline.platform_job_layers (
  jobname text primary key,
  layer int not null check (layer between 0 and 4),
  updated_at timestamptz not null default now()
);

create table if not exists pipeline.platform_notice_acks (
  notice_key text primary key,
  acknowledged_at timestamptz not null default now(),
  acknowledged_by uuid,
  reason text
);

alter table pipeline.platform_toolsets enable row level security;
alter table pipeline.platform_toolset_settings enable row level security;
alter table pipeline.platform_job_layers enable row level security;
alter table pipeline.platform_notice_acks enable row level security;
revoke all on pipeline.platform_toolsets, pipeline.platform_toolset_settings, pipeline.platform_job_layers, pipeline.platform_notice_acks from anon, authenticated;

insert into pipeline.platform_toolsets(key, label, kind, layers, provider_key, enforcement, help, sort, reason) values
  ('openrouter', 'OpenRouter (AI models)', 'ai', '{3}', null, 'observe',
   'Observe only: the daily spend guards and the credit floor are shown and raise notices but do not stop Layer 3. Stop at limits: Layer 3 stops for the day at a spend guard and stops entirely below the credit floor. OpenRouter''s own key limits still apply either way.',
   10, 'Decision 252 (4 Oct 2026): observe and top up when required'),
  ('firecrawl', 'Firecrawl (page reading and site maps)', 'fetch', '{2}', 'firecrawl', null,
   'The monthly entitlement and the reserve it stops at are set on Scrapers & fetchers; the scholarship share is on Layer 2 › Scholarships.', 20, 'Decision 252'),
  ('serper', 'Serper (web search)', 'search', '{2}', 'serper', null,
   'On trial. Used to find a course''s official page, or a provider''s website, where the site map has none. Not used by any scheduled job until a trial has been reviewed and the Platform Admin switches it on.', 30, 'Decision 252: trial key'),
  ('scrapingbee', 'ScrapingBee (pages that need a browser)', 'fetch', '{2}', 'scrapingbee', null,
   'On trial. Used to read pages that need a browser to render or that refuse a direct read. Pages a provider''s robots file disallows are never sent. Not used by any scheduled job until a trial has been reviewed and the Platform Admin switches it on.', 40, 'Decision 252: trial key'),
  ('scheduled_jobs', 'Scheduled jobs (database)', 'platform', '{0,1,2,3,4}', null, null,
   'Each scheduled job runs inside the database, which stops any single statement after its time limit. A job that times out repeatedly needs a smaller batch, not a longer limit.', 90, 'Decision 252'),
  ('edge_functions', 'Edge function calls', 'platform', '{0}', null, null,
   'Workers run as edge functions with a wall-clock limit per call. Calls that time out are counted here.', 95, 'Decision 252')
on conflict (key) do nothing;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason) values
  ('openrouter', 'low_balance_warn_usd', 'Warn when the balance is below', 'A notice is raised on Layer 3 when the OpenRouter balance falls below this. It does not stop anything.', 'number', '10', 0, 1000, 'US$', 10, 'Decision 252'),
  ('openrouter', 'balance_stale_minutes', 'Warn when the balance has not been read for', 'The balance is read every few minutes; if no reading is newer than this, a notice is raised.', 'number', '30', 5, 1440, 'minutes', 20, 'Decision 252'),
  ('openrouter', 'notice_window_hours', 'Look back for refusals over', 'Calls OpenRouter refused (out of credit, key limit, rate limit) within this many hours raise a notice.', 'number', '24', 1, 168, 'hours', 30, 'Decision 252'),
  ('firecrawl', 'low_balance_warn_units', 'Warn when credits left this month are below', 'A notice is raised on Layer 2 when Firecrawl reports fewer credits left than this.', 'number', '10000', 0, 1000000, 'credits', 10, 'Decision 252'),
  ('scheduled_jobs', 'notice_window_hours', 'Look back over', 'Job runs that failed or timed out within this many hours raise a notice on the layer the job belongs to.', 'number', '24', 1, 168, 'hours', 10, 'Decision 252'),
  ('scheduled_jobs', 'min_failures', 'Raise a notice after', 'Number of failed runs of the same job within the look-back before a notice is raised.', 'number', '2', 1, 100, 'failed runs', 20, 'Decision 252'),
  ('edge_functions', 'notice_window_hours', 'Look back over', 'Edge function calls that timed out within this many hours raise a notice.', 'number', '6', 1, 24, 'hours', 10, 'Decision 252'),
  ('edge_functions', 'min_timeouts', 'Raise a notice after', 'Number of timed-out calls within the look-back before a notice is raised.', 'number', '3', 1, 1000, 'calls', 20, 'Decision 252')
on conflict (toolset_key, key) do nothing;

-- Which layer each scheduled job belongs to (data, changeable; a job not listed counts as Layer 2).
insert into pipeline.platform_job_layers(jobname, layer)
select j.jobname,
       coalesce((select s.layer from pipeline.scholarship_jobs s where s.jobname = j.jobname),
         case when j.jobname ~ '^(layer1-|coursefinder-layer1-|statistics-edition)' then 1
              when j.jobname ~ '^layer3-' then 3
              when j.jobname ~ '^(layer4-|fee-period-settle)' then 4
              when j.jobname ~ '^(admin-summary|cron-history|platform-|evidence-|search-refresh|consumer-reference|coursefinder-data-quality|coursefinder-platform|coursefinder-cf245|coursefinder-m2-3)' then 0
              else 2 end)
from cron.job j
on conflict (jobname) do nothing;

create or replace function security.toolset_setting(p_toolset text, p_key text) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select s.value from pipeline.platform_toolset_settings s where s.toolset_key = p_toolset and s.key = p_key
$f$;

-- A toolset with no row, or set to 'stop', is enforced: if the register cannot be read, the old behaviour holds.
create or replace function security.toolset_enforced(p_toolset text) returns boolean
language sql stable security definer set search_path = '' as $f$
  select coalesce((select t.enforcement is distinct from 'observe' from pipeline.platform_toolsets t where t.key = p_toolset), true)
$f$;

-- The routing worker reads its credit floor and whether to apply it from here (was a constant in the worker).
create or replace function public.svc_layer3_credit_policy() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return jsonb_build_object('enforce', security.toolset_enforced('openrouter'),
                            'floor_usd', (select min(b.credit_floor_usd) from pipeline.layer3_route_budget b));
end $f$;
revoke all on function public.svc_layer3_credit_policy() from public, anon, authenticated;
grant execute on function public.svc_layer3_credit_policy() to service_role;

-- OpenRouter observe mode in the three places that stop Layer 3 on spend or balance (md5-guarded).
do $g$ declare v_oid oid; v_def text; o text; n text; c int;
begin
  v_oid := 'public.layer3_fact_claim_service(text,integer,text,text)'::regprocedure;
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from '15fcf19b03b42539a912dd0ee1501bf7' then raise exception 'layer3_fact_claim_service changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  o := $x$if b.task_class is null or v_spent>=b.daily_usd_max then return$x$;
  n := $x$if b.task_class is null or (v_spent>=b.daily_usd_max and security.toolset_enforced('openrouter')) then return$x$;
  c := (length(v_def) - length(replace(v_def, o, ''))) / length(o); if c <> 1 then raise exception 'claim budget snippet found % times', c; end if;
  v_def := replace(v_def, o, n);
  o := $x$if v_credit.remaining_usd is null or v_credit.observed_at<now()-interval '20 minutes' or v_credit.remaining_usd<b.credit_floor_usd then$x$;
  n := $x$if security.toolset_enforced('openrouter') and (v_credit.remaining_usd is null or v_credit.observed_at<now()-interval '20 minutes' or v_credit.remaining_usd<b.credit_floor_usd) then$x$;
  c := (length(v_def) - length(replace(v_def, o, ''))) / length(o); if c <> 1 then raise exception 'claim floor snippet found % times', c; end if;
  v_def := replace(v_def, o, n);
  execute v_def;

  v_oid := 'public.layer3_dispatch_headroom_service(text)'::regprocedure;
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from 'c081a641b616aa3cc2859730468ff56a' then raise exception 'layer3_dispatch_headroom_service changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  o := $x$if v_budget is not null and v_day_cost>=v_budget then$x$;
  n := $x$if v_budget is not null and v_day_cost>=v_budget and security.toolset_enforced('openrouter') then$x$;
  c := (length(v_def) - length(replace(v_def, o, ''))) / length(o); if c <> 1 then raise exception 'headroom snippet found % times', c; end if;
  execute replace(v_def, o, n);

  v_oid := 'public.layer3_route_credit_floor_service(numeric,numeric)'::regprocedure;
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from 'ae1a34a92116682c5477cf22bf38f7bb' then raise exception 'layer3_route_credit_floor_service changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  o := $x$if p_remaining is null or p_remaining>=p_floor then return jsonb_build_object('stopped',false); end if;$x$;
  n := $x$if not security.toolset_enforced('openrouter') then return jsonb_build_object('stopped',false,'mode','observe'); end if;
  $x$ || o;
  c := (length(v_def) - length(replace(v_def, o, ''))) / length(o); if c <> 1 then raise exception 'floor snippet found % times', c; end if;
  execute replace(v_def, o, n);
end $g$;

-- Notices, worked out from the logs when read.
create or replace function security.platform_notices_v1() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare
  w_or int := coalesce((security.toolset_setting('openrouter', 'notice_window_hours'))::text::int, 24);
  w_job int := coalesce((security.toolset_setting('scheduled_jobs', 'notice_window_hours'))::text::int, 24);
  w_edge int := coalesce((security.toolset_setting('edge_functions', 'notice_window_hours'))::text::int, 6);
  v_or_mode text := coalesce((select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter'), 'stop');
  v jsonb := '[]'::jsonb;
begin
  -- OpenRouter refused calls (Layer 3)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'openrouter:3:refused:' || z.code, 'layer', 3, 'toolset', 'openrouter', 'kind', 'refused', 'severity', 'high',
      'title', case z.code when 'credit' then 'OpenRouter refused calls: out of credit'
                           when 'key_limit' then 'OpenRouter refused calls: the key''s own spending limit was reached'
                           when 'rate' then 'OpenRouter refused calls: rate limit'
                           else 'OpenRouter refused calls: key not accepted' end,
      'detail', format('%s work items in the last %s hours were released and will be retried.', z.n, w_or),
      'hint', case z.code when 'credit' then 'Top up the OpenRouter balance, then the released items are picked up again.'
                          when 'key_limit' then 'The limit is set on the key at OpenRouter (Workspaces › Keys), not in CourseFinder. Raise or clear it there; the items retry by themselves.'
                          when 'rate' then 'Usually clears by itself; the items retry.'
                          else 'Check the key on Platform settings › Environment & integrations.' end,
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select case when i.last_error ilike '%key limit exceeded%' or i.last_error ilike '%key weekly limit%' then 'key_limit'
                      when i.last_error ~ 'provider_402' then 'credit' when i.last_error ~ 'provider_429' then 'rate' else 'key' end code,
                 count(*) n, min(i.updated_at) first_at, max(i.updated_at) last_at
          from pipeline.layer3_work_items i
          where i.updated_at > now() - make_interval(hours => w_or)
            and (i.last_error ~ 'provider_(40[123]|429)' or i.last_error ilike '%key weekly limit%')
          group by 1) z where z.code is not null), '[]'::jsonb);

  -- OpenRouter balance (Layer 3)
  v := v || coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('key', 'openrouter:3:low_balance', 'layer', 3, 'toolset', 'openrouter', 'kind', 'low_balance', 'severity', 'warning',
      'title', format('OpenRouter balance is US$%s', round(o.remaining_usd, 2)),
      'detail', format('Below the warning level of US$%s. Layer 3 is set to %s.', security.toolset_setting('openrouter', 'low_balance_warn_usd'),
                       case v_or_mode when 'observe' then 'observe only, so it keeps running until OpenRouter refuses calls' else 'stop at limits' end),
      'hint', 'Top up when you are ready; nothing is stopped by this notice.',
      'count', 1, 'first_at', o.observed_at, 'last_at', o.observed_at) x
    from (select * from pipeline.layer3_openrouter_observations where kind = 'credits' order by observed_at desc limit 1) o
    where o.remaining_usd < coalesce((security.toolset_setting('openrouter', 'low_balance_warn_usd'))::text::numeric, 0)
    union all
    select jsonb_build_object('key', 'openrouter:3:not_observed', 'layer', 3, 'toolset', 'openrouter', 'kind', 'not_observed', 'severity', 'warning',
      'title', 'OpenRouter balance has not been read recently',
      'detail', format('Last reading %s.', coalesce(o.observed_at::text, 'never')),
      'hint', 'The balance is read by the route guard job on Layer 3; check it is running.',
      'count', 1, 'first_at', o.observed_at, 'last_at', now())
    from (select max(observed_at) observed_at from pipeline.layer3_openrouter_observations where kind = 'credits') o
    where o.observed_at is null or o.observed_at < now() - make_interval(mins => coalesce((security.toolset_setting('openrouter', 'balance_stale_minutes'))::text::int, 30))
  ) q), '[]'::jsonb);

  -- Spend past a daily guard today (Layer 3)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'openrouter:3:over_guard:' || z.task_class || ':' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD'), 'layer', 3, 'toolset', 'openrouter', 'kind', 'over_guard',
      'severity', case v_or_mode when 'observe' then 'info' else 'warning' end,
      'title', format('%s spent US$%s today, past its guard of US$%s', replace(z.task_class, '_', ' '), round(z.spent, 2), z.guard),
      'detail', case v_or_mode when 'observe' then 'Observe only: the task keeps running. This is recorded for the top-up review.' else 'The task has stopped until the UTC day changes.' end,
      'hint', 'Change the guard on Platform settings › Environment & integrations, or the mode on Models & services › Toolsets and limits.',
      'count', 1, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select b.task_class, b.daily_usd_max guard, sum(i.estimated_cost_usd) spent, min(i.created_at) first_at, max(i.created_at) last_at
          from pipeline.layer3_route_budget b join pipeline.layer3_interpretations i on i.task_class = b.task_class
          where i.created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'
          group by 1, 2 having sum(i.estimated_cost_usd) >= b.daily_usd_max) z), '[]'::jsonb);

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
    from (select j.jobname, coalesce(l.layer, 2) layer,
                 case when d.return_message ilike '%statement timeout%' then 'timeout' else 'failed' end kind,
                 count(*) n, min(d.end_time) first_at, max(d.end_time) last_at, left(max(d.return_message), 140) msg,
                 (select count(*) from cron.job_run_details d2 where d2.jobid = j.jobid and d2.end_time > now() - make_interval(hours => w_job)) runs
          from cron.job_run_details d join cron.job j on j.jobid = d.jobid left join pipeline.platform_job_layers l on l.jobname = j.jobname
          where d.status = 'failed' and d.end_time > now() - make_interval(hours => w_job)
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
end $f$;
revoke all on function security.platform_notices_v1() from public, anon, authenticated;

create or replace function public.admin_platform_notices_read(p_layer int default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  v := security.platform_notices_v1();
  begin
    v := v || coalesce(security.toolset_trial_notices_v1(), '[]'::jsonb);
  exception when undefined_function then null;
  end;
  return jsonb_build_object('can_manage', v_rank >= 6, 'generated_at', now(),
    'notices', coalesce((select jsonb_agg(n || jsonb_build_object('acknowledged', a.acknowledged_at is not null and a.acknowledged_at >= (n->>'last_at')::timestamptz,
                                                                   'acknowledged_at', a.acknowledged_at, 'ack_reason', a.reason)
                                          order by case n->>'severity' when 'high' then 0 when 'warning' then 1 else 2 end, (n->>'last_at') desc)
                         from jsonb_array_elements(v) n left join pipeline.platform_notice_acks a on a.notice_key = n->>'key'
                         where p_layer is null or (n->>'layer')::int = p_layer), '[]'::jsonb));
end $f$;
revoke all on function public.admin_platform_notices_read(int) from public, anon;
grant execute on function public.admin_platform_notices_read(int) to authenticated;

create or replace function public.admin_toolsets_read() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'toolsets', (select coalesce(jsonb_agg(jsonb_build_object('key', t.key, 'label', t.label, 'kind', t.kind, 'layers', t.layers, 'enforcement', t.enforcement, 'help', t.help,
        'updated_at', t.updated_at, 'reason', t.reason,
        'key_saved', (select p.vault_secret_id is not null from pipeline.layer2_acquisition_providers p where p.provider_key = t.provider_key),
        'settings', (select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'help', s.help, 'kind', s.kind, 'value', s.value, 'min', s.min_value, 'max', s.max_value,
                        'unit', s.unit, 'updated_at', s.updated_at, 'reason', s.reason) order by s.sort, s.key), '[]'::jsonb)
                     from pipeline.platform_toolset_settings s where s.toolset_key = t.key)) order by t.sort), '[]'::jsonb)
      from pipeline.platform_toolsets t),
    'openrouter', jsonb_build_object(
      'balance', (select jsonb_build_object('remaining_usd', o.remaining_usd, 'observed_at', o.observed_at, 'total_credits', o.payload->'total_credits', 'total_usage', o.payload->'total_usage')
                  from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1),
      'guards', (select coalesce(jsonb_agg(jsonb_build_object('task_class', b.task_class, 'daily_usd_max', b.daily_usd_max, 'credit_floor_usd', b.credit_floor_usd,
                    'spent_today', (select coalesce(sum(i.estimated_cost_usd), 0) from pipeline.layer3_interpretations i where i.task_class = b.task_class
                                    and i.created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC')) order by b.task_class), '[]'::jsonb)
                 from pipeline.layer3_route_budget b),
      'spend_by_day', (select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'usd', d.usd, 'calls', d.calls) order by d.day), '[]'::jsonb)
                       from (select (i.created_at at time zone 'UTC')::date as day, round(sum(i.estimated_cost_usd), 4) usd, count(*) calls
                             from pipeline.layer3_interpretations i where i.created_at > now() - interval '14 days' group by 1) d)),
    'job_layers', (select coalesce(jsonb_object_agg(l.jobname, l.layer), '{}'::jsonb) from pipeline.platform_job_layers l));
end $f$;
revoke all on function public.admin_toolsets_read() from public, anon;
grant execute on function public.admin_toolsets_read() to authenticated;

create or replace function public.admin_toolsets_write(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_set pipeline.platform_toolset_settings%rowtype; v_val jsonb; v_num numeric; v_before jsonb; v_t pipeline.platform_toolsets%rowtype;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'setting' then
    select * into v_set from pipeline.platform_toolset_settings where toolset_key = p_args->>'toolset' and key = p_args->>'key';
    if v_set.key is null then raise exception 'unknown setting'; end if;
    v_val := p_args->'value';
    if v_set.kind = 'number' then
      v_num := (v_val #>> '{}')::numeric;
      if v_num is null or (v_set.min_value is not null and v_num < v_set.min_value) or (v_set.max_value is not null and v_num > v_set.max_value) then
        raise exception 'value must be between % and %', v_set.min_value, v_set.max_value; end if;
      v_val := to_jsonb(v_num);
    elsif v_set.kind = 'boolean' then v_val := to_jsonb((v_val #>> '{}')::boolean);
    elsif v_set.kind = 'list' then
      if jsonb_typeof(v_val) <> 'array' then raise exception 'a list is needed'; end if;
    else v_val := to_jsonb(btrim(v_val #>> '{}'));
      if length(v_val #>> '{}') = 0 then raise exception 'text cannot be empty'; end if;
    end if;
    v_before := v_set.value;
    update pipeline.platform_toolset_settings set value = v_val, reason = v_reason, updated_by = auth.uid(), updated_at = now() where toolset_key = v_set.toolset_key and key = v_set.key;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'setting', v_set.toolset_key || '.' || v_set.key, jsonb_build_object('before', v_before, 'after', v_val, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'toolset', v_set.toolset_key, 'key', v_set.key, 'value', v_val);
  elsif p_action = 'enforcement' then
    select * into v_t from pipeline.platform_toolsets where key = p_args->>'toolset';
    if v_t.key is null or v_t.enforcement is null then raise exception 'this toolset has no enforcement mode'; end if;
    if p_args->>'enforcement' not in ('observe', 'stop') then raise exception 'enforcement must be observe or stop'; end if;
    update pipeline.platform_toolsets set enforcement = p_args->>'enforcement', reason = v_reason, updated_by = auth.uid(), updated_at = now() where key = v_t.key;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'enforcement', v_t.key, jsonb_build_object('before', v_t.enforcement, 'after', p_args->>'enforcement', 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'toolset', v_t.key, 'enforcement', p_args->>'enforcement');
  elsif p_action = 'job_layer' then
    if not exists (select 1 from cron.job where jobname = p_args->>'jobname') then raise exception 'unknown job'; end if;
    if (p_args->>'layer')::int not between 0 and 4 then raise exception 'layer must be 0 to 4'; end if;
    insert into pipeline.platform_job_layers(jobname, layer, updated_at) values (p_args->>'jobname', (p_args->>'layer')::int, now())
      on conflict (jobname) do update set layer = excluded.layer, updated_at = now();
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'job_layer', p_args->>'jobname', jsonb_build_object('layer', p_args->'layer', 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true);
  elsif p_action = 'ack' then
    if coalesce(p_args->>'notice_key', '') = '' then raise exception 'notice_key required'; end if;
    insert into pipeline.platform_notice_acks(notice_key, acknowledged_at, acknowledged_by, reason) values (p_args->>'notice_key', now(), auth.uid(), v_reason)
      on conflict (notice_key) do update set acknowledged_at = now(), acknowledged_by = auth.uid(), reason = v_reason;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'ack', p_args->>'notice_key', jsonb_build_object('reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action %', p_action;
end $f$;
revoke all on function public.admin_toolsets_write(text, jsonb) from public, anon;
grant execute on function public.admin_toolsets_write(text, jsonb) to authenticated;
