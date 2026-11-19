-- CF-247 Decision 253 (4 Oct 2026, 19:16). Platform Admin: "I don't understand how to test the adapters, there is no
-- toggle or uni based adapters". The Firecrawl work panel (where the adapters are) took about 7 seconds to work out its
-- figures, against an 8-second limit for a signed-in user, so under load it did not load at all. Its figures are now
-- kept in small tables refreshed by scheduled jobs (targets every minute, course figures every 5 minutes) and the panel
-- reads them at once. Starting a run reads the same tables. The panel also lists the university adapters on their own.
-- No text value in this file contains a semicolon.

alter table pipeline.firecrawl_target_cache add column if not exists country text;
alter table pipeline.firecrawl_target_cache add column if not exists name text;
alter table pipeline.firecrawl_target_cache add column if not exists domain text;
alter table pipeline.firecrawl_target_cache add column if not exists rule_match boolean;
alter table pipeline.firecrawl_target_cache add column if not exists override_reason text;
alter table pipeline.firecrawl_target_cache add column if not exists courses int;
alter table pipeline.firecrawl_target_cache add column if not exists stats jsonb;
alter table pipeline.firecrawl_target_cache add column if not exists stats_at timestamptz;

create table if not exists pipeline.firecrawl_panel_figures (
  id int primary key default 1 check (id = 1),
  backlog jsonb not null default '{}'::jsonb,
  refreshed_at timestamptz not null default now()
);
alter table pipeline.firecrawl_panel_figures enable row level security;
revoke all on pipeline.firecrawl_panel_figures from anon, authenticated;

-- Every minute: the targets with their names, countries and websites.
create or replace function security.firecrawl_targets_refresh_v1() returns int
language plpgsql security definer set search_path = '' as $f$
declare n int;
begin
  insert into pipeline.firecrawl_target_cache(provider_id, included, refreshed_at, country, name, domain, rule_match, override_reason, courses)
    select t.provider_id, t.included, now(), t.country, t.name, t.domain, t.rule_match, t.override_reason, t.courses from security.firecrawl_targets_v1() t
  on conflict (provider_id) do update set included = excluded.included, refreshed_at = now(), country = excluded.country, name = excluded.name, domain = excluded.domain, rule_match = excluded.rule_match, override_reason = excluded.override_reason, courses = excluded.courses where pipeline.firecrawl_target_cache.provider_id = excluded.provider_id;
  get diagnostics n = row_count;
  update pipeline.firecrawl_target_cache set included = false, refreshed_at = now() where refreshed_at < now() - interval '30 seconds' and included;
  return n;
end $f$;
revoke all on function security.firecrawl_targets_refresh_v1() from public, anon, authenticated;

-- The targets as kept (fast). Used by the panel, the backlog and the worker.
create or replace function security.firecrawl_targets_fast() returns table (provider_id uuid, country text, name text, courses int, rule_match boolean, included boolean, override_reason text, domain text)
language sql stable security definer set search_path = '' as $f$
  select c.provider_id, c.country, c.name, c.courses, c.rule_match, c.included, c.override_reason, c.domain from pipeline.firecrawl_target_cache c where c.name is not null
$f$;
revoke all on function security.firecrawl_targets_fast() from public, anon, authenticated;

-- Every 5 minutes: what each target has now, and what each use case would take.
create or replace function security.firecrawl_panel_refresh_v1() returns int
language plpgsql security definer set search_path = '' as $f$
declare n int;
begin
  with c as (
    select t.provider_id, jsonb_build_object('courses', count(*),
           'confirmed', count(*) filter (where pg.status = 'bound' and pg.read_status = 'read' and pg.identity_basis is not null),
           'unreadable', count(*) filter (where pg.status in ('bound', 'ambiguous') and pg.read_status in ('needs_render', 'blocked', 'fetch_failed', 'too_thin', 'robots_disallowed')),
           'no_page', count(*) filter (where pg.course_id is null or pg.status not in ('bound', 'ambiguous')),
           'adapter_confirmed', count(*) filter (where pg.read_status = 'read' and pg.identity_basis in ('adapter_code', 'adapter_title')),
           'waiting_read', count(*) filter (where pg.status = 'bound' and (pg.read_status is null or pg.read_status = 'needs_render')),
           'intakes', count(*) filter (where exists (select 1 from catalogue.course_intakes i where i.course_id = cc.id and coalesce(i.status, 'active') = 'active')),
           'english', count(*) filter (where exists (select 1 from catalogue.course_english_requirements e where e.course_id = cc.id and coalesce(e.status, 'active') = 'active')),
           'any_fee', count(*) filter (where exists (select 1 from catalogue.course_fees f where f.course_id = cc.id and coalesce(f.audience, '') ~* 'int'))) s
    from pipeline.firecrawl_target_cache t join catalogue.courses cc on cc.provider_id = t.provider_id and cc.lifecycle_status = 'active'
    left join pipeline.coverage_course_pages pg on pg.course_id = cc.id
    where t.name is not null
    group by t.provider_id
  )
  update pipeline.firecrawl_target_cache t set stats = c.s, stats_at = now() from c where c.provider_id = t.provider_id;
  get diagnostics n = row_count;
  insert into pipeline.firecrawl_panel_figures(id, backlog, refreshed_at)
    values (1, jsonb_build_object('read_page', (select count(*) from security.firecrawl_backlog_v1('read_page')), 'find_page', (select count(*) from security.firecrawl_backlog_v1('find_page'))), now())
  on conflict (id) do update set backlog = excluded.backlog, refreshed_at = now() where pipeline.firecrawl_panel_figures.id = 1;
  return n;
end $f$;
revoke all on function security.firecrawl_panel_refresh_v1() from public, anon, authenticated;

-- The backlog reads the kept targets (fast) instead of working the rule out again.
create or replace function security.firecrawl_backlog_v1(p_use_case text) returns table (course_id uuid, provider_id uuid, country text, url text, input jsonb)
language plpgsql stable security definer set search_path = '' as $f$
declare v_statuses text[]; v_retry boolean; v_like text; v_skip text;
begin
  select coalesce(array_agg(e), '{}') into v_statuses from jsonb_array_elements_text(coalesce(security.firecrawl_setting('read_statuses'), '[]'::jsonb)) e;
  v_retry := coalesce((security.firecrawl_setting('find_retry_refused') #>> '{}')::boolean, false);
  v_like := coalesce(nullif(btrim(security.firecrawl_setting('read_url_pattern') #>> '{}'), ''), '.');
  v_skip := nullif(btrim(coalesce(security.firecrawl_setting('read_skip_url_pattern') #>> '{}', '')), '');
  if p_use_case = 'read_page' then
    return query
    select pg.course_id, pg.provider_id, t.country, pg.url,
           jsonb_build_object('course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'page_status', pg.status, 'earlier_read', pg.read_status, 'earlier_http', pg.http_status)
    from security.firecrawl_targets_fast() t
    join pipeline.coverage_course_pages pg on pg.provider_id = t.provider_id
    join catalogue.courses c on c.id = pg.course_id
    where t.included and c.lifecycle_status = 'active' and pg.status in ('bound', 'ambiguous') and pg.read_status = any(v_statuses)
      and pg.url is not null and coalesce(pg.http_status, 0) not in (404, 410) and pg.evidence_id is null
      and pg.url ~* v_like and (v_skip is null or pg.url !~* v_skip);
  elsif p_use_case = 'find_page' then
    return query
    select c.id, t.provider_id, t.country, null::text,
           jsonb_build_object('course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'provider', t.name, 'domain', t.domain,
                              'earlier_url', pg.url, 'earlier_status', pg.status,
                              'refind', coalesce(pg.status in ('bound', 'ambiguous'), false))
    from security.firecrawl_targets_fast() t
    join catalogue.courses c on c.provider_id = t.provider_id
    left join pipeline.coverage_course_pages pg on pg.course_id = c.id
    where t.included and t.domain is not null and c.lifecycle_status = 'active'
      and (pg.course_id is null or pg.status not in ('bound', 'ambiguous')
           or (pg.read_status = any(v_statuses) and pg.evidence_id is null and (pg.url !~* v_like or (v_skip is not null and pg.url ~* v_skip))))
      and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field = 'official_url')
      and (pg.read_status is not distinct from 'refused_host'
           or not exists (select 1 from pipeline.search_pass_links l where l.course_id = c.id and (l.state in ('found', 'verified') or (l.state = 'none' and not v_retry))));
  end if;
end $f$;
revoke all on function security.firecrawl_backlog_v1(text) from public, anon, authenticated;

-- The panel: everything read from the kept figures, plus the university adapters listed on their own.
create or replace function public.admin_firecrawl_read() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_fc uuid; v_obs record; v_fig record;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;
  select p.id into v_fc from pipeline.layer2_acquisition_providers p where p.provider_key = 'firecrawl';
  select o.* into v_obs from pipeline.vendor_credit_observations o where o.provider_id = v_fc order by o.observed_at desc limit 1;
  select f.* into v_fig from pipeline.firecrawl_panel_figures f where f.id = 1;
  return jsonb_build_object(
    'can_manage', coalesce(v_rank, 0) >= 6,
    'figures_at', v_fig.refreshed_at,
    'plan', jsonb_build_object('budget', security.layer2_provider_budget_status(v_fc, 1), 'vendor', case when v_obs.provider_id is null then null else jsonb_build_object('observed_at', v_obs.observed_at, 'plan_credits', v_obs.plan_units, 'remaining', v_obs.remaining_units, 'period_start', v_obs.raw->>'billing_period_start', 'period_end', v_obs.period_end) end),
    'targets', coalesce((select jsonb_agg(jsonb_build_object('provider_id', t.provider_id, 'country', t.country, 'name', t.name, 'domain', t.domain, 'rule_match', t.rule_match, 'included', t.included, 'override_reason', t.override_reason)
                 || coalesce(t.stats, jsonb_build_object('courses', t.courses))
                 || jsonb_build_object('adapter', case when a.provider_id is null then 'none' when a.admit then 'admitting' when a.enabled then 'testing' else 'off' end,
                                       'requests_open', (select count(*) from pipeline.uni_adapter_requests r where r.provider_id = t.provider_id and r.status = 'open'))
               order by (a.provider_id is not null) desc, t.included desc, t.country, coalesce(t.courses, 0) desc)
               from pipeline.firecrawl_target_cache t left join pipeline.uni_adapters a on a.provider_id = t.provider_id where t.name is not null), '[]'::jsonb),
    'backlog', coalesce(v_fig.backlog, '{}'::jsonb),
    'runs', coalesce((select jsonb_agg(to_jsonb(r) - 'settings' order by r.created_at desc) from (select * from pipeline.firecrawl_runs order by created_at desc limit 12) r), '[]'::jsonb),
    'spend', coalesce((select jsonb_agg(jsonb_build_object('purpose', s.purpose, 'target', s.target, 'units', s.units) order by s.units desc) from (
               select u.purpose, coalesce(tc.included, false) target, sum(u.units) units
               from pipeline.coverage_vendor_usage u left join pipeline.firecrawl_target_cache tc on tc.provider_id = u.provider_id
               where u.acquisition_provider_id = v_fc and u.at >= coalesce((v_obs.raw->>'billing_period_start')::timestamptz, date_trunc('month', now()))
               group by 1, 2) s), '[]'::jsonb)
  );
end $f$;
revoke all on function public.admin_firecrawl_read() from public, anon;
grant execute on function public.admin_firecrawl_read() to authenticated;

select security.firecrawl_targets_refresh_v1();
select security.firecrawl_panel_refresh_v1();
select cron.schedule('firecrawl-panel-figures', '*/5 * * * *', 'select security.firecrawl_panel_refresh_v1()');
insert into pipeline.platform_job_layers(jobname, layer, updated_at) values ('firecrawl-panel-figures', 2, now()) on conflict (jobname) do nothing;
