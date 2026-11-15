-- =====================================================================================================================================
-- PASTE FILE for the Platform Admin (SQL editor, project fxcwkweaxjtknorudmwp ONLY; never coursefinder-demo). A migration drops nothing
-- (CLAUDE.md housekeeping); this file is how the 46 retiring settings leave pipeline.platform_toolset_settings.
-- Approved: Platform Admin 16 Nov 2026 05:12 (decision 1: retire the 39 Serper and ScrapingBee settings and the settings tied to retiring
-- components) and 05:23 (start Phase 1 now). Audit: project doc claude/ui-ux-settings-audit-2026-11-15.md §2.3 and §6.
-- Prepared by: migration 20261116010000_cf247_settings_tidy_phase1 (control_class 'retiring'; component register kind 'setting', retiring,
-- retire_after = the day it was applied (15 Nov 2026 UTC) + hygiene.retire_after_days, so 29 Nov 2026).
-- Replaces: nothing. Retires: the 46 settings (rows deleted; register rows set to retired). The toolset rows serper and scrapingbee in
--   pipeline.platform_toolsets stay (their history and keys are kept, as since 4 Oct 2026).
-- Run on or after 29 Nov 2026. One transaction; it refuses to run unless:
--   1. all 46 settings are still retiring, with a register row past retire_after;
--   2. no scheduled job command names any of them;
--   3. the functions that still name them are gone (dropped by their own paste files): public.admin_search_pass_start,
--      public.admin_toolset_sample_write, public.admin_toolset_samples_read, security.toolset_pass_backlog (retiring, after 17 Nov 2026) and
--      security.calendar_default_intakes_apply_v1 (retiring, after 5 Nov 2026);
--   4. the jobs course-link-reverse and worker-outcome-check are gone (PASTE-20261115-cron-legacy-jobs-drop.sql PART B, from 29 Nov 2026).
--   Also confirm by hand before running: the retiring edge function toolset-runner has been deleted (Supabase dashboard › Edge Functions).
-- Kept everywhere else: security.toolset_plan_status gives no plan for a toolset without settings (every setting it reads is optional);
--   security.pipeline_num_v1 falls back to its default; security.ai_settings_not_read_v1 simply stops listing the three model pins.
-- Rollback: every deleted row is written in full to pipeline.admin_control_events (area 'settings', action 'drop', detail = the row) first;
--   re-insert it from there.
-- =====================================================================================================================================

begin;
do $$
declare v_n int; v_names text[]; v_left text;
begin
  select array_agg(r.name), count(*) into v_names, v_n
    from pipeline.platform_toolset_settings s
    join pipeline.component_register r on r.kind = 'setting' and r.name = s.toolset_key || '.' || s.key
   where s.control_class = 'retiring' and r.status = 'retiring' and r.introduced_in like '20261116010000%' and r.retire_after <= current_date;
  if v_n <> 46 then raise exception 'refused: % of 46 settings are retiring and past retire_after (29 Nov 2026); nothing was changed', v_n; end if;

  select string_agg(j.jobname, ', ') into v_left from cron.job j
   where exists (select 1 from unnest(v_names) x where position('''' || substr(x, strpos(x, '.') + 1) || '''' in replace(j.command, '''''', '''')) > 0)
      or j.jobname in ('course-link-reverse', 'worker-outcome-check');
  if v_left is not null then raise exception 'refused: scheduled job(s) still name or need these settings: %; nothing was changed', v_left; end if;

  select string_agg(n.nspname || '.' || p.proname, ', ') into v_left from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname || '.' || p.proname in ('public.admin_search_pass_start', 'public.admin_toolset_sample_write', 'public.admin_toolset_samples_read',
                                           'security.toolset_pass_backlog', 'security.calendar_default_intakes_apply_v1');
  if v_left is not null then raise exception 'refused: function(s) that read these settings still exist: %; drop them first; nothing was changed', v_left; end if;

  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  select 'settings', 'drop', s.toolset_key || '.' || s.key, to_jsonb(s) || jsonb_build_object('paste', 'PASTE-20261116-retired-settings-drop.sql'), auth.uid()
    from pipeline.platform_toolset_settings s where s.toolset_key || '.' || s.key = any(v_names);

  delete from pipeline.platform_toolset_settings s where s.toolset_key || '.' || s.key = any(v_names) and s.control_class = 'retiring';
  get diagnostics v_n = row_count;
  if v_n <> 46 then raise exception 'post-check: % of 46 settings deleted; rolled back', v_n; end if;

  update pipeline.component_register set status = 'retired', note = coalesce(note || '; ', '') || 'dropped by PASTE-20261116-retired-settings-drop.sql', updated_at = now()
   where kind = 'setting' and name = any(v_names);
  raise notice 'done: 46 retiring settings deleted (each kept in pipeline.admin_control_events), register rows retired';
end $$;
commit;
