-- CF-247 Decision 162: run the provider basis rule every 10 minutes, just before the Layer 3 dispatcher (5-59/10).
select cron.unschedule(jobid) from cron.job where jobname='provider-basis-rule-admit';
select cron.schedule('provider-basis-rule-admit','3-59/10 * * * *',$c$select security.provider_basis_rule_admit_v1(true,200)$c$);
