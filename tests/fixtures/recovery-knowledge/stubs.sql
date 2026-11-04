-- Live shapes for the recovery-knowledge fixtures (CF-247, 4 Nov 2026). The root causes and remedies used by the cases are registered exactly as
-- live (read 4 Nov 2026 18:10 AEDT: detect rules, authorities, attempt and cool-down keys). Their action and verification functions are owned by
-- other changes (work continuity, Layer 4 readiness, fees) and are stood in here with their live signatures; the cases control what they find.
-- The controller, its Authorise step and the learning step are the real ones. Never a Supabase project.
set check_function_bodies = off;
create table if not exists fx.verify_pass (remedy text primary key, pass boolean not null);
create or replace function security.work_remedy_retry_parked_v1(p_issue bigint) returns jsonb language plpgsql security definer set search_path to '' as $$
declare n int;
begin
  update pipeline.work_items set stage = 'eligible', next_eligible_at = now(), updated_at = now() where lane = 'aer_technical' and stage = 'parked' and failure_class = 'technical_hold';
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'changed', n > 0, 'evidence', jsonb_build_object('released', n));
end $$;
create or replace function security.work_verify_recovered_v1(p_issue bigint) returns jsonb language sql stable security definer set search_path to '' as $$
  select jsonb_build_object('passed', n_left = 0 and n_rec > 0, 'measure', jsonb_build_object('condition_cleared', n_left = 0 and n_rec > 0, 'recovered', n_rec, 'still_held', n_left),
                            'evidence', n_rec || ' recovered, ' || n_left || ' still held')
    from (select count(*) filter (where recovered_at is not null) n_rec, count(*) filter (where stage in ('parked', 'eligible')) n_left
            from pipeline.work_items where lane = 'aer_technical' and failure_class = 'technical_hold') z
$$;
create or replace function security.layer4_remedy_recheck_v1(p_issue bigint) returns jsonb language sql security definer set search_path to '' as $$
  select jsonb_build_object('ok', true, 'changed', true, 'evidence', jsonb_build_object('rechecked', p_issue)) $$;
create or replace function security.layer4_remedy_recheck_verify_v1(p_issue bigint) returns jsonb language sql stable security definer set search_path to '' as $$
  select jsonb_build_object('passed', p, 'measure', jsonb_build_object('condition_cleared', p), 'evidence', case when p then 'approvals admitted and published' else 'approvals still not admitted' end)
    from (select coalesce((select v.pass from fx.verify_pass v where v.remedy = 'layer4_admission_recheck:' || p_issue), false) p) z $$;
create or replace function security.fee_integrity_recheck_v1(p_issue bigint) returns jsonb language sql security definer set search_path to '' as $$
  select jsonb_build_object('ok', true, 'changed', false, 'evidence', '["security.fee_integrity_measure_v1()"]'::jsonb) $$;
create or replace function security.fee_integrity_verify_v1(p_issue bigint) returns jsonb language sql stable security definer set search_path to '' as $$
  select jsonb_build_object('passed', false, 'measure', jsonb_build_object('condition_cleared', false), 'evidence', '["security.fee_integrity_measure_v1()"]'::jsonb) $$;

-- the attempt and cool-down settings those remedies name (live values)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values
 ('pipeline', 'layer4.remedy_max_attempts', 'x', 'number', '3'), ('pipeline', 'layer4.remedy_cooldown_minutes', 'x', 'number', '30'),
 ('pipeline', 'fees.integrity_max_attempts', 'x', 'number', '3'), ('pipeline', 'fees.integrity_cooldown_minutes', 'x', 'number', '60')
on conflict do nothing;
-- root causes and remedies as live
select security.ops_root_cause_register_v1('work_technical_hold', '{"class": "transient", "title": "Layer 4 items stay technically held", "detect": {"any": [{"fingerprint_like": ["work_blocked:%:technical_hold"]}], "priority": 20, "confidence": 0.85}}');
select security.ops_root_cause_register_v1('layer4_approval_not_admitted', '{"class": "rule", "title": "An approval did not reach the catalogue", "detect": {"any": [{"fingerprint_like": ["l4\\_not\\_admitted:%"]}], "priority": 49, "confidence": 0.8}}');
select security.ops_root_cause_register_v1('layer4_approval_not_published', '{"class": "rule", "title": "An approval did not reach the website", "detect": {"any": [{"fingerprint_like": ["l4\\_not\\_published:%"]}], "priority": 50, "confidence": 0.7}}');
select security.ops_root_cause_register_v1('fee_reader_units_misread', '{"class": "rule", "title": "The AI fee reader divided a fee by the unit load", "detect": {"any": [{"fingerprint_like": ["fee:ai\\_reader\\_credit\\_point\\_unit%", "fee:ai\\_reader\\_units%"]}], "route": "needs_release", "priority": 46, "confidence": 0.9}}');
select security.ops_remedy_register_v1('work_retry_technical', '{"title": "Give technically held items one more bounded check cycle", "treats": ["work_technical_hold"], "authority": "auto", "action_fn": "security.work_remedy_retry_parked_v1(bigint)", "verify_fn": "security.work_verify_recovered_v1(bigint)", "max_attempts_key": "ops.max_attempts", "cooldown_key": "ops.cooldown_minutes"}');
select security.ops_remedy_register_v1('layer4_admission_recheck', '{"title": "Check the approvals again (the projection may have refreshed), then verify none still fails", "treats": ["layer4_approval_not_admitted", "layer4_approval_not_published"], "authority": "auto", "action_fn": "security.layer4_remedy_recheck_v1(bigint)", "verify_fn": "security.layer4_remedy_recheck_verify_v1(bigint)", "max_attempts_key": "layer4.remedy_max_attempts", "cooldown_key": "layer4.remedy_cooldown_minutes"}');
select security.ops_remedy_register_v1('fee_integrity_recheck', '{"title": "Check that no AI fee is active on a held course or made by the old unit division", "treats": ["fee_reader_units_misread"], "authority": "auto", "action_fn": "security.fee_integrity_recheck_v1(bigint)", "verify_fn": "security.fee_integrity_verify_v1(bigint)", "max_attempts_key": "fees.integrity_max_attempts", "cooldown_key": "fees.integrity_cooldown_minutes"}');
