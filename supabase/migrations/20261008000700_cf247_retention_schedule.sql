-- CF-247, 8 Oct 2026: storage and retention, part 3 of 3: run the retention worker every 2 minutes (it does nothing unless a Platform Admin
-- queued a purge or audit on the Storage & retention screen, apart from refreshing one category's estimate an hour).
select cron.schedule('retention-worker', '*/2 * * * *', 'select security.retention_tick_v1()');
