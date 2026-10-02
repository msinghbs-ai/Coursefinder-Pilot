-- CF-247 (2 Oct 2026). coverage-sweep mode reidentify (worker v0.10.0, identity rule v0.5.7) was checked live on 300
-- stored mismatch pages (13 passed, 287 still mismatched). It runs every minute, 300 pages a run, until every stored
-- mismatch page has been checked under this rule (each page once per rule); after that a run finds nothing to do.
select cron.schedule('coverage-reidentify', '* * * * *', $$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"reidentify","limit":300}'::jsonb)$$);
