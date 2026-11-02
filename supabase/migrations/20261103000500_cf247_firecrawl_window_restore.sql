-- CF-247: end the temporary Firecrawl unlimited window and restore the normal approved limits (Integration Controller, 2 Nov 2026 ~23:50 AEDT).
-- Why a migration: the Platform Admin authorised unlimited Firecrawl use until the credits expire (2 Nov 16:39; Admin
--   docs/platform/nz-enrichment-brief/2026-11-02-firecrawl-unlimited-authority-1639.md). The planned 03:05 restore needs a direct database write,
--   and direct writes need the Platform Admin present to approve each prompt (cancelled automatically at 23:46). If nothing restored the limits,
--   the platform would keep spending without the daily budget into the new vendor period from 3 Nov 02:57. The 23:24 direction requires normal
--   approved limits after the window and "no unlimited spending". This release restores them now; the remaining window is given up
--   (most credits would expire unused anyway).
-- Every value restored is the value recorded before the window in pipeline.admin_control_events #28625 (window), #28629 (read_statuses,
--   run_concurrency), #28631 (lanes), #28658 (scholarship lane) and #28668 (scholarship lifetime cap). Each update only acts when the setting
--   still holds tonight's value, so a value someone changed since is left alone and reported.
-- Jobs: coverage-discover and coverage-discover-2 return to paused (their state before the window); coverage-read and coverage-read-2 were
--   already active before the window and stay active.
-- Firecrawl runs still 'running' are stopped (existing status 'stopped'); nothing is deleted.
-- Not restored here: scholarship_min_courses stays at its pre-window value 30 (the 23:24 direction proposes replacing it; that needs approval).
-- Replaces: nothing (setting values only)
-- Retires: nothing
-- Rollback: re-apply the window values from event #28625/#28631/#28658/#28668 by a recorded Platform Admin decision; no schema change to undo.
-- Nothing dropped, deleted or renamed. No new job. Consumer API untouched (G3).

do $restore$
declare v_changed jsonb := '{}'::jsonb; v_kept jsonb := '{}'::jsonb; r record; v_n int;
  v_reason text := 'Firecrawl unlimited window ended by release (Integration Controller 2 Nov 2026 ~23:50): normal approved limits restored from the before values in admin_control_events #28625 #28629 #28631 #28658 #28668';
begin
  for r in select * from (values
      ('firecrawl', 'daily_budget_on',                    'false'::jsonb,  'true'::jsonb),
      ('firecrawl', 'target_only',                        'false'::jsonb,  'true'::jsonb),
      ('firecrawl', 'central_refresh_days',               '1'::jsonb,      '30'::jsonb),
      ('firecrawl', 'find_retry_refused',                 'true'::jsonb,   'false'::jsonb),
      ('firecrawl', 'search_stop_after',                  '1000'::jsonb,   '30'::jsonb),
      ('firecrawl', 'run_concurrency',                    '12'::jsonb,     '12'::jsonb),
      ('firecrawl', 'autobuild_per_day',                  '200'::jsonb,    '25'::jsonb),
      ('firecrawl', 'ondemand_credits_per_day',           '20000'::jsonb,  '2000'::jsonb),
      ('firecrawl', 'find_credits_per_run',               '500000'::jsonb, '15000'::jsonb),
      ('firecrawl', 'read_credits_per_run',               '500000'::jsonb, '15000'::jsonb),
      ('firecrawl', 'read_statuses',                      '["needs_render","blocked","fetch_failed","read"]'::jsonb, '["needs_render","blocked","fetch_failed"]'::jsonb),
      ('firecrawl', 'scholarship_cap_per_uni',            '5000'::jsonb,   '150'::jsonb),
      ('firecrawl', 'scholarship_min_courses',            '0'::jsonb,      '30'::jsonb),
      ('firecrawl', 'map_limit_scholarships',             '100000'::jsonb, '5000'::jsonb),
      ('firecrawl', 'search_results_scholarship_discover','20'::jsonb,     '6'::jsonb),
      ('firecrawl', 'search_results_scholarship_search',  '20'::jsonb,     '5'::jsonb),
      ('pipeline',  'batch.central_find',                 '50'::jsonb,     '4'::jsonb),
      ('pipeline',  'batch.coverage_find_site',           '50'::jsonb,     '5'::jsonb),
      ('pipeline',  'batch.course_link_search_queue',     '200'::jsonb,    '20'::jsonb)
    ) v(toolset, key, window_value, normal_value)
  loop
    update pipeline.platform_toolset_settings s set value = r.normal_value, reason = v_reason
     where s.toolset_key = r.toolset and s.key = r.key and s.value = r.window_value and r.window_value is distinct from r.normal_value;
    get diagnostics v_n = row_count;
    if v_n = 1 then v_changed := v_changed || jsonb_build_object(r.key, r.normal_value);
    else v_kept := v_kept || jsonb_build_object(r.key, (select s.value from pipeline.platform_toolset_settings s where s.toolset_key = r.toolset and s.key = r.key)); end if;
  end loop;

  update pipeline.scholarship_layer_settings set value = 60000, updated_at = now(), reason = v_reason where key = 'firecrawl_cap' and value = 100000;
  get diagnostics v_n = row_count;
  if v_n = 1 then v_changed := v_changed || jsonb_build_object('scholarship.firecrawl_cap', 60000);
  else v_kept := v_kept || jsonb_build_object('scholarship.firecrawl_cap', (select value from pipeline.scholarship_layer_settings where key = 'firecrawl_cap')); end if;

  perform cron.alter_job(j.jobid, active => false) from cron.job j where j.jobname in ('coverage-discover', 'coverage-discover-2') and j.active;
  update pipeline.firecrawl_runs set status = 'stopped', finished_at = now() where status = 'running';
  get diagnostics v_n = row_count;

  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('pipeline', 'firecrawl_unlimited_window_ended', 'pipeline.platform_toolset_settings',
          jsonb_build_object('restored', v_changed, 'left_as_found', v_kept, 'runs_stopped', v_n,
                             'jobs_paused', jsonb_build_array('coverage-discover', 'coverage-discover-2'),
                             'authority', v_reason, 'migration', '20261103000500_cf247_firecrawl_window_restore'), null);
end $restore$;

-- post-check: the budget guard is back on, the scope is back to target providers and no Firecrawl run is open
do $$
begin
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'firecrawl' and key = 'daily_budget_on') is distinct from 'true'::jsonb then
    raise exception 'Firecrawl window restore post-check: daily_budget_on is not true'; end if;
  if exists (select 1 from pipeline.firecrawl_runs where status = 'running') then
    raise exception 'Firecrawl window restore post-check: a Firecrawl run is still running'; end if;
  if exists (select 1 from cron.job where jobname in ('coverage-discover', 'coverage-discover-2') and active) then
    raise exception 'Firecrawl window restore post-check: a discovery job is still active'; end if;
end $$;
