insert into pipeline.layer2_execution_policies(profile_id,schedule_mode,batch_size,routing_strategy,max_paid_attempts_per_entity,max_vendor_units_per_entity,max_cost_usd_per_entity,auto_handoff_layer3,stop_on_identity_mismatch,enabled,max_concurrency,stale_after_minutes)
select sp.id,'manual',1,'direct_then_best_value',2,2,0.10,true,true,true,1,30
from pipeline.layer2_source_profiles sp
join pipeline.sources s on s.id=sp.source_id
where sp.domain='scholarship' and s.source_type='scholarship_detail' and sp.enabled and not sp.paused
on conflict(profile_id) do nothing;
