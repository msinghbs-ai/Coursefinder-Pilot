CREATE OR REPLACE FUNCTION security.layer4_boost_study_load_inbox_decide_v1(p_ref text, p_choice text, p_value text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.boost_study_load_reviews; v_val text; v_status text; v_n int := 0; v_ev bigint; v_returns text;
        v_reason text := coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Layer 4 Inbox: ' || p_choice);
begin
  select * into r from pipeline.boost_study_load_reviews where id::text = p_ref and status = 'open' for update;
  if not found then
    return jsonb_build_object('ok', false, 'kind', 'boost_study_load', 'choice', p_choice, 'ref', p_ref, 'request', 'This reading has already been settled; refresh the Inbox.');
  end if;
  v_val := case p_choice when 'accept_full_time' then 'full_time' when 'accept_part_time' then 'part_time' when 'accept_both' then 'both' end;
  if v_val is not null then
    if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = r.course_id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id')) then
      return jsonb_build_object('ok', false, 'kind', 'boost_study_load', 'choice', p_choice, 'ref', p_ref, 'request', 'A manual lock holds this course''s study load; it was not changed.');
    end if;
    update catalogue.courses set study_load = v_val, study_load_source = 'manual', study_load_evidence_id = r.evidence_id
     where id = r.course_id and study_load is null;
    get diagnostics v_n = row_count;
    v_status := case when v_n = 1 then 'accepted' else 'superseded' end;
    v_returns := case when v_n = 1 then 'The course''s study load is now ' || replace(v_val, '_', '-') || '.' else 'The course already had a study load; it was not changed.' end;
  elsif p_choice = 'not_stated' then
    v_status := 'not_stated'; v_returns := 'Recorded as not stated on the page.';
  elsif p_choice = 'dismiss' then
    v_status := 'dismissed'; v_returns := 'The reading is dismissed; nothing changed.';
  else
    raise exception 'unknown choice %', p_choice using errcode = '22023';
  end if;
  update pipeline.boost_study_load_reviews set status = v_status, decision = p_choice, decided_value = case when v_n = 1 then v_val end,
         reason = v_reason, decided_by = auth.uid(), decided_at = now() where id = r.id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', 'boost_study_load:' || p_ref, jsonb_build_object('kind', 'boost_study_load', 'ref', p_ref, 'choice', p_choice, 'value', v_val, 'reason', v_reason,
          'course_id', r.course_id, 'provider_id', r.provider_id, 'evidence_id', r.evidence_id, 'filled', v_n = 1), auth.uid()) returning id into v_ev;
  perform security.boost_study_load_review_feed_v1();
  return jsonb_build_object('ok', true, 'kind', 'boost_study_load', 'choice', p_choice, 'ref', p_ref, 'event_id', v_ev, 'returns', v_returns);
end $function$
