-- CF-247 complete coverage (Platform Admin approval 29 Sep 2026: "Raise cap + qualify"): Layer 3 tuition checks
-- up to 15,000 a day, spend ceiling US$5 a day. The qualified Mistral profile's allowance rises from 1,000 to 15,000
-- requests a day (about US$0.0002 each, so about US$3 a day at the cap). Rate limits are not part of the
-- qualification binding hash (model, prompts, token limits, timeouts, retry ceiling), so the qualification stands.
-- Schedules: dispatch every 2 minutes (25 items per call, the worker's maximum), enqueue 250 an hour, admission
-- 100 every 5 minutes.
alter table pipeline.layer3_profile_activation_events drop constraint layer3_profile_activation_events_action_check;
alter table pipeline.layer3_profile_activation_events add constraint layer3_profile_activation_events_action_check
  check (action = any (array['activated','activation_refused','paused','auto_paused_binding_drift','throughput_changed']));
update pipeline.layer3_model_profiles set requests_per_day=15000, requests_per_minute=30, updated_at=now()
 where code='openrouter-provider-tuition-validation-mistral-small-3-2-v1' and requests_per_day=1000;
insert into pipeline.layer3_profile_activation_events(profile_id,action,actor_id,reason,binding_hash,benchmark_run_id,checks,change_control_ref)
select id,'throughput_changed',null,'Platform Admin approval 29 Sep 2026: 15,000 a day, spend ceiling US$5 a day (complete coverage)',
       quality_benchmark->>'binding_hash', quality_benchmark->>'run_id',
       jsonb_build_object('requests_per_day',jsonb_build_object('from',1000,'to',15000),'requests_per_minute',jsonb_build_object('from',10,'to',30),'daily_spend_ceiling_usd',5,'binding_hash_unchanged',true),
       'CF-CHG-20260915-247'
  from pipeline.layer3_model_profiles where code='openrouter-provider-tuition-validation-mistral-small-3-2-v1';
select cron.schedule('layer3-tuition-dispatch','*/2 * * * *',$$select pipeline.svc_pilot_submit_nonce('layer3-work-dispatch', jsonb_build_object('limit',25,'worker','cron-layer3-dispatch'))$$);
select cron.schedule('layer3-tuition-enqueue','22 * * * *',$$select public.layer3_enqueue_eligible_layer2_service(250)$$);
select cron.schedule('layer3-tuition-admission','*/5 * * * *',$$select security.layer3_tuition_admit_validated_v1(100)$$);
