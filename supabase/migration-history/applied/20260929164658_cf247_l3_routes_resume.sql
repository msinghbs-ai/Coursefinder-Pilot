-- CF-247 Layer 3: the Platform Admin removed the OpenRouter key's weekly limit (29 Sep 2026 22:13 IST). A live probe
-- succeeded (English 3 pages at tier 1, US$0.0003; intake 3 pages, 2 at tier 1 and 1 escalated to tier 3), so the
-- intake, English and tuition route jobs are switched back on. Daily guards and the credit floor are unchanged.
select cron.alter_job(jobid, active => true) from cron.job where jobname in ('layer3-intake-route','layer3-english-route','layer3-tuition-dispatch');
insert into pipeline.layer3_route_events(kind,detail) values ('routes_resumed',jsonb_build_object('reason','OpenRouter key weekly limit removed by the Platform Admin (29 Sep 2026 22:13 IST); probe succeeded'));
