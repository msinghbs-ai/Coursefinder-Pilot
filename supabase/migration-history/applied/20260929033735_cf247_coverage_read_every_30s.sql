-- CF-247 coverage sweep: bound pages were arriving faster than they were read (522 read, 2,374 waiting after 15
-- minutes). Reads run every 30 seconds with up to 50 pages per call (at most 8 per provider per call, so at most
-- 16 requests a minute to one site).
select cron.schedule('coverage-read','30 seconds',$$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"read","limit":50}'::jsonb)$$);
