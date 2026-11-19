-- ========== 6. Schedules — created SWITCHED OFF; enabled only after a supervised run ==========
-- Enqueue and dispatch do nothing unless a qualified profile is active (activation is the master switch).
select cron.schedule('layer3-tuition-enqueue',   '*/15 * * * *',     $$select public.layer3_enqueue_eligible_layer2_service(25)$$);
select cron.schedule('layer3-tuition-dispatch',  '5-59/10 * * * *',  $$select pipeline.svc_pilot_submit_nonce('layer3-work-dispatch', jsonb_build_object('limit',5,'worker','cron-layer3-dispatch'))$$);
select cron.schedule('layer3-tuition-admission', '8-59/15 * * * *',  $$select security.layer3_tuition_admit_validated_v1(25)$$);
select cron.alter_job(jobid, active := false) from cron.job
where jobname in ('layer3-tuition-enqueue','layer3-tuition-dispatch','layer3-tuition-admission');
