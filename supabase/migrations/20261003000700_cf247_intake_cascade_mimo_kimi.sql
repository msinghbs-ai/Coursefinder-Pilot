-- CF-247 (3 Oct 2026, 08:50 AEST). Platform Admin, by multiple choice: "Yes, MiMo step 2, Kimi step 3" for the intake
-- cascade, under the cascade's own admission rule (at least 30 cases, at least 80% right, 0 wrong-admitted on the frozen
-- holdout l3r-intake-h1; Platform Admin 29 Sep 2026), which is the rule every live tier was admitted under.
-- Why: on 2 Oct MiMo v2.6 Pro (45 of 47 right, 0 wrong, US$1.26 per 1,000) and Kimi K2 0905 (43 of 47, 0 wrong, US$2.10)
-- were run on the intake holdout and marked "failed" against a stricter 95%-of-stated rule that the live final step
-- (Claude Haiku 4.5, 44 of 47, 12 of 13 stated) does not meet either. Both have zero wrong answers and cost a third to a
-- half of Haiku per call. New ladder: 1 Qwen3 30B, 2 MiMo v2.6 Pro, 3 Kimi K2 0905, 4 Claude Haiku 4.5 (final), 5 Claude
-- Sonnet 4.6 (off). Nothing else changes: the same contract (cf247-intake-validation v1.2.0), checks and daily limit.
-- Then: the waiting intake reviews that step 1 alone produced for a checking reason that a stronger step can settle
-- ("quoted text not on the saved page", "did not pass the automatic checks") and that have no value on record are sent
-- back once through the full ladder, as 20261002184300 did for English. Reviews whose page names only a study period
-- ("Semester 1") are NOT sent back: no model can turn those into months under v1.2.0; they wait for the calendar step.
update pipeline.layer3_route_tiers set tier_no = 5, updated_at = now()
 where task_class = 'provider_intake_validation' and tier_no = 3 and active = false
   and profile_id = (select id from pipeline.layer3_model_profiles where code = 'openrouter-intake-l3r-claude-sonnet-4-6-v1');
update pipeline.layer3_route_tiers set tier_no = 4, updated_at = now()
 where task_class = 'provider_intake_validation' and tier_no = 2
   and profile_id = (select id from pipeline.layer3_model_profiles where code = 'openrouter-intake-l3r-claude-haiku-4-5-v1');

do $l$
declare r record; v_n int; v_ok int; v_wrong int; v_cost numeric;
begin
  for r in select * from (values ('openrouter-intake-l3c-mimo-v2-6-pro-v1', 2, 'q-intake-mimo-v2-6-pro-h1'), ('openrouter-intake-l3c-kimi-k2-0905-v1', 3, 'q-intake-kimi-k2-0905-h1')) v(code, tier, run) loop
    select count(*), count(*) filter (where h.outcome in ('exact','exact_not_stated')), count(*) filter (where h.outcome = 'wrong_admitted'), avg(h.cost_usd)
      into v_n, v_ok, v_wrong, v_cost
      from pipeline.layer3_holdout_results h join pipeline.layer3_model_profiles p on p.id = h.profile_id join pipeline.layer3_holdout_cases c on c.id = h.case_id
     where p.code = r.code and c.task_class = 'provider_intake_validation' and c.gold_set = 'l3r-intake-h1' and h.run_label = r.run;
    if v_n < 30 or v_ok::numeric / v_n < 0.80 or v_wrong > 0 then raise exception 'Intake step % (%) does not meet the rule: % of % right, % wrong', r.tier, r.code, v_ok, v_n, v_wrong; end if;
    if exists (select 1 from pipeline.layer3_route_tiers where task_class = 'provider_intake_validation' and tier_no = r.tier) then raise exception 'Intake tier % is still taken', r.tier; end if;
    insert into pipeline.layer3_route_tiers(task_class, tier_no, profile_id, min_success, cost_per_call_usd, h1_success_rate, h1_wrong_admitted, is_final, qualified_by, active)
    select 'provider_intake_validation', r.tier, p.id, 0.80, round(v_cost, 6), round(v_ok::numeric / v_n, 4), v_wrong, false,
           jsonb_build_object('holdout_cases', v_n, 'right', v_ok, 'wrong_admitted', v_wrong, 'run_label', r.run,
             'rule', 'at least 30 cases, at least 80% right and 0 wrong-admitted on the frozen holdout (cascade admission rule, Platform Admin 29 Sep 2026)',
             'direction', 'Platform Admin multiple choice, 3 Oct 2026 08:45'), true
      from pipeline.layer3_model_profiles p where p.code = r.code;
    update pipeline.layer3_model_profiles set enabled = true, paused = false, updated_at = now() where code = r.code;
  end loop;
end $l$;

update pipeline.layer3_route_tiers t
   set is_final = (t.active and t.tier_no = (select max(tier_no) from pipeline.layer3_route_tiers where task_class = 'provider_intake_validation' and active)), updated_at = now()
 where t.task_class = 'provider_intake_validation';

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('layer3', 'switch_on', 'Intake cascade: MiMo v2.6 Pro step 2, Kimi K2 0905 step 3; Haiku 4.5 final at step 4',
        jsonb_build_object('decision', 'Platform Admin multiple choice, 3 Oct 2026 08:45', 'rule', 'cascade admission rule (>=80% right, 0 wrong)'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

with l4 as (
  update pipeline.layer4_review_items l set status = 'superseded', decided_at = now(),
         escalation_reason = 'Superseded: sent back to Layer 3 for the intake cascade with MiMo and Kimi as steps 2 and 3 (was: ' || left(l.escalation_reason, 120) || ').'
   where l.status = 'pending' and l.layer3_interpretation_id is not null and l.before_value is null
     and l.field_code = 'course_intake'
     and (l.escalation_reason like 'The AI quoted text that is not on the saved page%' or l.escalation_reason like 'The AI''s answer did not pass the automatic checks%')
  returning l.layer3_interpretation_id),
fact as (
  update pipeline.layer3_work_items w set status = 'failed', updated_at = now(), last_error = 'released: sent back to Layer 3 for the MiMo and Kimi intake steps (3 Oct 2026)'
    from l4 where w.interpretation_id = l4.layer3_interpretation_id and w.status = 'layer4_required'
  returning w.id)
update pipeline.layer3_fact_handoffs h set work_item_id = null, attempts = 0 from fact where h.work_item_id = fact.id;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('requeue', 'send_back', 'Intakes: checking failures with no value on record, for the MiMo and Kimi steps', jsonb_build_object('decision', 'Intake steps 2 and 3 switched on, 3 Oct 2026'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
