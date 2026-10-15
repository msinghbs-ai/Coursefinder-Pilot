CREATE OR REPLACE FUNCTION security.fee_rule_run_v1(p_rule_id bigint, p_apply boolean, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.fee_wording_rules%rowtype; m record; v_src uuid; v_fee uuid; n_ok int := 0; n_amb int := 0; n_has int := 0; n_locked int := 0;
        v_courses uuid[] := '{}'; v_op bigint;
begin
  select * into r from pipeline.fee_wording_rules where id = p_rule_id;
  if r.id is null then raise exception 'rule not found'; end if;
  for m in select * from security.fee_rule_matches(r.provider_id, r.phrase, r.url_pattern) loop
    if m.amounts > 1 then n_amb := n_amb + 1; continue; end if;
    if m.has_fee then n_has := n_has + 1; continue; end if;
    if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = m.course_id and l.field = 'tuition') then n_locked := n_locked + 1; continue; end if;
    if not p_apply then n_ok := n_ok + 1; continue; end if;
    select source_id into v_src from pipeline.evidence_artifacts where id = m.evidence_id;
    v_fee := null;
    insert into catalogue.course_fees(course_id, fee_year, audience, fee_type, amount, currency_code, basis, notes, source_id, evidence_id, confidence, source_fee_key, status, last_verified_at, source_snapshot_at, updated_at)
    values (m.course_id, m.fee_year, 'international', 'provider_current_tuition', m.amount, 'AUD', r.basis,
            format('CF-247 Layer 4 fee wording rule #%s (%s)', r.id, r.label), v_src, m.evidence_id, 1,
            'fee-rule:' || r.id || ':' || coalesce(m.fee_year::text, '') || ':' || r.basis, 'active', now(), now(), now())
    on conflict (course_id, source_id, source_fee_key) where source_id is not null and source_fee_key is not null do nothing
    returning id into v_fee;
    if v_fee is null then n_has := n_has + 1; continue; end if;
    update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
           escalation_reason = format('Settled by Layer 4 fee wording rule #%s (%s)', r.id, r.label)
     where entity_type = 'course' and entity_id = m.course_id and field_code = 'provider_current_tuition_validation' and status in ('pending','returned_layer3');
    update pipeline.layer3_work_items set status = 'admitted', completed_at = now(), last_error = null, updated_at = now()
     where entity_id = m.course_id and task_class = 'provider_current_tuition_validation' and status in ('pending','layer4_required','failed','no_candidate','rejected');
    insert into pipeline.fee_rule_admissions(rule_id, course_id, course_fee_id, amount, fee_year, basis, matched_text)
    values (r.id, m.course_id, v_fee, m.amount, m.fee_year, r.basis, m.matched_text);
    v_courses := v_courses || m.course_id; n_ok := n_ok + 1;
  end loop;
  if p_apply then
    update pipeline.fee_wording_rules set last_run_at = now(), admitted = admitted + n_ok where id = r.id;
    if n_ok > 0 then
      insert into pipeline.layer4_mass_operations(target_kind, action, actor_id, group_key, reason, before_count, affected_count, result, change_control_ref)
      values ('course_tuition', 'fee_wording_rule_run', coalesce(p_actor, r.approved_by, r.created_by), jsonb_build_object('rule_id', r.id, 'provider_id', r.provider_id, 'phrase', r.phrase),
              format('Fee wording rule #%s: %s', r.id, r.label), n_ok + n_amb + n_has + n_locked, n_ok,
              jsonb_build_object('admitted', n_ok, 'ambiguous', n_amb, 'already_had_fee', n_has, 'entered_by_hand', n_locked), 'CF-CHG-20260915-247');
      perform search.refresh_course_enrichment_scoped_v1(v_courses, true);
    end if;
  end if;
  return jsonb_build_object('mode', case when p_apply then 'run' else 'preview' end, 'admitted', n_ok, 'ambiguous', n_amb, 'already_had_fee', n_has, 'entered_by_hand', n_locked);
end $function$
