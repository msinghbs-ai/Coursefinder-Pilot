-- CF-247 legacy telemetry retirement (S2-Build, Platform Admin 18 Nov 2026 12:19: retire telemetry jobs and rollup records that no screen or
-- operation uses, keeping the daily telemetry sync, rollup-scheduler and coverage-lane-dispatch).
--
-- Read live 18 Nov 2026 12:35 AEDT (consumer per object):
--   * Retired here (no consumer): rollup targets coursefinder-cf245-enrichment-coverage-snapshot and coursefinder-cf245-enrichment-hourly-admin-cache
--     (functions public.svc_cf245_capture_coverage_snapshot and public.svc_cf245_refresh_hourly_admin_cache). They write
--     pipeline.enrichment_coverage_snapshots (about 15,350 rows, the hourly per-field snapshot of the old CF-245 enrichment panel) and
--     pipeline.layer2_enrichment_hourly_admin_cache_v1, read only by security.admin_enrichment_operations_read through
--     admin_read('enrichment_operations'), which no screen calls (only the test mock names it). Their legacy cron jobs are already off (PR 1).
--   * Kept (live consumers): Link refresh (Coverage › Courses: the link schedules and the portals that supply course links, applied by job
--     link-refresh) is configuration, not telemetry; Stalled fields is the actionable card on Layer 2/3 › Enrich fields (Fill now, Release holds);
--     pipeline.enrich_coverage_snapshots (Enrich fields), pipeline.progress_snapshots (Progress), course coverage and completeness builds
--     (Coverage & completeness trend charts) and every other rollup target have readers.
-- What it does: the two targets are switched off (enabled false; kept), and the targets' functions, the read and the two tables are marked
-- retiring in pipeline.component_register (retire after 14 days). The tables and their rows are dropped by the Platform Admin with admin paste
-- file docs/paste/PASTE-20261202-cf245-enrichment-snapshots-drop.sql on or after 2 Dec 2026. Nothing is dropped or deleted here. G3 untouched.
-- Replaces: nothing (no successor: the screen that read them is gone).
-- Retires: rollup targets coursefinder-cf245-enrichment-coverage-snapshot and coursefinder-cf245-enrichment-hourly-admin-cache; functions
--          public.svc_cf245_capture_coverage_snapshot, public.svc_cf245_refresh_hourly_admin_cache, security.admin_enrichment_operations_read; tables
--          pipeline.enrichment_coverage_snapshots, pipeline.layer2_enrichment_hourly_admin_cache_v1.

update pipeline.rollup_targets
   set enabled = false, updated_at = now(),
       note = coalesce(note, '') || ' | switched off 18 Nov 2026 (Platform Admin 12:19): no screen or operation reads its output; retiring'
 where target_code in ('coursefinder-cf245-enrichment-coverage-snapshot', 'coursefinder-cf245-enrichment-hourly-admin-cache') and enabled;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, introduced_in)
select v.kind, v.name, 'Reports', 'Reports', v.purpose, 'active', 'before 20261118151000'
  from (values
    ('function', 'public.svc_cf245_capture_coverage_snapshot', 'CF-245 hourly per-field enrichment coverage snapshot'),
    ('function', 'public.svc_cf245_refresh_hourly_admin_cache', 'CF-245 hourly enrichment admin cache'),
    ('function', 'security.admin_enrichment_operations_read', 'Read behind admin_read(''enrichment_operations'')'),
    ('table', 'pipeline.enrichment_coverage_snapshots', 'CF-245 hourly per-field enrichment coverage snapshots'),
    ('table', 'pipeline.layer2_enrichment_hourly_admin_cache_v1', 'CF-245 hourly enrichment admin cache')) v(kind, name, purpose)
 where not exists (select 1 from pipeline.component_register r where r.kind = v.kind and r.name = v.name);

update pipeline.component_register
   set status = 'retiring', retire_after = current_date + 14, updated_at = now(),  -- fixed: hygiene.retire_after_days (14) as the date written
       note = 'Retired 18 Nov 2026 (Platform Admin 12:19): no screen or operation reads it; dropped by admin paste file PASTE-20261202-cf245-enrichment-snapshots-drop.sql'
 where (kind, name) in (('function', 'public.svc_cf245_capture_coverage_snapshot'), ('function', 'public.svc_cf245_refresh_hourly_admin_cache'),
                        ('function', 'security.admin_enrichment_operations_read'), ('table', 'pipeline.enrichment_coverage_snapshots'),
                        ('table', 'pipeline.layer2_enrichment_hourly_admin_cache_v1'))
   and status = 'active';

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('housekeeping', 'telemetry_retire', 'cf245-enrichment-snapshots',
        jsonb_build_object('rollup_targets_off', jsonb_build_array('coursefinder-cf245-enrichment-coverage-snapshot', 'coursefinder-cf245-enrichment-hourly-admin-cache'),
                           'kept', jsonb_build_array('link-refresh', 'Stalled fields (Enrich fields)', 'enrich-coverage-snapshot', 'progress-snapshot', 'course-coverage-build', 'course-completeness-build'),
                           'reason', 'Platform Admin 18 Nov 2026 12:19: retire non-actionable legacy telemetry'), null);

do $$
begin
  if exists (select 1 from pipeline.rollup_targets where target_code in ('coursefinder-cf245-enrichment-coverage-snapshot', 'coursefinder-cf245-enrichment-hourly-admin-cache') and enabled) then
    raise exception 'post-check: the two targets are off';
  end if;
  if exists (select 1 from pipeline.rollup_targets where target_code in ('enrich-coverage-snapshot', 'progress-snapshot', 'course-coverage-build', 'course-completeness-build', 'data-delivery') and not enabled) then
    raise exception 'post-check: a target with a reader was switched off';
  end if;
  if (select count(*) from pipeline.component_register where status = 'retiring' and name in ('public.svc_cf245_capture_coverage_snapshot', 'public.svc_cf245_refresh_hourly_admin_cache',
        'security.admin_enrichment_operations_read', 'pipeline.enrichment_coverage_snapshots', 'pipeline.layer2_enrichment_hourly_admin_cache_v1')) <> 5 then -- fixed: the five objects retired here
    raise exception 'post-check: component register';
  end if;
end $$;
