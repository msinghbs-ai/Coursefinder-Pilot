-- CF-247: release one orphaned Layer 3 tuition work item (57926802…), reserved at 05:17 UTC on 29 Sep under the
-- Mistral Small 3.2 profile, which the routing activation paused later that day. Nothing will pick it up again, so it
-- goes back to pending under the active tuition route (Qwen3 235B 2507). Reported by the platform health check.
update pipeline.layer3_work_items
   set status='pending', profile_id=(select id from pipeline.layer3_model_profiles where code='openrouter-tuition-l3r-qwen3-235b-2507-v1'),
       reserved_at=null, reserved_by=null, interpretation_id=null, available_at=now(), updated_at=now(),
       last_error='released: orphaned reservation under the paused Mistral Small 3.2 profile (CF-247 platform health, 29 Sep 2026)'
 where id='57926802-0246-4f38-beac-6e4cec9fbd5a' and status='interpreting'
   and exists (select 1 from pipeline.layer3_model_profiles where code='openrouter-tuition-l3r-qwen3-235b-2507-v1' and enabled and not paused);
