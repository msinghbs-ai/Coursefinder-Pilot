-- CF-247 s900 (Platform Admin 21 Nov 2026 07:48 AEDT, chat S1-Coverage-Unlock-UI-Notes): the approved fixes from the 2 AM capacity and runtime
-- audit (admin docs/platform/2026-11-21-capacity-runtime-audit.md, admin #730).
--   IQ-00510: the pilot database alert levels move from 4 / 6 / 7 GiB to 8,192 / 9,216 / 10,240 MiB (watch / high / critical). The database
--             read 7,370 MiB on 21 Nov 02:17 AEDT against the old critical level of 7,168 MiB; the growth is stored evidence and pipeline work,
--             and dead rows are about 5%. Log retention is unchanged. The non-locking VACUUM (ANALYZE) of the four flagged tables cannot run
--             inside a migration (VACUUM refuses a transaction block), so it is admin docs/paste/PASTE-20261121-s900-vacuum-analyze.sql.
--   IQ-00445: coverage-reconcile moves from :26 (the busiest minute of the hour: 59k busy seconds in 24 h against 13k at :09; alone the run
--             takes 9.1 s, at :26 106 s p50 and 137 s p95 with 3 time-outs in 7 days) to :09. scholarship-coverage-classify, which runs after
--             it, moves from :29 to :40. Same commands, same catalogue rows; only the minute and the catalogue wording change.
-- Replaces: the :26 and :29 minutes of the two jobs, and the 16 Oct 2026 pilot alert levels (CF-CHG-20260901-051).
-- Retires: nothing.
-- Parity before writing (21 Nov 2026 08:20 AEDT): main a0f9cece4 (#1441), migration head 20261120235000; open claim 20261121080000 (s894,
-- Pilot #1442). G1: no job added (active jobs unchanged, 0 unregistered). G2: no number in a job command; no new setting. G3: no consumer
-- object (75/48). Nothing dropped or deleted. No spend.

set local lock_timeout = '5s'; -- fixed: lock wait guard for the cron and policy updates below

do $s900$
declare v_before jsonb; v_rec bigint; v_cls bigint; v_active int := (select count(*) from cron.job where active);
begin
  select to_jsonb(c) into v_before from pipeline.platform_capacity_policy c where c.environment = 'pilot';
  if v_before is null then raise exception 's900: no pilot row in pipeline.platform_capacity_policy'; end if;

  update pipeline.platform_capacity_policy
     set database_warn_bytes     = 8192::bigint * 1048576,   -- 8,192 MiB (watch)
         database_high_bytes     = 9216::bigint * 1048576,   -- 9,216 MiB
         database_critical_bytes = 10240::bigint * 1048576,  -- 10,240 MiB
         change_control_ref = 'CF-CHG-20260901-051; CF-247 s900 (Platform Admin 21 Nov 2026 07:48, IQ-00510)',
         updated_at = now()
   where environment = 'pilot';

  select jobid into v_rec from cron.job where jobname = 'coverage-reconcile' and command = 'select security.coverage_reconcile_v1()';
  select jobid into v_cls from cron.job where jobname = 'scholarship-coverage-classify' and command = 'select security.scholarship_coverage_classify_v1()';
  if v_rec is null or v_cls is null then raise exception 's900: coverage-reconcile or scholarship-coverage-classify not found with its expected command'; end if;
  perform cron.alter_job(v_rec, schedule => '9 * * * *');
  perform cron.alter_job(v_cls, schedule => '40 * * * *');

  update pipeline.automation_catalogue
     set description = replace(description, 'Every hour at :26:', 'Every hour at :09:')
   where jobname = 'coverage-reconcile';
  update pipeline.automation_catalogue
     set description = replace(description, 'Every hour at :29 (after coverage-reconcile):', 'Every hour at :40 (after coverage-reconcile at :09):')
   where jobname = 'scholarship-coverage-classify';

  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('capacity', 'policy_update', 'pipeline.platform_capacity_policy',
          jsonb_build_object('change', 's900', 'issue', 'IQ-00510', 'environment', 'pilot',
                             'before', jsonb_build_object('warn', v_before->'database_warn_bytes', 'high', v_before->'database_high_bytes', 'critical', v_before->'database_critical_bytes'),
                             'after', jsonb_build_object('warn', 8192::bigint * 1048576, 'high', 9216::bigint * 1048576, 'critical', 10240::bigint * 1048576)), null),
         ('scheduler', 'job_reschedule', 'coverage-reconcile',
          jsonb_build_object('change', 's900', 'issue', 'IQ-00445', 'from', '26 * * * *', 'to', '9 * * * *'), null),
         ('scheduler', 'job_reschedule', 'scholarship-coverage-classify',
          jsonb_build_object('change', 's900', 'issue', 'IQ-00445', 'from', '29 * * * *', 'to', '40 * * * *'), null);

  -- post-checks
  if (select schedule from cron.job where jobid = v_rec) <> '9 * * * *' or (select schedule from cron.job where jobid = v_cls) <> '40 * * * *' then
    raise exception 'post-check: a job did not take its new minute';
  end if;
  if not (select active from cron.job where jobid = v_rec) or not (select active from cron.job where jobid = v_cls) then
    raise exception 'post-check: a moved job is not switched on';
  end if;
  if (select count(*) from cron.job where active) <> v_active then raise exception 'post-check: the active job count changed'; end if;
  if (select database_critical_bytes from pipeline.platform_capacity_policy where environment = 'pilot') <> 10240::bigint * 1048576 then
    raise exception 'post-check: the pilot critical level was not set';
  end if;
  if exists (select 1 from pipeline.automation_catalogue where jobname in ('coverage-reconcile', 'scholarship-coverage-classify') and description ~ 'at :2[69]') then
    raise exception 'post-check: a catalogue row still names the old minute';
  end if;
  raise notice 's900: levels 8192/9216/10240 MiB; coverage-reconcile :09, scholarship-coverage-classify :40; % active jobs', v_active;
end $s900$;
