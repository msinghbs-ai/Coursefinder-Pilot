CREATE OR REPLACE FUNCTION security.course_description_check_v1(p_course uuid, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_s jsonb := coalesce(p_result->'sentences', '[]'::jsonb); v_n int; v_text text; s jsonb; t text; v_sup numeric; v_other record; v_pid uuid;
        v_min_sup numeric := security.pipeline_num_v1('pdesc.support_min_share', 0.6); v_dup numeric := security.pipeline_num_v1('pdesc.duplicate_share', 0.8);
        v_checks jsonb;
begin
  select c.provider_id into v_pid from catalogue.courses c where c.id = p_course;
  v_n := jsonb_array_length(v_s);
  v_text := (select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements(v_s) with ordinality e(x, o));
  v_checks := jsonb_build_object('sentences', v_n, 'chars', length(coalesce(v_text, '')));
  if coalesce((p_result->>'about_course')::boolean, false) is false or v_n = 0 then
    return jsonb_build_object('ok', false, 'rule', 'not_stated', 'checks', v_checks, 'reason', 'the page does not state it');
  end if;
  if v_n < security.pipeline_num_v1('enrich.course_description_min_sentences', 1) or v_n > security.pipeline_num_v1('enrich.course_description_max_sentences', 4) then
    return jsonb_build_object('ok', false, 'rule', 'sentence_count', 'checks', v_checks, 'reason', v_n || ' sentence(s), outside the set range');
  end if;
  for s in select x from jsonb_array_elements(v_s) x loop
    t := btrim(coalesce(s->>'text', ''));
    if coalesce((s->>'on_page')::boolean, false) is false or nullif(btrim(coalesce(s->>'quote', '')), '') is null then
      return jsonb_build_object('ok', false, 'rule', 'quote_not_on_page', 'checks', v_checks, 'reason', 'a sentence''s words are not on the course page: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb)) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'rule', 'unsupported_marketing', 'checks', v_checks, 'reason', 'a marketing word that is not in the quote: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'rule', 'unsupported_claim', 'checks', v_checks, 'reason', 'a ranking, outcome or accreditation claim that is not in the quote: ' || left(t, 120));
    end if;
    -- a sentence that does not end as a sentence is a fragment: held, never cut or completed (Platform Admin 2 Nov 2026 23:24)
    if t !~ '[.!?]["'')\]’”]*$' or t ~ '(\.\.\.|…)["'')\]’”]*$' then
      return jsonb_build_object('ok', false, 'rule', 'incomplete_sentence', 'checks', v_checks, 'reason', 'a sentence is not complete (it would be published as a fragment): ' || left(t, 120));
    end if;
    v_sup := security.pdesc_support_v1(t, s->>'quote');
    if v_sup < v_min_sup then
      return jsonb_build_object('ok', false, 'rule', 'unsupported_sentence', 'checks', v_checks || jsonb_build_object('support', v_sup),
        'reason', 'a sentence is not supported by its quote (' || v_sup || '): ' || left(t, 120));
    end if;
  end loop;
  if length(v_text) < security.pipeline_num_v1('enrich.course_description_min_chars', 80) or length(v_text) > security.pipeline_num_v1('enrich.course_description_max_chars', 700) then
    return jsonb_build_object('ok', false, 'rule', 'length', 'checks', v_checks, 'reason', length(v_text) || ' characters, outside the set range (held whole, never cut)');
  end if;
  -- boilerplate: the same words as another course of the provider (held, or waiting in Layer 4)
  select z.course_id, z.sim into v_other from (
    select x.course_id, security.pdesc_similarity_v1(v_text, x.d) sim from (
      select c.id course_id, c.description d, c.updated_at at from catalogue.courses c
       where c.provider_id = v_pid and c.id <> p_course and nullif(btrim(c.description), '') is not null
      union all
      select r.entity_id, r.proposed_value->>'description', r.created_at from pipeline.layer4_review_items r join catalogue.courses c on c.id = r.entity_id
       where r.entity_type = 'course' and r.field_code = 'course_description_first_read' and r.status = 'pending' and c.provider_id = v_pid and r.entity_id <> p_course
      order by 3 desc limit security.pipeline_num_v1('enrich.course_description_duplicate_window', 500)::int) x) z
   where z.sim >= v_dup order by z.sim desc limit 1;
  if v_other.course_id is not null then
    return jsonb_build_object('ok', false, 'rule', 'duplicate_other_course', 'checks', v_checks || jsonb_build_object('duplicate_of', v_other.course_id, 'similarity', v_other.sim),
      'reason', 'the same words as another course''s description (' || v_other.sim || '): text that is not about this course');
  end if;
  return jsonb_build_object('ok', true, 'rule', 'ok', 'text', v_text, 'checks', v_checks, 'reason', null);
end $function$
