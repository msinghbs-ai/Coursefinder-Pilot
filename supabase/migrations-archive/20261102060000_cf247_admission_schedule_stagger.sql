-- CF-247 Decision 4 (Platform Admin consolidated decision pack, 2 Nov 2026 10:56, "Scheduler capacity: APPROVED APPROACH: Stagger the three
-- 10-minute admission jobs, subject to current-load reconciliation"; admin docs/platform/nz-enrichment-brief/2026-11-02-consolidated-decision-pack-1056.md).
-- Why: on 2 Nov coverage-admit (07:00) and adapter-overwrite (07:03) hit the 120 s statement limit during a database slowdown (06:58–07:05)
--   (admin docs/platform/nz-enrichment-brief/2026-11-02-incident-0700-admission-timeouts.md). The admission writers shared their start
--   minutes with other 10-minute jobs: coverage-admit with nz-cop and link-refresh at :x0, adapter-overwrite with provider-english-defaults at
--   :x3, coverage-admit-intakes with platform-health at :x8.
-- What: the approved pattern (the D8 P1 proposal). Commands, frequency, batch sizes and time-outs unchanged.
--   coverage-admit          '*/10 * * * *'    -> '3-59/10 * * * *'
--   coverage-admit-intakes  '8-59/10 * * * *' -> '5-59/10 * * * *'
--   adapter-overwrite       '3-59/10 * * * *' -> '9-59/10 * * * *'
-- Load reconciliation (live 2 Nov 11:00 AEDT, last 3 h): 0 failures in the three jobs; :x3 keeps provider-english-defaults (about 17 s) beside
--   coverage-admit; :x5 has policy-auto-approve and fee-period-settle (light); :x9 has evidence-link-index (light). Observed after release.
-- Rollback: cron.alter_job back to the three schedules on the left (one statement each); the catalogue notes are history.
-- Replaces: the SS-004 (1 Nov 2026) admission stagger :00/:03/:08 in migration 20261101010000 (same jobs, new minutes)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No new job. Consumer API untouched (G3).

-- guard: the three schedules are as reconciled; otherwise nothing changes
do $$
begin
  if (select schedule from cron.job where jobname = 'coverage-admit') = '3-59/10 * * * *'
     and (select schedule from cron.job where jobname = 'coverage-admit-intakes') = '5-59/10 * * * *'
     and (select schedule from cron.job where jobname = 'adapter-overwrite') = '9-59/10 * * * *' then
    raise notice 'admission stagger already applied';
  elsif (select schedule from cron.job where jobname = 'coverage-admit') <> '*/10 * * * *'
     or (select schedule from cron.job where jobname = 'coverage-admit-intakes') <> '8-59/10 * * * *'
     or (select schedule from cron.job where jobname = 'adapter-overwrite') <> '3-59/10 * * * *' then
    raise exception 'admission schedules differ from the reconciled state (*/10, 8-59/10, 3-59/10); nothing changed';
  end if;
end $$;

select cron.alter_job((select j.jobid from cron.job j where j.jobname = 'coverage-admit'), schedule => '3-59/10 * * * *');
select cron.alter_job((select j.jobid from cron.job j where j.jobname = 'coverage-admit-intakes'), schedule => '5-59/10 * * * *');
select cron.alter_job((select j.jobid from cron.job j where j.jobname = 'adapter-overwrite'), schedule => '9-59/10 * * * *');

update pipeline.automation_catalogue set description = description || ' From 2 Nov 2026 (Decision 4) runs at minute 3 of each 10.'
 where jobname = 'coverage-admit' and description not like '%Decision 4%';
update pipeline.automation_catalogue set description = description || ' From 2 Nov 2026 (Decision 4) runs at minute 5 of each 10 (the earlier minute-8 note is history).'
 where jobname = 'coverage-admit-intakes' and description not like '%Decision 4%';
update pipeline.automation_catalogue set description = description || ' From 2 Nov 2026 (Decision 4) runs at minute 9 of each 10 (the earlier minute-3 note is history).'
 where jobname = 'adapter-overwrite' and description not like '%Decision 4%';

-- post-check
do $$
begin
  if (select schedule from cron.job where jobname = 'coverage-admit') <> '3-59/10 * * * *'
     or (select schedule from cron.job where jobname = 'coverage-admit-intakes') <> '5-59/10 * * * *'
     or (select schedule from cron.job where jobname = 'adapter-overwrite') <> '9-59/10 * * * *' then
    raise exception 'Decision 4 post-check: admission schedules';
  end if;
end $$;
