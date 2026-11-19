CREATE OR REPLACE FUNCTION security.course_description_machine_admit_v1(p_item uuid, p_via text DEFAULT 'settle'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.layer4_review_items%rowtype; c catalogue.courses%rowtype; v jsonb; v_text text; v_after text; v_pub jsonb; v_shown text; v_cc text; v_dec uuid; v_reason text; v_msg text; v_stamp text; v_next text; v_tr boolean; v_sub jsonb;
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150'; -- fixed: the system automation account that records Decision 263 rule decisions
        v_rule constant text := 'cdesc-machine-v2'; v_ref constant text := 'CF-247 F-CDESC; Platform Admin decision 10 Nov 2026 (course descriptions: source-verified machine admission)';
        v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int; -- derived: a decline is looked at again after the days the queue reads a course again
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('ok', false, 'rule', 'machine_admission_off'); end if;
  select * into i from pipeline.layer4_review_items where id = p_item for update;
  if i.id is null or i.entity_type <> 'course' or i.field_code <> 'course_description_first_read' then return jsonb_build_object('ok', false, 'rule', 'not_a_course_description_item'); end if;
  if i.status <> 'pending' then return jsonb_build_object('ok', false, 'rule', 'item_not_pending', 'status', i.status); end if;
  select * into c from catalogue.courses where id = i.entity_id for update;
  v_stamp := security.course_description_machine_policy_stamp_v1();
  v := security.course_description_machine_check_v1(p_item);
  if coalesce((v->>'ok')::boolean, false) then
    v_text := v->>'text';
    -- a reading that carries a subset (security.cdesc_subset_recover_v1): the admission says so, in its own via and in its reason
    select f.value->'subset_of_reading' into v_sub from pipeline.field_enrich_items f where f.id = (v->>'reading_item_id')::bigint;
    if v_sub is not null then p_via := 'subset_of_reading'; v_sub := v_sub - 'original'; end if;
    begin
      -- the one write, proved on the row: a guard that put the old text back (a hand lock) must stop the admission, not leave an audit that says it was published
      update catalogue.courses set description = v_text, updated_at = now() where id = c.id and nullif(btrim(description), '') is null;
      select nullif(btrim(x.description), '') into v_after from catalogue.courses x where x.id = c.id;
      if v_after is distinct from v_text then raise exception 'cdesc:description_not_written:the catalogue kept the earlier text (a lock or guard put it back)'; end if;
      -- the consumer read-back (read only): what the website function returns for this course now
      begin v_pub := public.website_v2_course(c.stable_key); exception when others then v_pub := null; end;
      v_shown := v_pub->'item'->>'description';
      v_cc := case when v_pub is null then 'error' when v_pub ? 'error' then 'not_in_feed' when v_shown = v_text then 'matched' when nullif(btrim(v_shown), '') is null then 'lag' else 'mismatch' end;
      if v_cc = 'mismatch' then raise exception 'cdesc:consumer_mismatch:the website function shows different text for this course after the write'; end if;
      update pipeline.layer4_review_items set status = 'approved', decided_at = now() where id = i.id and status = 'pending';
      v_reason := format('Auto (%s, %s): description read from the course''s own stored page %s (content hash %s); right course and page (identity proof and a margin of at least 0.1 over the runner-up), the quote results the worker stored for each sentence, the sentence, length, support and duplicate checks and the wording policy checked again at admission (the page was not read again). Not a person''s decision.',
                         v_rule, coalesce(p_via, 'settle'), coalesce(v->>'source_url', ''), left(coalesce(v->>'content_hash', ''), 12)); -- fixed: a short hash prefix is shown for reading, the full hash is stored
      if v_sub is not null then
        v_reason := v_reason || format(' Subset of the reading: %s of its %s sentences were kept in their original order; set aside: %s. Nothing was reworded, added or cut; the original reading, its quotes and its history are kept.',
                                       v_sub->>'kept_count', v_sub->>'original_count', coalesce((select string_agg('sentence ' || (d->>'index') || ' (' || (d->>'cause') || ')', ', ' order by (d->>'index')::int) from jsonb_array_elements(v_sub->'dropped') d), 'none'));
      end if;
      insert into pipeline.layer4_decisions (review_item_id, action, actor_id, reason, before_value, proposed_value, final_value, evidence_id, layer2_state, layer3_state, change_control_ref)
      values (i.id, 'approve', v_sys, v_reason, i.before_value, i.proposed_value, i.proposed_value, i.evidence_id,
              coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'actor_kind', 'machine', 'via', coalesce(p_via, 'settle')) || case when v_sub is not null then jsonb_build_object('subset_of_reading', v_sub) else '{}'::jsonb end, coalesce(i.layer3_state, '{}'::jsonb), v_ref) returning id into v_dec;
      insert into pipeline.admin_control_events (area, action, target, detail, actor)
      values ('layer4', 'inbox_decide', i.id::text, jsonb_build_object('kind', 'course_description', 'ref', i.id::text, 'choice', 'approve', 'reason', v_reason, 'course_id', c.id, 'provider_id', c.provider_id,
              'auto', true, 'machine_rule', v_rule, 'actor_kind', 'machine', 'decision_id', v_dec, 'field_code', i.field_code, 'consumer_check', v_cc), v_sys);
      insert into pipeline.search_refresh_signals (entity_type, entity_id, review_decision_id, reason, change_control_ref)
      values ('course', c.id, v_dec, 'Accepted machine-rule Layer 4 canonical change: ' || v_reason, v_ref);
      insert into pipeline.course_description_machine_admissions (course_id, provider_id, review_item_id, reading_item_id, rule, outcome, reason_code, reason, policy_stamp, before_description, after_description, text_md5,
             evidence_id, content_hash, source_url, storage_path, model, prompt_version, worker, checks, recovery, consumer_check, consumer_checked_at, actor)
      values (c.id, c.provider_id, i.id, (v->>'reading_item_id')::bigint, v_rule, 'admitted', 'admitted', v_reason, v_stamp, null, v_text, v->>'text_md5',
              i.evidence_id, v->>'content_hash', v->>'source_url', v->>'storage_path', v->>'model', v->>'prompt_version', v->>'worker',
              coalesce(v->'checks', '{}'::jsonb) || jsonb_build_object('decision_id', v_dec, 'via', coalesce(p_via, 'settle'), 'source_recheck', v->>'source_recheck', 'captured_at', v->>'captured_at') || case when v_sub is not null then jsonb_build_object('subset_of_reading', v_sub) else '{}'::jsonb end,
              'Withdraw with public.admin_course_description_machine_withdraw_v1(course, reason) (Platform Admin): puts the empty description back if no person changed it and no lock was added since.',
              v_cc, now(), v_sys);
      return jsonb_build_object('ok', true, 'rule', v_rule, 'course_id', c.id, 'decision_id', v_dec, 'description_chars', length(v_text), 'consumer_check', v_cc);
    exception when others then
      get stacked diagnostics v_msg = message_text;
      v := security.cdesc_machine_fail_v1(case when v_msg like 'cdesc:%' then split_part(v_msg, ':', 2) else 'admission_error' end,
                                          case when v_msg like 'cdesc:%' then split_part(v_msg, ':', 3) else left(v_msg, 300) end, -- fixed: display width of the stored reason text
                                          'Nothing was written; the item still waits. A person decides in Layer 4, or the next run tries again.', v_msg not like 'cdesc:%' or v_msg like 'cdesc:consumer_mismatch:%'); -- a feed that disagrees is read again after an hour
    end;
  end if;
  -- declined: the item stays waiting with the exact reason on it; recorded once for the item and refreshed
  v_next := coalesce(v->>'next_action', 'A person decides in Layer 4.'); v_tr := coalesce((v->>'transient')::boolean, false);
  v_reason := coalesce(v->>'reason', 'The machine rule did not admit this.');
  insert into pipeline.course_description_machine_admissions (course_id, provider_id, review_item_id, reading_item_id, rule, outcome, reason_code, reason, next_action, transient, retry_after, policy_stamp, text_md5, evidence_id, actor)
  values (c.id, c.provider_id, i.id, case when coalesce(i.proposed_value->>'item_id', '') ~ '^\d+$' then (i.proposed_value->>'item_id')::bigint end, v_rule, 'declined', v->>'rule', v_reason, v_next, v_tr,
          now() + case when v_tr then make_interval(hours => 1) else make_interval(days => v_days) end, -- fixed: a transient decline is looked at again after an hour
          v_stamp, md5(coalesce(i.proposed_value->>'description', '')), i.evidence_id, v_sys)
  on conflict (review_item_id) where outcome = 'declined' do update set rule = excluded.rule, reason_code = excluded.reason_code, reason = excluded.reason, next_action = excluded.next_action, transient = excluded.transient,
         retry_after = excluded.retry_after, policy_stamp = excluded.policy_stamp, text_md5 = excluded.text_md5, evidence_id = excluded.evidence_id, created_at = now();
  update pipeline.layer4_review_items set escalation_reason = left('Machine rule ' || v_rule || ' did not admit this: ' || (v->>'rule') || '. ' || regexp_replace(coalesce(escalation_reason, ''), '^Machine rule [^:]*: [a-z0-9_]+\. ', ''), 1000) -- fixed: the item's reason column shows its first 1000 characters
   where id = i.id and coalesce(escalation_reason, '') not like 'Machine rule ' || v_rule || ' did not admit this: ' || (v->>'rule') || '.%';
  return jsonb_build_object('ok', false, 'rule', v->>'rule', 'reason', v_reason, 'next_action', v_next);
end $function$
