-- Decision 124: deterministic provider-rule admission runs every 15 minutes (7, 22, 37, 52),
-- after the 5-minute rule stamping. Layer 3 enqueue runs (no AI calls); Layer 3 dispatch
-- and admission stay paused until a model passes two clean benchmark runs (Decision 91).
select cron.unschedule(jobid) from cron.job where jobname='provider-rule-admit';
select cron.schedule('provider-rule-admit','7-59/15 * * * *',$c$select security.provider_rule_admit_v1(true);$c$);
