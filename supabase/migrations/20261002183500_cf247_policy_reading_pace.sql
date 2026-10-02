-- CF-247 (2 Oct 2026, Platform Admin 19:02: "take and record recommended action to have maximum data admission").
-- About 500 English policy and academic calendar documents are found but not yet read; at 8 a run they take a day.
-- The institution reader reads up to 20 documents a run (each run stays inside the worker's time budget; Firecrawl
-- spend is still capped by the balance guard). Searches are unchanged.
select cron.alter_job(j.jobid, command := $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"provider_facts","search_limit":12,"read_limit":20}'::jsonb)$c$)
  from cron.job j where j.jobname = 'provider-facts';
