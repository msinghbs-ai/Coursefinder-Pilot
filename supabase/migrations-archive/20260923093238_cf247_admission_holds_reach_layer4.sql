-- CF-CHG-20260915-247: admission holds reach Layer 4.
-- Previously a held item was set to admission_pending with no review item, so no
-- person would ever see it. Every hold now creates a Layer 4 review item with a
-- plain-English reason (what happened, what to check) and moves the work item to
-- layer4_required; the technical reason is kept in layer3_state and last_error.
-- Admission rules themselves are unchanged.
-- ========== 5. Deterministic Layer 3 tuition admission ==========
create or replace function security.layer3_tuition_admit_validated_v1(p_limit integer default 25)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','pipeline','catalogue','security','search','ref' as $$
declare
  v_caller text; r record; v_hold text; v_plain text; v_fee_label text; v_key text; v_min numeric; v_cand jsonb;
  v_amount numeric; v_cur text; v_basis text; v_year int; v_aud text; v_fee uuid;
  v_ex_amount numeric; v_ex_cur text;
  v_admitted int := 0; v_already int := 0; v_held int := 0; v_refresh jsonb; v_items jsonb := '[]'::jsonb;
begin
  v_caller := coalesce(nullif(current_setting('request.jwt.claim.role',true),''),nullif(current_setting('request.jwt.role',true),''),session_user);
  if v_caller not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;

  for r in
    select w.id wid, w.entity_id course_id, w.evidence_id, w.interpretation_id,
           i.candidate_value cv, i.confidence, i.validator_result vr, i.aggregator_response_model model,
           p.deterministic_validators dv, c.course_code, e.source_id
    from pipeline.layer3_work_items w
    join pipeline.layer3_interpretations i on i.id = w.interpretation_id
    join pipeline.layer3_model_profiles p on p.id = i.profile_id
    left join catalogue.courses c on c.id = w.entity_id
    left join pipeline.evidence_artifacts e on e.id = w.evidence_id
    where w.task_class = 'provider_current_tuition_validation' and w.status = 'validated'
    order by w.completed_at nulls last, w.id
    limit least(greatest(coalesce(p_limit,25),1),100)
    for update of w skip locked
  loop
    v_hold := null; v_cand := r.cv;
    v_min := coalesce(nullif(r.dv->>'review_confidence_min','')::numeric, 0.9);
    v_amount := nullif(v_cand->>'amount','')::numeric;
    v_cur := upper(nullif(btrim(coalesce(v_cand->>'currency_code', v_cand->>'currency')),''));
    v_basis := nullif(btrim(v_cand->>'basis'),'');
    v_year := nullif(v_cand->>'fee_year','')::int;
    v_aud := lower(coalesce(nullif(btrim(v_cand->>'audience'),''),''));
    v_plain := null;
    v_fee_label := case when v_amount is null then 'the fee'
                  else case coalesce(v_cur,'') when 'AUD' then 'A$' when 'NZD' then 'NZ$' else coalesce(v_cur||' ','') end
                       || to_char(v_amount,'FM999,999,999.##') end;
    v_fee_label := rtrim(v_fee_label,'.');

    if v_cand is null or jsonb_typeof(v_cand) <> 'object' then v_hold := 'no candidate value'; v_plain := 'The AI''s answer was empty, so nothing could be recorded. Please check the page and confirm the fee.';
    elsif coalesce((r.vr->>'valid')::boolean,false) is not true or coalesce((r.vr->>'candidate_bound')::boolean,false) is not true then v_hold := 'validator result is not valid and candidate-bound'; v_plain := format('The AI''s answer for %s didn''t pass the automatic checks. Please check the page and confirm the fee.', v_fee_label);
    elsif r.confidence is null or r.confidence < v_min then v_hold := format('confidence %s is below the admission threshold %s', r.confidence, v_min); v_plain := format('The AI was only %s%% confident that %s is the annual international tuition fee (%s%% is needed). Please check the page.', round(coalesce(r.confidence,0)*100), v_fee_label, round(v_min*100));
    elsif v_amount is null or v_amount <= 0 then v_hold := 'amount is not positive'; v_plain := 'The fee amount wasn''t a valid positive number. Please check the page and enter the correct fee.';
    elsif v_aud <> 'international' then v_hold := 'audience is not international'; v_plain := format('%s isn''t clearly a fee for international students. Please confirm who this fee applies to.', v_fee_label);
    elsif r.dv ? 'allowed_currencies' and not (r.dv->'allowed_currencies' ? coalesce(v_cur,'')) then v_hold := format('currency %s is not allowed', v_cur); v_plain := format('The fee on the page (%s) isn''t in Australian or New Zealand dollars, so it can''t be recorded automatically. Please confirm the fee.', v_fee_label);
    elsif r.dv ? 'allowed_basis' and not (r.dv->'allowed_basis' ? coalesce(v_basis,'')) then v_hold := format('basis %s is not allowed', v_basis); v_plain := format('We can''t tell whether %s is charged per year. Please confirm whether it is an annual fee.', v_fee_label);
    elsif r.dv ? 'amount_max' and v_amount > (r.dv->>'amount_max')::numeric then v_hold := 'amount is above the profile ceiling'; v_plain := format('%s is higher than the usual maximum, so it needs a person to check it. Please confirm the fee.', v_fee_label);
    elsif r.course_code is null then v_hold := 'course code unavailable'; v_plain := format('We couldn''t identify the course record for this fee. Please check the course before confirming %s.', v_fee_label);
    elsif r.source_id is null then v_hold := 'Evidence has no source'; v_plain := format('The saved page isn''t linked to a known source, so %s can''t be recorded automatically. Please check the page and confirm the fee.', v_fee_label);
    elsif not exists(select 1 from ref.currencies where code = v_cur) then v_hold := format('currency %s is not seeded', v_cur); v_plain := format('%s isn''t set up as a currency yet. Please review %s manually.', coalesce(v_cur,'This currency'), v_fee_label);
    end if;

    if v_hold is null then
      -- same fee key convention as the Layer 2 writer (svc_coursefacts_apply_record)
      v_key := lower(upper(btrim(r.course_code))||':'||v_aud||':'||coalesce(v_year::text,'current')||':'||coalesce(v_basis,'tuition'));
      v_fee := null;
      insert into catalogue.course_fees(course_id,fee_year,audience,fee_type,amount,currency_code,basis,notes,source_id,evidence_id,confidence,campus_id,source_fee_key,status,last_verified_at,source_snapshot_at,updated_at)
      values (r.course_id,v_year,v_aud,'provider_current_tuition',v_amount,v_cur,v_basis,
              format('CF-247 Layer 3 admission; interpretation %s; model %s', r.interpretation_id, coalesce(r.model,'unknown')),
              r.source_id,r.evidence_id,r.confidence,null,v_key,'active',now(),now(),now())
      on conflict(course_id,source_id,source_fee_key) where source_id is not null and source_fee_key is not null do nothing
      returning id into v_fee;
      if v_fee is null then
        select amount, currency_code into v_ex_amount, v_ex_cur from catalogue.course_fees
        where course_id = r.course_id and source_id = r.source_id and source_fee_key = v_key;
        if v_ex_amount = v_amount and btrim(v_ex_cur) = v_cur then
          update pipeline.layer3_work_items set status='admitted', completed_at=now(), updated_at=now(),
            last_error='admitted: identical fee already present' where id = r.wid;
          v_already := v_already + 1;
          v_items := v_items || jsonb_build_object('work_item_id', r.wid, 'result', 'already_present');
          continue;
        end if;
        v_hold := format('conflicts with existing fee %s %s for the same key', v_ex_amount, v_ex_cur); v_plain := format('A different fee (%s%s) is already recorded for this course from the same source, so %s wasn''t added. Please decide which one is correct.', case btrim(v_ex_cur) when 'AUD' then 'A$' when 'NZD' then 'NZ$' else btrim(v_ex_cur)||' ' end, to_char(v_ex_amount,'FM999,999,999'), v_fee_label);
      end if;
    end if;

    if v_hold is not null then
      -- CF-247: every hold reaches the Layer 4 queue with a plain-English reason;
      -- the technical reason stays in layer3_state and on the work item.
      insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, layer3_interpretation_id,
        layer2_state, layer3_state, status, escalation_reason, change_control_ref)
      values ('course', r.course_id, 'provider_current_tuition_validation', r.evidence_id, r.interpretation_id,
        '{}'::jsonb, jsonb_build_object('admission_hold', v_hold, 'candidate_value', r.cv, 'confidence', r.confidence),
        'pending', coalesce(v_plain, format('The AI''s answer for %s couldn''t be recorded automatically. Please check the page and confirm the fee.', v_fee_label)),
        'CF-CHG-20260915-247');
      update pipeline.layer3_work_items set status='layer4_required', updated_at=now(),
        last_error=left('admission held for human review: '||v_hold,500) where id = r.wid;
      v_held := v_held + 1;
      v_items := v_items || jsonb_build_object('work_item_id', r.wid, 'result', 'held', 'reason', v_hold);
      continue;
    end if;

    update pipeline.layer3_work_items set status='admitted', completed_at=now(), updated_at=now(), last_error=null where id = r.wid;
    v_admitted := v_admitted + 1;
    v_items := v_items || jsonb_build_object('work_item_id', r.wid, 'result', 'admitted', 'course_fee_id', v_fee, 'amount', v_amount, 'currency', v_cur, 'basis', v_basis);
  end loop;

  if v_admitted > 0 then v_refresh := search.refresh_course_enrichment_v1(true); end if;
  return jsonb_build_object('ok', true, 'admitted', v_admitted, 'already_present', v_already, 'held_for_review', v_held,
    'projection_refreshed', v_refresh is not null, 'items', v_items, 'change_control_ref', 'CF-CHG-20260915-247');
end $$;
revoke all on function security.layer3_tuition_admit_validated_v1(integer) from public, anon, authenticated;
grant execute on function security.layer3_tuition_admit_validated_v1(integer) to service_role;
