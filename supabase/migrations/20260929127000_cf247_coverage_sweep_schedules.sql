-- CF-247 complete coverage: ongoing schedules (Platform Admin direction 29 Sep 2026).
--  coverage-discover  every 2 minutes, 6 providers per call: site maps first, Firecrawl map only when short; each
--                     provider is re-discovered every 30 days (new and renamed course pages).
--  coverage-bind      every 5 minutes (already scheduled): binds courses of newly mapped providers.
--  coverage-read      every minute, up to 40 pages per call, at most 8 per provider: bound pages first; pages are
--                     re-read every 90 days, failed reads after 6 hours.
--  course-coverage-build hourly (already scheduled): statistics and daily trend.
select cron.schedule('coverage-discover','*/2 * * * *',$$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"discover","limit":6}'::jsonb)$$);
select cron.schedule('coverage-read','* * * * *',$$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"read","limit":40}'::jsonb)$$);
