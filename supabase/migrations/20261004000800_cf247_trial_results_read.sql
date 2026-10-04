-- CF-247 Decision 252: trial results by country and outcome, the backlog each trial samples from, and every case of a run.
create or replace function public.admin_toolset_trials_read(p_run_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'toolset', r.toolset_key, 'purpose', r.purpose, 'countries', r.countries, 'status', r.status, 'status_note', r.status_note,
                'credits_used', r.credits_used, 'reason', r.reason, 'created_at', r.created_at, 'finished_at', r.finished_at,
                'cases', (select count(*) from pipeline.toolset_trial_items i where i.run_id = r.id),
                'done', (select count(*) from pipeline.toolset_trial_items i where i.run_id = r.id and i.status = 'done'),
                'usd_per_1k_credits', r.settings->'usd_per_1k_credits') order by r.created_at desc), '[]'::jsonb)
             from (select * from pipeline.toolset_trial_runs order by created_at desc limit 30) r),
    'summary', (select coalesce(jsonb_agg(jsonb_build_object('toolset', z.toolset_key, 'purpose', z.purpose, 'country', z.country, 'outcome', z.outcome, 'n', z.n,
                    'credits', z.credits, 'avg_latency_ms', z.lat) order by z.toolset_key, z.purpose, z.country, z.n desc), '[]'::jsonb)
                from (select r.toolset_key, r.purpose, i.country, i.outcome, count(*) n, sum(i.credits) credits, round(avg(i.latency_ms)) lat
                      from pipeline.toolset_trial_items i join pipeline.toolset_trial_runs r on r.id = i.run_id
                      where i.status = 'done' and (p_run_id is null or r.id = p_run_id) group by 1, 2, 3, 4) z),
    'backlog', (select coalesce(jsonb_agg(jsonb_build_object('toolset', t.toolset, 'purpose', t.purpose, 'country', c.cc, 'n', (select count(*) from security.toolset_trial_backlog(t.purpose, c.cc)))), '[]'::jsonb)
                from (values ('serper', 'find_course_page'), ('serper', 'find_provider_site'), ('scrapingbee', 'render_page')) t(toolset, purpose)
                cross join lateral (select jsonb_array_elements_text(coalesce(security.toolset_setting(t.toolset, 'trial_countries'), '[]'::jsonb)) cc) c),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('country', i.country, 'input', i.input, 'outcome', i.outcome, 'http_status', i.http_status, 'credits', i.credits,
                 'latency_ms', i.latency_ms, 'result', i.result, 'done_at', i.done_at) order by i.country, i.outcome, i.done_at), '[]'::jsonb)
              from pipeline.toolset_trial_items i where p_run_id is not null and i.run_id = p_run_id and i.status = 'done'));
end $f$;
revoke all on function public.admin_toolset_trials_read(uuid) from public, anon;
grant execute on function public.admin_toolset_trials_read(uuid) to authenticated;

-- Trial runs stopped by a limit become Layer 2 notices (read by admin_platform_notices_read).
create or replace function security.toolset_trial_notices_v1() returns jsonb
language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', 'trial:2:' || r.status || ':' || r.id, 'layer', 2, 'toolset', r.toolset_key, 'kind', r.status,
    'severity', case when r.status = 'stopped_vendor_limit' then 'high' else 'warning' end,
    'title', case r.status when 'stopped_vendor_limit' then format('%s trial stopped: the service refused calls', initcap(r.toolset_key))
                           when 'stopped_credit_cap' then format('%s trial stopped at its credit allowance (%s credits)', initcap(r.toolset_key), r.credits_used)
                           else format('%s trial paused at the time limit per call', initcap(r.toolset_key)) end,
    'detail', coalesce(r.status_note, ''),
    'hint', case r.status when 'stopped_vendor_limit' then 'The trial plan''s own limit or the key was refused. Check the account with the vendor.'
                          when 'stopped_credit_cap' then 'Raise "Credits a run may use" on Models & services › Toolsets and limits, then start a new run.'
                          else 'Press Continue on Models & services › Toolsets and limits.' end,
    'count', 1, 'first_at', r.updated_at, 'last_at', r.updated_at)), '[]'::jsonb)
  from pipeline.toolset_trial_runs r
  where r.status in ('stopped_vendor_limit', 'stopped_credit_cap', 'paused_time_limit') and r.updated_at > now() - interval '7 days'
$f$;
revoke all on function security.toolset_trial_notices_v1() from public, anon, authenticated;
