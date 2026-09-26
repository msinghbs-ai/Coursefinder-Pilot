-- 26 Sep 2026: workload re-plan for Micro compute (Decision 152). After the disk-IO exhaustion on
-- Nano, every scheduled job runs no more often than its data changes, and heavy jobs each have their
-- own minute of the hour (at least 7 minutes apart) so they never overlap. Consumers read the
-- reference bundle from cache (rebuilt hourly; live fallback only if older than 3 hours, applied
-- separately under the consumer API guard). Job history is kept for 14 days.
select cron.alter_job(jobid, schedule := s.sched, active := true)
from cron.job j join (values
  -- light, operational
  ('provider-fee-profiles-apply','26 * * * *'),
  ('provider-rule-admit','29 * * * *'),
  ('coursefinder-layer2-qualification-finalizer','2-59/15 * * * *'),
  ('layer2-auto-discovery','13-59/15 * * * *'),
  ('layer3-operations-housekeeping','44 * * * *'),
  ('coursefinder-m2-3-refresh-intelligence-tick','36 * * * *'),
  -- moderate
  ('admin-summary-snapshots-refresh','1-59/15 * * * *'),
  ('coursefinder-layer1-regulatory-scheduler','5 * * * *'),
  ('coursefinder-layer2-fanout-scheduler','27,57 * * * *'),
  ('layer3-tuition-enqueue','22 * * * *'),
  ('coursefinder-scholarship-etl-scheduler','43 * * * *'),
  -- heavy: one per minute slot, never overlapping
  ('evidence-filter-options-refresh','4 */2 * * *'),
  ('coursefinder-cf245-enrichment-hourly-admin-cache','12 * * * *'),
  ('coursefinder-layer2-refresh-dispatcher','18 * * * *'),
  ('coursefinder-layer2-qualification-scheduler','32 * * * *'),
  ('coursefinder-layer2-wave-scheduler','40 * * * *'),
  ('coursefinder-cf245-enrichment-coverage-snapshot','47 * * * *'),
  ('consumer-reference-bundle-refresh','50 * * * *'),
  ('layer2-onboarding-snapshot','53 */2 * * *'),
  ('evidence-link-index','9-59/10 * * * *')
) s(name,sched) on s.name=j.jobname;

-- Consumer reference bundle: live fallback only if the cache is older than 3 hours.
create or replace function public.zoho_edge_reference_bundle_v1()
returns jsonb language plpgsql volatile security definer
set search_path to 'pg_catalog', 'public', 'catalogue', 'ref', 'search'
as $b$
declare b jsonb; t timestamptz;
begin
  select c.bundle, c.built_at into b, t from pipeline.consumer_reference_bundle_cache c where c.id=1;
  if b is null or t < now() - interval '3 hours' then
    return security.zoho_reference_bundle_live_v1();
  end if;
  return b;
end $b$;

-- Job history retention: 14 days (daily).
select cron.unschedule(jobid) from cron.job where jobname='cron-history-retention';
select cron.schedule('cron-history-retention','37 3 * * *',$c$delete from cron.job_run_details where end_time < now() - interval '14 days';$c$);
