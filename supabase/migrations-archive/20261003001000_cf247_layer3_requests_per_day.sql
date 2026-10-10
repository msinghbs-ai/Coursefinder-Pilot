-- CF-247 (3 Oct 2026, 09:20 AEST). Platform Admin, 08:17: "What's stopping us" — remove throttles that are not cost
-- controls. Found at 09:10: both Layer 3 routes answer "profile requests/day reached". layer3_fact_claim_service counts
-- every interpretation of the task class for the UTC day (all steps together) against the claiming profile's
-- requests_per_day, so each cascade stops at 6,000 calls a day — intake reached 6,001 and English 6,000 by 09:00 AEST,
-- at about US$1.50 of cheap-model calls. The daily spend guard (intake US$20, English US$15, Platform Admin 29 Sep) and
-- the credit floor are the cost controls and stay as they are.
-- What this does: requests_per_day 6,000 → 40,000 for the enabled intake and English cascade profiles (the Claude steps
-- included, because the count is task-wide and the smallest cap binds). Nothing else changes: no profile is switched on
-- or off, no tier moves, every call is still bound to its qualified hash and limited by the daily spend guard.
update pipeline.layer3_model_profiles
   set requests_per_day = 40000, updated_at = now()
 where enabled and retired_at is null and requests_per_day = 6000
   and code ~ '^openrouter-(intake|english)-l3[cr]-';
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('layer3', 'limit_change', 'Layer 3 intake and English profiles: requests a day 6,000 → 40,000',
        jsonb_build_object('why', 'layer3_fact_claim_service counts all steps of a task class together; both cascades stopped at 6,000 calls on 3 Oct by 09:00 AEST', 'cost_control', 'daily spend guard unchanged (intake US$20, English US$15)', 'direction', 'Platform Admin 3 Oct 2026 08:17'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
