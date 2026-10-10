-- CF-247 (Platform Admin, 1 Oct 2026 16:01 AEST: "Start parallel jobs for nz asap"). A second course-page discovery
-- worker runs beside coverage-discover. The coverage-sweep worker maps at most 8 provider sites per call; the queue
-- (public.svc_coverage_discovery_next) leases rows with FOR UPDATE SKIP LOCKED, so two workers never take the same
-- provider. Listed in Automations (area Course pages) so it can be paused, run or resized like the first one.
-- Idempotent: an existing job of the same name is replaced.

select cron.unschedule(jobid) from cron.job where jobname = 'coverage-discover-2';
select cron.schedule('coverage-discover-2', '* * * * *',
  $$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"discover","limit":8}'::jsonb)$$);

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('coverage-discover-2', 'Course pages', 21, 'Discover course pages (second worker)',
        'Runs beside Discover course pages to map more provider websites at once (added for New Zealand, 1 Oct 2026).', 5, true)
on conflict (jobname) do update set area = excluded.area, sort = excluded.sort, label = excluded.label,
       description = excluded.description, control_rank = excluded.control_rank, batch_editable = excluded.batch_editable;
