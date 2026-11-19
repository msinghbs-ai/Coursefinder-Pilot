-- CF-247 (2 Oct 2026). The map-first link matcher worker (coverage-sweep mode ai_match, worker v0.10.0) is deployed and
-- was checked on 12 live courses (4 pages chosen, 8 none; every choice one of the prepared addresses). It now runs every
-- minute, 60 courses a run. Each chosen page is read by coverage-read and accepted only under the identity rule.
select cron.schedule('coverage-ai-match', '* * * * *', $$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"ai_match","limit":60,"concurrency":10}'::jsonb)$$);
