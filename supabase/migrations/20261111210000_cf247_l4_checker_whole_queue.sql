-- CF-247 F-INT (Layer 4 backlog triage, 11 Nov 2026 08:30 AEDT; Platform Admin "yes" 08:13 to the Layer 4 build-up plan, step 1): the continuous
-- production check integration-validate looks at the whole Layer 4 queue again.
--
-- Evidence (project fxcwkweaxjtknorudmwp, SELECT only, 11 Nov 2026 06:20 to 08:30 AEDT):
--   - pipeline.layer4_review_items has 5,361 pending items; integration.l4_pending_max is 5,000.
--   - security.integration_validate_v1 reads the pending items through security.integration_l4_pending_v1(integration.l4_pending_max), newest first,
--     and marks its findings "partly_checked". The 361 OLDEST items (back to 25 Oct 2026) are not examined, which are exactly the ones its
--     duplicate, lifecycle-leak and age checks exist to catch (layer4.target_days 7; 2,980 items are past it).
--   - Job integration-validate (21,51 * * * *) took 2.5 to 3.2 s until 10 Nov 19:51 UTC and 9.6 to 13.5 s on the last two runs as the queue grew.
-- What this changes: the setting integration.l4_pending_max 5,000 -> 10,000 (range 500 to 50,000 unchanged). Nothing else: no function, job,
-- schedule, Layer 4 item, decision or consumer object (G3) changes. The job's run time is watched after deploy; forward recovery is the same
-- update back to 5,000 (Settings > Pipeline settings > Integration queue, or this statement with 5000).
-- Replaces: the value 5,000 of integration.l4_pending_max
-- Retires: nothing

update pipeline.platform_toolset_settings set value = '10000'::jsonb, updated_at = now(),
       reason = 'CF-247 Layer 4 build-up step 1 (20261111210000): 5,361 pending exceeded 5,000, so the oldest items were not checked; 10,000 covers the whole queue'
 where toolset_key = 'pipeline' and key = 'integration.l4_pending_max';

do $post$
begin
  if security.pipeline_num_v1('integration.l4_pending_max', 0) <> 10000 then raise exception 'post-check: integration.l4_pending_max'; end if;
end $post$;
