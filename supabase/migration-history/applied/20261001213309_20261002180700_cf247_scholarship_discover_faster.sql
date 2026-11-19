-- CF-247 (Decision 214): "asap" - scholarship discovery reads 6 providers per run (the worker's maximum; was 3), every
-- 10 minutes, so the 100 queued providers take about 3 hours instead of 6. Same Firecrawl cap.
select cron.schedule('scholarship-discover', '*/10 * * * *', $$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"scholarship_discover","limit":6}'::jsonb)$$);
