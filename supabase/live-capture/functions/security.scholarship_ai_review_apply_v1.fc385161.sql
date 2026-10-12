CREATE OR REPLACE FUNCTION security.scholarship_ai_review_apply_v1(p_review bigint, p_decision text, p_extraction bigint, p_note text, p_by uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v pipeline.scholarship_ai_reviews%rowtype; e pipeline.scholarship_ai_extractions%rowtype; v_ans jsonb; v_chk jsonb; v_id bigint; r jsonb; v_pv int;
begin
  select * into v from pipeline.scholarship_ai_reviews where id = p_review for update;
  if v.id is null then raise exception 'no such review'; end if;
  if p_decision = 'admit' then
    select * into e from pipeline.scholarship_ai_extractions where id = coalesce(p_extraction,
      (select x.id from pipeline.scholarship_ai_extractions x where x.id = any (v.extraction_ids) and x.answer is not null order by coalesce((x.answer->>'is_scholarship')::boolean, false) desc, x.at desc limit 1));
    if e.id is null or e.answer is null then raise exception 'no model answer to admit; read the page again first'; end if;
    v_ans := e.answer || jsonb_build_object('is_scholarship', true, 'single_scholarship', true,
               'audience', case when e.answer->>'audience' in ('international', 'both') then e.answer->>'audience' else 'international' end,
               'audience_quote', case when e.answer->>'audience' in ('international', 'both') then e.answer->>'audience_quote' else 'Confirmed by a person in Layer 4' end,
               'offered', 'yes', 'name', coalesce(nullif(e.answer->>'name', ''), 'Scholarship'));
    v_chk := coalesce(e.checks, '{}'::jsonb) || jsonb_build_object('name', true, 'audience', true, 'offered', true, 'value', coalesce(e.answer->'value'->>'kind', 'not_stated') not in ('not_stated', 'non_monetary'),
               'levels', jsonb_array_length(coalesce(e.answer->'levels', '[]'::jsonb)) > 0, 'dates', coalesce((e.checks->>'dates')::boolean, false), 'by_person', true);
    select p.version into v_pv from pipeline.scholarship_ai_prompts p where p.active order by p.version desc limit 1;
    insert into pipeline.scholarship_ai_extractions(queue_id, model_code, model_identifier, prompt_version, run_kind, candidate_id, scholarship_id, provider_id, url, storage_path, content_hash, evidence_id, answer, checks, verdict, cost_usd, error)
    values (e.queue_id, 'person', 'person', coalesce(v_pv, e.prompt_version), 'review', v.candidate_id, v.scholarship_id, v.provider_id, v.url, coalesce(v.storage_path, e.storage_path), e.content_hash, e.evidence_id, v_ans, v_chk, 'scholarship', 0, null)
    returning id into v_id;
    r := security.scholarship_ai_apply_v1(v_id);
  elsif p_decision = 'refuse' then
    if v.candidate_id is not null then
      update pipeline.scholarship_page_candidates set admit_status = 'rejected', admit_reasons = array['refused_by_person'] where id = v.candidate_id and admitted_scholarship_id is null;
      insert into pipeline.scholarship_admission_log(candidate_id, provider_id, action, detail) values (v.candidate_id, v.provider_id, 'rejected', jsonb_build_object('by', 'person', 'review', v.id, 'note', p_note));
    end if;
    if v.scholarship_id is not null then
      insert into pipeline.scholarship_publication_holds(scholarship_id, reason, held_by, held_at)
      values (v.scholarship_id, 'Refused in Layer 4 › AI could not decide: ' || coalesce(p_note, ''), 'admin', now())
      on conflict (scholarship_id) do update set reason = excluded.reason, held_by = 'admin', held_at = now(), released_at = null, release_note = null;
    end if;
    r := jsonb_build_object('refused', true);
  else raise exception 'decide admit or refuse';
  end if;
  update pipeline.scholarship_ai_reviews set status = case when p_decision = 'admit' then 'admitted' else 'refused' end, decided_by = p_by, decided_at = now(), note = p_note,
         decision = jsonb_build_object('decision', p_decision, 'extraction', coalesce(v_id, p_extraction), 'applied', r) where id = v.id;
  return coalesce(r, '{}'::jsonb) || jsonb_build_object('review', v.id, 'decision', p_decision);
end $function$
