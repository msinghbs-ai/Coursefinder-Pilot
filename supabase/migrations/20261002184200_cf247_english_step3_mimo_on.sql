-- CF-247 (2 Oct 2026). Platform Admin, by multiple choice: "Add as English step 3". MiMo v2.6 Pro (xiaomi/mimo-v2.6-pro,
-- profile openrouter-english-l3c-mimo-v2-6-pro-v1) passed qualification on the frozen holdout l3r-english-h1 today
-- (19 of 19 stated, 18 of 18 not stated, 0 wrong-admitted; Decision 230). It becomes step 3 of the English cascade, after
-- Qwen3 30B and Mistral Small 3.2, and the final step. Claude Sonnet 4.6 moves from step 3 to step 4 and stays off.
-- The tier is inserted with the same evidence check as the ladder (at least 30 cases, at least 80% right, 0 wrong).
update pipeline.layer3_route_tiers set tier_no = 4, updated_at = now()
 where task_class = 'provider_english_validation' and tier_no = 3 and active = false
   and profile_id = (select id from pipeline.layer3_model_profiles where code = 'openrouter-english-l3r-claude-sonnet-4-6-v1');

do $l$
declare v_n int; v_ok int; v_wrong int; v_cost numeric; v_code text := 'openrouter-english-l3c-mimo-v2-6-pro-v1';
begin
  select count(*), count(*) filter (where h.outcome in ('exact','exact_not_stated')), count(*) filter (where h.outcome = 'wrong_admitted'), avg(h.cost_usd)
    into v_n, v_ok, v_wrong, v_cost
    from pipeline.layer3_holdout_results h join pipeline.layer3_model_profiles p on p.id = h.profile_id join pipeline.layer3_holdout_cases c on c.id = h.case_id
   where p.code = v_code and c.task_class = 'provider_english_validation' and c.gold_set = 'l3r-english-h1';
  if v_n < 30 or v_ok::numeric / v_n < 0.80 or v_wrong > 0 then raise exception 'English step 3 (%) does not meet the rule: % of % right, % wrong', v_code, v_ok, v_n, v_wrong; end if;
  if exists (select 1 from pipeline.layer3_route_tiers where task_class = 'provider_english_validation' and tier_no = 3) then raise exception 'English tier 3 is still taken'; end if;
  insert into pipeline.layer3_route_tiers(task_class, tier_no, profile_id, min_success, cost_per_call_usd, h1_success_rate, h1_wrong_admitted, is_final, qualified_by, active)
  select 'provider_english_validation', 3, p.id, 0.80, round(v_cost, 6), round(v_ok::numeric / v_n, 4), v_wrong, true,
         jsonb_build_object('holdout_cases', v_n, 'right', v_ok, 'wrong_admitted', v_wrong, 'run_label', 'q-english-mimo-v2-6-pro-h1',
           'rule', '>=95% exact on stated cases and 0 wrong-admitted on the frozen holdout (Decision 230)', 'direction', 'Platform Admin multiple choice, 2 Oct 2026'), true
    from pipeline.layer3_model_profiles p where p.code = v_code;
end $l$;

update pipeline.layer3_model_profiles set enabled = true, paused = false, updated_at = now() where code = 'openrouter-english-l3c-mimo-v2-6-pro-v1';
update pipeline.layer3_route_tiers t
   set is_final = (t.active and t.tier_no = (select max(tier_no) from pipeline.layer3_route_tiers where task_class = 'provider_english_validation' and active)), updated_at = now()
 where t.task_class = 'provider_english_validation';
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('layer3', 'switch_on', 'English cascade step 3: MiMo v2.6 Pro (cf247-english-validation-v1.0.0)',
        jsonb_build_object('decision', 'Platform Admin multiple choice, 2 Oct 2026; Decision 230', 'profile', 'openrouter-english-l3c-mimo-v2-6-pro-v1'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
