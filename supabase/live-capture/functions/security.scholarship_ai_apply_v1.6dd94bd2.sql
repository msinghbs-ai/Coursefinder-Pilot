CREATE OR REPLACE FUNCTION security.scholarship_ai_apply_v1(p_extraction bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare e pipeline.scholarship_ai_extractions%rowtype; v_facts jsonb; v_rule jsonb; r jsonb; v_sid uuid; v_aud text;
begin
  select * into e from pipeline.scholarship_ai_extractions where id = p_extraction;
  if e.id is null or e.error is not null or e.answer is null then return jsonb_build_object('applied', false, 'reason', 'no answer'); end if;
  v_aud := case e.answer->>'audience' when 'international' then 'international' when 'both' then 'international_and_domestic' when 'domestic' then 'domestic' else null end;
  if e.candidate_id is not null then
    select c.facts into v_rule from pipeline.scholarship_page_candidates c where c.id = e.candidate_id;
    v_facts := security.scholarship_ai_facts_v1(e.answer, e.checks, coalesce(v_rule->'rules', v_rule), e.model_code || ' / instructions v' || e.prompt_version) || jsonb_build_object('rules', coalesce(v_rule->'rules', v_rule));
    update pipeline.scholarship_page_candidates set facts = v_facts, admit_status = null, admit_reasons = null, read_status = 'read' where id = e.candidate_id and admitted_scholarship_id is null;
    if coalesce((v_facts->'admission'->>'admit')::boolean, false) then
      r := security.scholarship_admit_from_provider_page_v1(e.candidate_id);
      v_sid := (r->>'scholarship_id')::uuid;
      if coalesce((r->>'admitted')::boolean, false) and v_aud is not null then update scholarship.scholarships set audience = v_aud, updated_at = now() where id = v_sid; end if;
    else
      update pipeline.scholarship_page_candidates set admit_status = 'rejected', admit_reasons = array(select jsonb_array_elements_text(v_facts->'admission'->'reasons')) where id = e.candidate_id;
      insert into pipeline.scholarship_admission_log(candidate_id, provider_id, action, detail) values (e.candidate_id, e.provider_id, 'rejected', jsonb_build_object('by', 'ai', 'extraction', e.id, 'reasons', v_facts->'admission'->'reasons'));
      r := jsonb_build_object('admitted', false, 'reasons', v_facts->'admission'->'reasons');
    end if;
  elsif e.scholarship_id is not null then
    select sp.facts into v_rule from pipeline.scholarship_pages sp where sp.scholarship_id = e.scholarship_id;
    v_facts := security.scholarship_ai_facts_v1(e.answer, e.checks, coalesce(v_rule->'rules', v_rule), e.model_code || ' / instructions v' || e.prompt_version) || jsonb_build_object('rules', coalesce(v_rule->'rules', v_rule));
    update pipeline.scholarship_pages set facts = v_facts, read_status = 'read', evidence_id = coalesce(e.evidence_id, evidence_id) where scholarship_id = e.scholarship_id;
    if not coalesce((v_facts->'admission'->>'admit')::boolean, false) and exists (select 1 from pipeline.scholarship_pages where scholarship_id = e.scholarship_id and url_source = 'admitted') then
      r := security.scholarship_admission_withdraw_v1(e.scholarship_id, jsonb_build_object('reasons', v_facts->'admission'->'reasons', 'extractor', v_facts->>'extractor', 'by', 'ai'));
    else
      r := security.scholarship_sweep_apply_v1(e.scholarship_id);
      if v_aud is not null then update scholarship.scholarships set audience = v_aud, updated_at = now() where id = e.scholarship_id and audience is distinct from v_aud; end if;
      -- v2.15.250: an automatic hold is released when this answer passes every publish check; a hold a person made stays
      if exists (select 1 from pipeline.scholarship_publication_holds h where h.scholarship_id = e.scholarship_id and h.released_at is null and h.held_by = 'auto')
         and exists (select 1 from security.scholarship_publishability_for_v1(array[e.scholarship_id]) p where not exists (select 1 from unnest(p.missing) x where x ilike '%held%' is not true)) then
        update pipeline.scholarship_publication_holds set released_at = now(), release_note = 'AI re-read passes every publish check (v2.15.250)' where scholarship_id = e.scholarship_id;
        r := coalesce(r, '{}'::jsonb) || jsonb_build_object('auto_hold_released', true);
      end if;
    end if;
  end if;
  update pipeline.scholarship_ai_extractions set applied = coalesce(r, '{}'::jsonb) || jsonb_build_object('at', now()) where id = e.id;
  return r;
end $function$
