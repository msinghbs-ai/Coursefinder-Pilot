create extension if not exists pg_cron;
select cron.schedule(
  'coursefinder-data-quality-overview-refresh',
  '*/15 * * * *',
  'select security.refresh_data_quality_overview_snapshots();'
);
