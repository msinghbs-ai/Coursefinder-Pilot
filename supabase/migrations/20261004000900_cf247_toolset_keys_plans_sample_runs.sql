-- CF-247 (4 Oct 2026, 15:00 AEDT). Decision 252 (amended). Platform Admin, 14:26: "Dont use trial terminology for the
-- toolset or programming the toolset. Api and limits that to be configured from ui will have trial key limits that can
-- be replaced by production api key with newer limits configured."
--   1. Serper and ScrapingBee are ordinary services with a key and the limits of that key's plan, all set in the UI.
--      Replacing the key (Environment & integrations) and entering the new plan's limits here is all a change of plan needs.
--   2. "Trials" become sample runs: tables, functions, settings and the worker are renamed (renames only, nothing lost).
--   3. New settings per service: plan name, credits in the plan, whether they renew monthly, the date credits are counted
--      from, a reserve kept back, and calls the plan allows at the same time. Sample runs stop when the key's plan is at
--      its reserve, with a notice on Layer 2.
--   4. Settings are grouped into sections on screen (Key and plan limits, How the service is used, Sample runs, Notices).
-- Nothing here changes any admitted value. No text value in this file contains a semicolon (the migration tool reads a
-- semicolon inside text as the end of a statement and asks for a confirmation this session cannot show).

alter table pipeline.toolset_trial_runs rename to toolset_sample_runs;
alter table pipeline.toolset_trial_items rename to toolset_sample_items;
alter index pipeline.toolset_trial_items_run rename to toolset_sample_items_run;
alter index pipeline.toolset_trial_items_subject rename to toolset_sample_items_subject;
do $r$ declare c record;
begin
  for c in select conrelid::regclass::text t, conname::text n from pg_constraint where conname like 'toolset\_trial\_%' loop
    execute format('alter table %s rename constraint %I to %I', c.t, c.n, replace(c.n, 'toolset_trial_', 'toolset_sample_'));
  end loop;
end $r$;

alter table pipeline.platform_toolset_settings add column if not exists section text not null default 'Notices';

update pipeline.platform_toolset_settings set key = case key when 'trial_countries' then 'sample_countries' when 'trial_sample_per_country' then 'sample_cases_per_country' when 'trial_max_credits_per_run' then 'sample_credits_per_run' when 'trial_seconds_per_call' then 'sample_seconds_per_call' when 'trial_concurrency' then 'sample_concurrency' else key end where toolset_key in ('serper', 'scrapingbee') and key like 'trial\_%';
update pipeline.platform_toolset_settings set section = 'Sample runs' where toolset_key in ('serper', 'scrapingbee') and key like 'sample\_%';
update pipeline.platform_toolset_settings set section = 'How the service is used' where toolset_key in ('serper', 'scrapingbee') and key in ('course_query', 'course_site_filter', 'provider_query', 'results_per_query', 'title_match_min', 'directory_hosts', 'render_js', 'premium_proxy', 'wait_ms');
update pipeline.platform_toolset_settings set section = 'Key and plan limits', sort = 60 where toolset_key in ('serper', 'scrapingbee') and key = 'usd_per_1k_credits';
update pipeline.platform_toolset_settings set label = 'Countries sampled', help = 'Country codes a sample run takes cases from. Any country with courses can be added.' where toolset_key in ('serper', 'scrapingbee') and key = 'sample_countries';
update pipeline.platform_toolset_settings set label = 'Cases per country', help = 'How many cases a sample run takes per country. Cases already run are skipped, so each run adds new evidence.' where toolset_key in ('serper', 'scrapingbee') and key = 'sample_cases_per_country';
update pipeline.platform_toolset_settings set label = 'Credits one run may use', help = 'A sample run stops when it has used this many credits. The key''s plan limits below apply as well.' where toolset_key in ('serper', 'scrapingbee') and key = 'sample_credits_per_run';
update pipeline.platform_toolset_settings set help = 'The worker stops taking new cases after this long and the run waits for Continue. Keep it under the edge function time limit.' where toolset_key in ('serper', 'scrapingbee') and key = 'sample_seconds_per_call';
update pipeline.platform_toolset_settings set help = 'Calls made at the same time within one worker call. Never more than the key''s plan allows (below).' where toolset_key in ('serper', 'scrapingbee') and key = 'sample_concurrency';
update pipeline.platform_toolset_settings set help = 'The price per 1,000 credits of the key''s plan, used for cost projections.', reason = 'Decision 252' where toolset_key in ('serper', 'scrapingbee') and key = 'usd_per_1k_credits';

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section) values
  ('serper', 'plan_name', 'Plan of the key in use', 'Whatever the vendor calls the plan of the key saved now. Change it when you replace the key.', 'text', '"Free plan"', null, null, null, 10, 'Decision 252: key supplied on the free plan', 'Key and plan limits'),
  ('serper', 'plan_credits', 'Credits in the plan', 'Credits the key''s plan gives. Work using this service stops at the reserve below. Check the figure on the vendor''s dashboard.', 'number', '2500', 0, 100000000, 'credits', 20, 'Decision 252: Serper free plan', 'Key and plan limits'),
  ('serper', 'plan_renews_monthly', 'Credits renew each month', 'Yes if the plan''s credits renew monthly (they are then counted from the first of the month), No if they are a one-off allowance counted from the date below.', 'boolean', 'false', null, null, null, 30, 'Decision 252', 'Key and plan limits'),
  ('serper', 'plan_counted_from', 'Count credits from', 'The date this key started (YYYY-MM-DD). Set it to the day you replace the key, so the new plan starts from nothing used.', 'text', '"2026-10-04"', null, null, null, 40, 'Decision 252', 'Key and plan limits'),
  ('serper', 'plan_reserve', 'Credits kept back', 'Work using this service stops when the plan has this many credits or fewer left.', 'number', '100', 0, 1000000, 'credits', 50, 'Decision 252', 'Key and plan limits'),
  ('serper', 'plan_max_concurrency', 'Calls the plan allows at the same time', 'The most calls the key''s plan accepts at once. Runs never exceed it.', 'number', '5', 1, 200, 'calls', 55, 'Decision 252', 'Key and plan limits'),
  ('scrapingbee', 'plan_name', 'Plan of the key in use', 'Whatever the vendor calls the plan of the key saved now. Change it when you replace the key.', 'text', '"Free plan"', null, null, null, 10, 'Decision 252: key supplied on the free plan', 'Key and plan limits'),
  ('scrapingbee', 'plan_credits', 'Credits in the plan', 'Credits the key''s plan gives (a page rendered in a browser costs 5, with premium proxies 25). Work using this service stops at the reserve below. Check the figure on the vendor''s dashboard.', 'number', '1000', 0, 100000000, 'credits', 20, 'Decision 252: ScrapingBee free plan', 'Key and plan limits'),
  ('scrapingbee', 'plan_renews_monthly', 'Credits renew each month', 'Yes if the plan''s credits renew monthly (they are then counted from the first of the month), No if they are a one-off allowance counted from the date below.', 'boolean', 'false', null, null, null, 30, 'Decision 252', 'Key and plan limits'),
  ('scrapingbee', 'plan_counted_from', 'Count credits from', 'The date this key started (YYYY-MM-DD). Set it to the day you replace the key, so the new plan starts from nothing used.', 'text', '"2026-10-04"', null, null, null, 40, 'Decision 252', 'Key and plan limits'),
  ('scrapingbee', 'plan_reserve', 'Credits kept back', 'Work using this service stops when the plan has this many credits or fewer left.', 'number', '50', 0, 1000000, 'credits', 50, 'Decision 252', 'Key and plan limits'),
  ('scrapingbee', 'plan_max_concurrency', 'Calls the plan allows at the same time', 'The most pages the key''s plan reads at once. Runs never exceed it.', 'number', '5', 1, 200, 'calls', 55, 'Decision 252', 'Key and plan limits')
on conflict (toolset_key, key) do nothing;

update pipeline.layer2_acquisition_providers set display_name = 'Serper (web search)', billing_config = billing_config - 'plan_tier', request_template = (request_template - 'trial_only') || '{"sample_runs_only": true}'::jsonb where provider_key = 'serper';
update pipeline.layer2_acquisition_providers set display_name = 'ScrapingBee (browser rendering)', billing_config = billing_config - 'plan_tier', request_template = (request_template - 'trial_only') || '{"sample_runs_only": true}'::jsonb where provider_key = 'scrapingbee';
update pipeline.platform_toolsets set help = 'Finds a course''s official page, or a provider''s website, where the site map has none. The key and its plan limits are set here and on Environment & integrations. Used only by sample runs until the Platform Admin switches it on for scheduled work.', reason = 'Decision 252 (amended 4 Oct 2026 14:26)' where key = 'serper';
update pipeline.platform_toolsets set help = 'Reads pages that need a browser to render or that refuse a direct read. Pages a provider''s robots file disallows are never sent. The key and its plan limits are set here and on Environment & integrations. Used only by sample runs until the Platform Admin switches it on for scheduled work.', reason = 'Decision 252 (amended 4 Oct 2026 14:26)' where key = 'scrapingbee';

-- The key's plan: credits, used since the counting date (any work on this service), left and the reserve.
create or replace function security.toolset_plan_status(p_toolset text) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_monthly boolean := coalesce((security.toolset_setting(p_toolset, 'plan_renews_monthly') #>> '{}')::boolean, false);
        v_from date; v_credits numeric := (security.toolset_setting(p_toolset, 'plan_credits') #>> '{}')::numeric;
        v_reserve numeric := coalesce((security.toolset_setting(p_toolset, 'plan_reserve') #>> '{}')::numeric, 0); v_used numeric;
begin
  begin v_from := (security.toolset_setting(p_toolset, 'plan_counted_from') #>> '{}')::date;
  exception when others then v_from := null;
  end;
  if v_monthly then v_from := greatest(coalesce(v_from, date_trunc('month', now())::date), date_trunc('month', now())::date); end if;
  select coalesce(sum(u.units), 0) into v_used from pipeline.coverage_vendor_usage u join pipeline.layer2_acquisition_providers p on p.id = u.acquisition_provider_id
   where p.provider_key = p_toolset and u.at >= coalesce(v_from, '2000-01-01'::date);
  return jsonb_build_object('name', security.toolset_setting(p_toolset, 'plan_name') #>> '{}', 'credits', v_credits, 'renews_monthly', v_monthly, 'counted_from', v_from,
    'used', v_used, 'left', case when v_credits is null then null else v_credits - v_used end, 'reserve', v_reserve,
    'max_concurrency', (security.toolset_setting(p_toolset, 'plan_max_concurrency') #>> '{}')::int,
    'at_reserve', v_credits is not null and v_credits - v_used <= v_reserve);
end $f$;
revoke all on function security.toolset_plan_status(text) from public, anon, authenticated;

alter function security.toolset_trial_backlog(text, text) rename to toolset_backlog;
alter function public.admin_toolset_trial_write(text, jsonb) rename to admin_toolset_sample_write;
alter function public.svc_toolset_trial_left(uuid) rename to svc_toolset_sample_left;
alter function public.svc_toolset_trial_release(uuid) rename to svc_toolset_sample_release;
alter function public.svc_toolset_trial_close(uuid, boolean) rename to svc_toolset_sample_close;
alter function public.svc_toolset_trial_record(uuid, jsonb) rename to svc_toolset_sample_record;
alter function public.svc_toolset_trial_next(uuid, int) rename to svc_toolset_sample_next;
alter function public.admin_toolset_trials_read(uuid) rename to admin_toolset_samples_read;
alter function security.toolset_trial_notices_v1() rename to toolset_sample_notices_v1;

create or replace function public.admin_toolset_sample_write(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_toolset text := p_args->>'toolset'; v_purpose text := p_args->>'purpose'; v_settings jsonb; v_countries text[]; v_n int;
        v_run uuid; v_cc text; v_added int := 0; v_r pipeline.toolset_sample_runs%rowtype; v_plan jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'start' then
    if not ((v_toolset = 'serper' and v_purpose in ('find_course_page', 'find_provider_site')) or (v_toolset = 'scrapingbee' and v_purpose = 'render_page')) then
      raise exception 'this service does not run that kind of sample'; end if;
    if not exists (select 1 from pipeline.layer2_acquisition_providers p where p.provider_key = v_toolset and p.vault_secret_id is not null) then
      raise exception 'save the % key on Platform settings › Environment & integrations first', v_toolset; end if;
    v_plan := security.toolset_plan_status(v_toolset);
    if (v_plan->>'at_reserve')::boolean then
      raise exception 'the % key''s plan has % credits left, at or below its reserve of %. Replace the key or raise the plan limits first', v_toolset, v_plan->>'left', v_plan->>'reserve'; end if;
    if exists (select 1 from pipeline.toolset_sample_runs r where r.toolset_key = v_toolset and r.status in ('ready', 'running', 'paused_time_limit')) then
      raise exception 'a % sample run is still open. Finish or stop it first', v_toolset; end if;
    select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb) into v_settings from pipeline.platform_toolset_settings s where s.toolset_key = v_toolset;
    select array_agg(x) into v_countries from jsonb_array_elements_text(v_settings->'sample_countries') x;
    insert into pipeline.toolset_sample_runs(toolset_key, purpose, countries, settings, reason, requested_by)
      values (v_toolset, v_purpose, coalesce(v_countries, '{}'), v_settings, v_reason, auth.uid()) returning id into v_run;
    foreach v_cc in array coalesce(v_countries, '{}') loop
      v_n := (v_settings->>'sample_cases_per_country')::int;
      insert into pipeline.toolset_sample_items(run_id, country, subject_key, course_id, provider_id, input)
      select v_run, v_cc, b.subject_key, b.course_id, b.provider_id, b.input
      from security.toolset_backlog(v_purpose, v_cc) b
      where not exists (select 1 from pipeline.toolset_sample_items i join pipeline.toolset_sample_runs r on r.id = i.run_id
                        where i.subject_key = b.subject_key and r.purpose = v_purpose and i.status = 'done')
      order by md5(b.subject_key || v_run::text) limit v_n;
      get diagnostics v_n = row_count; v_added := v_added + v_n;
    end loop;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'sample_start', v_toolset || ':' || v_purpose, jsonb_build_object('run_id', v_run, 'cases', v_added, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'run_id', v_run, 'cases', v_added);
  elsif p_action = 'stop' then
    select * into v_r from pipeline.toolset_sample_runs where id = (p_args->>'run_id')::uuid;
    if v_r.id is null then raise exception 'unknown run'; end if;
    update pipeline.toolset_sample_runs set status = 'stopped', status_note = v_reason, updated_at = now(), finished_at = now() where id = v_r.id and status in ('ready', 'running', 'paused_time_limit');
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'sample_stop', v_r.id::text, jsonb_build_object('reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action %', p_action;
end $f$;

create or replace function public.svc_toolset_sample_left(p_run_id uuid) returns int
language sql stable security definer set search_path = '' as $f$
  select count(*)::int from pipeline.toolset_sample_items where run_id = p_run_id and status <> 'done'
$f$;

create or replace function public.svc_toolset_sample_release(p_run_id uuid) returns int
language plpgsql security definer set search_path = '' as $f$
declare v_n int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  update pipeline.toolset_sample_items set leased_until = now() where run_id = p_run_id and status = 'leased';
  get diagnostics v_n = row_count;
  return v_n;
end $f$;

create or replace function public.svc_toolset_sample_close(p_run_id uuid, p_timed_out boolean) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_left int; v_new text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  perform public.svc_toolset_sample_release(p_run_id);
  v_left := public.svc_toolset_sample_left(p_run_id);
  v_new := case when v_left = 0 then 'done' when p_timed_out then 'paused_time_limit' else null end;
  if v_new = 'done' then
    update pipeline.toolset_sample_runs set status = 'done', finished_at = now(), updated_at = now() where id = p_run_id and status = 'running';
  elsif v_new = 'paused_time_limit' then
    update pipeline.toolset_sample_runs set status = 'paused_time_limit', status_note = format('%s cases left. The worker reached its time per call. Press Continue', v_left), updated_at = now() where id = p_run_id and status = 'running';
  end if;
  return jsonb_build_object('left', v_left, 'status', (select status from pipeline.toolset_sample_runs where id = p_run_id));
end $f$;

create or replace function public.svc_toolset_sample_record(p_item_id uuid, p_result jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_i pipeline.toolset_sample_items%rowtype; v_r pipeline.toolset_sample_runs%rowtype; v_credits numeric := coalesce((p_result->>'credits')::numeric, 0); v_cap numeric;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_i from pipeline.toolset_sample_items where id = p_item_id;
  if v_i.id is null then raise exception 'unknown item'; end if;
  select * into v_r from pipeline.toolset_sample_runs where id = v_i.run_id;
  v_cap := coalesce((v_r.settings->>'sample_credits_per_run')::numeric, 0);
  if p_result->>'outcome' = 'vendor_limit' then
    update pipeline.toolset_sample_items set leased_until = now() where id = p_item_id;
    update pipeline.toolset_sample_runs set status = 'stopped_vendor_limit', status_note = left(p_result->>'message', 300), finished_at = now(), updated_at = now() where id = v_r.id;
    return jsonb_build_object('continue', false);
  end if;
  update pipeline.toolset_sample_items set status = 'done', outcome = p_result->>'outcome', done_at = now() where id = p_item_id;
  update pipeline.toolset_sample_items set http_status = (p_result->>'http_status')::int, credits = v_credits, latency_ms = (p_result->>'latency_ms')::int where id = p_item_id;
  update pipeline.toolset_sample_items set result = p_result - 'outcome' - 'http_status' - 'credits' - 'latency_ms' where id = p_item_id;
  update pipeline.toolset_sample_runs set credits_used = credits_used + v_credits, updated_at = now() where id = v_r.id;
  if v_credits > 0 then
    insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, provider_id, url)
    select p.id, v_credits, 'sample_' || v_r.toolset_key, v_i.provider_id, coalesce(v_i.input->>'url', p_result->>'query')
    from pipeline.layer2_acquisition_providers p where p.provider_key = v_r.toolset_key;
  end if;
  if v_r.credits_used + v_credits >= v_cap then
    update pipeline.toolset_sample_runs set status = 'stopped_credit_cap', status_note = 'The run used the credits one run may use', finished_at = now() where id = v_r.id and status = 'running';
  end if;
  return jsonb_build_object('continue', v_r.credits_used + v_credits < v_cap and not (security.toolset_plan_status(v_r.toolset_key)->>'at_reserve')::boolean
    and (select status = 'running' from pipeline.toolset_sample_runs where id = v_r.id));
end $f$;

create or replace function public.svc_toolset_sample_next(p_run_id uuid, p_limit int) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_r pipeline.toolset_sample_runs%rowtype; v_items jsonb; v_ids uuid[]; v_plan jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_r from pipeline.toolset_sample_runs where id = p_run_id for update;
  if v_r.id is null or v_r.status not in ('ready', 'running', 'paused_time_limit') then return jsonb_build_object('items', '[]'::jsonb, 'status', v_r.status); end if;
  v_plan := security.toolset_plan_status(v_r.toolset_key);
  if (v_plan->>'at_reserve')::boolean then
    update pipeline.toolset_sample_runs set status = 'stopped_vendor_limit', status_note = format('The key''s plan has %s credits left, at or below its reserve of %s. Replace the key or raise the plan limits', v_plan->>'left', v_plan->>'reserve'), finished_at = now(), updated_at = now() where id = p_run_id;
    return jsonb_build_object('items', '[]'::jsonb, 'status', 'stopped_vendor_limit');
  end if;
  if v_r.credits_used >= coalesce((v_r.settings->>'sample_credits_per_run')::numeric, 0) then
    update pipeline.toolset_sample_runs set status = 'stopped_credit_cap', status_note = 'The run used the credits one run may use', finished_at = now(), updated_at = now() where id = p_run_id;
    return jsonb_build_object('items', '[]'::jsonb, 'status', 'stopped_credit_cap');
  end if;
  update pipeline.toolset_sample_runs set status = 'running', updated_at = now() where id = p_run_id;
  select array_agg(i.id) into v_ids from (
    select i.id from pipeline.toolset_sample_items i
    where i.run_id = p_run_id and (i.status = 'pending' or (i.status = 'leased' and i.leased_until < now()))
    order by i.country, i.id limit greatest(1, least(p_limit, 50)) for update skip locked) i;
  update pipeline.toolset_sample_items set status = 'leased', leased_until = now() + interval '10 minutes' where id = any(coalesce(v_ids, '{}'));
  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'country', i.country, 'input', i.input)), '[]'::jsonb) into v_items
    from pipeline.toolset_sample_items i where i.id = any(coalesce(v_ids, '{}'));
  return jsonb_build_object('items', v_items, 'status', 'running', 'purpose', v_r.purpose, 'settings', v_r.settings, 'plan', v_plan,
    'provider', (select public.layer2_provider_runtime_config(p.id) from pipeline.layer2_acquisition_providers p where p.provider_key = v_r.toolset_key));
end $f$;

create or replace function public.admin_toolset_samples_read(p_run_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'toolset', r.toolset_key, 'purpose', r.purpose, 'countries', r.countries, 'status', r.status, 'status_note', r.status_note,
                'credits_used', r.credits_used, 'reason', r.reason, 'created_at', r.created_at, 'finished_at', r.finished_at,
                'cases', (select count(*) from pipeline.toolset_sample_items i where i.run_id = r.id),
                'done', (select count(*) from pipeline.toolset_sample_items i where i.run_id = r.id and i.status = 'done'),
                'usd_per_1k_credits', r.settings->'usd_per_1k_credits', 'plan_name', r.settings->'plan_name') order by r.created_at desc), '[]'::jsonb)
             from (select * from pipeline.toolset_sample_runs order by created_at desc limit 30) r),
    'summary', (select coalesce(jsonb_agg(jsonb_build_object('toolset', z.toolset_key, 'purpose', z.purpose, 'country', z.country, 'outcome', z.outcome, 'n', z.n,
                    'credits', z.credits, 'avg_latency_ms', z.lat) order by z.toolset_key, z.purpose, z.country, z.n desc), '[]'::jsonb)
                from (select r.toolset_key, r.purpose, i.country, i.outcome, count(*) n, sum(i.credits) credits, round(avg(i.latency_ms)) lat
                      from pipeline.toolset_sample_items i join pipeline.toolset_sample_runs r on r.id = i.run_id
                      where i.status = 'done' and (p_run_id is null or r.id = p_run_id) group by 1, 2, 3, 4) z),
    'backlog', (select coalesce(jsonb_agg(jsonb_build_object('toolset', t.toolset, 'purpose', t.purpose, 'country', c.cc, 'n', (select count(*) from security.toolset_backlog(t.purpose, c.cc)))), '[]'::jsonb)
                from (values ('serper', 'find_course_page'), ('serper', 'find_provider_site'), ('scrapingbee', 'render_page')) t(toolset, purpose)
                cross join lateral (select jsonb_array_elements_text(coalesce(security.toolset_setting(t.toolset, 'sample_countries'), '[]'::jsonb)) cc) c),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('country', i.country, 'input', i.input, 'outcome', i.outcome, 'http_status', i.http_status, 'credits', i.credits,
                 'latency_ms', i.latency_ms, 'result', i.result, 'done_at', i.done_at) order by i.country, i.outcome, i.done_at), '[]'::jsonb)
              from pipeline.toolset_sample_items i where p_run_id is not null and i.run_id = p_run_id and i.status = 'done'));
end $f$;

create or replace function security.toolset_sample_notices_v1() returns jsonb
language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select jsonb_build_object(
      'key', 'sample:2:' || r.status || ':' || r.id, 'layer', 2, 'toolset', r.toolset_key, 'kind', r.status,
      'severity', case when r.status = 'stopped_vendor_limit' then 'high' else 'warning' end,
      'title', case r.status when 'stopped_vendor_limit' then format('%s sample run stopped: the key or its plan limit', initcap(r.toolset_key))
                             when 'stopped_credit_cap' then format('%s sample run used its credits (%s)', initcap(r.toolset_key), r.credits_used)
                             else format('%s sample run paused at the time limit per call', initcap(r.toolset_key)) end,
      'detail', coalesce(r.status_note, ''),
      'hint', case r.status when 'stopped_vendor_limit' then 'Replace the key on Environment & integrations and enter the new plan''s limits on Models & services › Toolsets and limits.'
                            when 'stopped_credit_cap' then 'Raise "Credits one run may use" on Models & services › Toolsets and limits, then start another run.'
                            else 'Press Continue on Models & services › Toolsets and limits.' end,
      'count', 1, 'first_at', r.updated_at, 'last_at', r.updated_at) x
    from pipeline.toolset_sample_runs r
    where r.status in ('stopped_vendor_limit', 'stopped_credit_cap', 'paused_time_limit') and r.updated_at > now() - interval '7 days'
    union all
    select jsonb_build_object(
      'key', 'plan:2:at_reserve:' || t.key || ':' || coalesce(p->>'counted_from', ''), 'layer', 2, 'toolset', t.key, 'kind', 'plan_at_reserve', 'severity', 'high',
      'title', format('%s key''s plan is at its reserve (%s of %s credits used)', initcap(t.key), p->>'used', p->>'credits'),
      'detail', format('Plan: %s. Work using this service has stopped.', coalesce(p->>'name', 'not named')),
      'hint', 'Replace the key on Environment & integrations and enter the new plan''s limits on Models & services › Toolsets and limits.',
      'count', 1, 'first_at', now(), 'last_at', now())
    from pipeline.platform_toolsets t cross join lateral (select security.toolset_plan_status(t.key) p) s
    where t.key in ('serper', 'scrapingbee') and (p->>'at_reserve')::boolean) q
$f$;

create or replace function public.admin_platform_notices_read(p_layer int default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  v := security.platform_notices_v1() || coalesce(security.toolset_sample_notices_v1(), '[]'::jsonb);
  return jsonb_build_object('can_manage', v_rank >= 6, 'generated_at', now(),
    'notices', coalesce((select jsonb_agg(n || jsonb_build_object('acknowledged', a.acknowledged_at is not null and a.acknowledged_at >= (n->>'last_at')::timestamptz,
                                                                   'acknowledged_at', a.acknowledged_at, 'ack_reason', a.reason)
                                          order by case n->>'severity' when 'high' then 0 when 'warning' then 1 else 2 end, (n->>'last_at') desc)
                         from jsonb_array_elements(v) n left join pipeline.platform_notice_acks a on a.notice_key = n->>'key'
                         where p_layer is null or (n->>'layer')::int = p_layer), '[]'::jsonb));
end $f$;

create or replace function public.admin_toolsets_read() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
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
      'guards', (select coalesce(jsonb_agg(jsonb_build_object('task_class', b.task_class, 'daily_usd_max', b.daily_usd_max, 'credit_floor_usd', b.credit_floor_usd,
                    'spent_today', (select coalesce(sum(i.estimated_cost_usd), 0) from pipeline.layer3_interpretations i where i.task_class = b.task_class
                                    and i.created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC')) order by b.task_class), '[]'::jsonb)
                 from pipeline.layer3_route_budget b),
      'spend_by_day', (select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'usd', d.usd, 'calls', d.calls) order by d.day), '[]'::jsonb)
                       from (select (i.created_at at time zone 'UTC')::date as day, round(sum(i.estimated_cost_usd), 4) usd, count(*) calls
                             from pipeline.layer3_interpretations i where i.created_at > now() - interval '14 days' group by 1) d)),
    'job_layers', (select coalesce(jsonb_object_agg(l.jobname, l.layer), '{}'::jsonb) from pipeline.platform_job_layers l));
end $f$;
