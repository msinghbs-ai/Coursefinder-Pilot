-- CF-247 (2 Oct 2026). Platform Admin, by multiple choice: "Switch on Haiku step 2". The intake cascade's step 2,
-- Claude Haiku 4.5 on the qualified v1.2.0 contract (44 of 47 right and 0 wrong-admitted on the frozen holdout
-- l3r-intake-h1; Platform Admin direction 29 Sep 2026), is switched on. An answer from step 1 (Qwen3 30B) that fails
-- the checks now goes to Haiku before Layer 4; Haiku becomes the final step. Claude Sonnet 4.6 (step 3) stays off.
-- Also by the same choice: "Rolling / monthly intakes" stay with a person (the v1.3.0 candidates stay paused).
update pipeline.layer3_route_tiers set active = true, updated_at = now()
 where id = '43fb82b9-f6e4-4c69-b15f-7115eb39ee36' and task_class = 'provider_intake_validation' and tier_no = 2;
update pipeline.layer3_route_tiers t
   set is_final = (t.active and t.tier_no = (select max(tier_no) from pipeline.layer3_route_tiers where task_class = 'provider_intake_validation' and active)), updated_at = now()
 where t.task_class = 'provider_intake_validation';
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('layer3', 'switch_on', 'Intake cascade step 2: Claude Haiku 4.5 (v1.2.0)',
        jsonb_build_object('decision', 'Platform Admin multiple choice, 2 Oct 2026 20:05', 'tier_id', '43fb82b9-f6e4-4c69-b15f-7115eb39ee36'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
