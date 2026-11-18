CREATE OR REPLACE FUNCTION security.cdesc_sentence_fault_v1(p_text text, p_quote text, p_on_page boolean, p_claim jsonb, p_mkt jsonb, p_min_support numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t text := btrim(coalesce(p_text, '')); v_sup numeric;
        v_run int := security.pipeline_num_v1('enrich.course_description_copy_run_words', 10)::int;
        v_gen jsonb := coalesce(security.toolset_setting('pipeline', 'enrich.course_description_generic_phrases'), '[]'::jsonb); v_sw text[]; v_qw text; i int;
begin
  -- the per-sentence tests of the course description check, in the order the check runs them; null when the sentence passes
  if coalesce(p_on_page, false) is false or nullif(btrim(coalesce(p_quote, '')), '') is null then
    return jsonb_build_object('rule', 'quote_not_on_page', 'reason', 'a sentence''s words are not on the course page: ' || left(t, 120));
  end if;
  if exists (select 1 from jsonb_array_elements_text(p_mkt) w where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(p_quote, w)) then
    return jsonb_build_object('rule', 'unsupported_marketing', 'reason', 'a marketing word that is not in the quote: ' || left(t, 120));
  end if;
  if exists (select 1 from jsonb_array_elements_text(p_claim) w where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(p_quote, w) and not security.cdesc_learner_word_ok_v1(w, t, p_quote)) then
    return jsonb_build_object('rule', 'unsupported_claim', 'reason', 'a ranking, outcome or accreditation claim that is not in the quote: ' || left(t, 120));
  end if;
  -- cdesc-source-grounded-v1 (CF-247 F-CDESC, 12 Nov 2026): a stock phrase that says nothing about this course is held, whatever the page says
  if exists (select 1 from jsonb_array_elements_text(v_gen) w where security.pdesc_has_term_v1(t, w)) then
    return jsonb_build_object('rule', 'generic_phrase', 'reason', 'a generic phrase that says nothing specific about this course: ' || left(t, 120));
  end if;
  -- a sentence that does not end as a sentence is a fragment: held, never cut or completed (Platform Admin 2 Nov 2026 23:24)
  if t !~ '[.!?]["'')\]’”]*$' or t ~ '(\.\.\.|…)["'')\]’”]*$' then
    return jsonb_build_object('rule', 'incomplete_sentence', 'reason', 'a sentence is not complete (it would be published as a fragment): ' || left(t, 120));
  end if;
  v_sup := security.pdesc_support_v1(t, p_quote);
  if v_sup < p_min_support then
    return jsonb_build_object('rule', 'unsupported_sentence', 'checks', jsonb_build_object('support', v_sup), 'reason', 'a sentence is not supported by its quote (' || v_sup || '): ' || left(t, 120));
  end if;
  -- cdesc-source-grounded-v1: a run of v_run words of the sentence, in order, in its source passage is the page's text, not an original description (0 = off)
  if v_run > 0 then
    v_sw := array(select w from regexp_split_to_table(lower(t), '[^a-z0-9]+') w where w <> '');
    v_qw := ' ' || array_to_string(array(select w from regexp_split_to_table(lower(coalesce(p_quote, '')), '[^a-z0-9]+') w where w <> ''), ' ') || ' ';
    for i in 1 .. coalesce(array_length(v_sw, 1), 0) - v_run + 1 loop
      if position(' ' || array_to_string(v_sw[i:i + v_run - 1], ' ') || ' ' in v_qw) > 0 then
        return jsonb_build_object('rule', 'copied_sentence', 'checks', jsonb_build_object('copy_run_words', v_run),
          'reason', 'a sentence repeats ' || v_run || ' or more words of the page in order (copied, not an original description): ' || left(t, 120));
      end if;
    end loop;
  end if;
  return null;
end $function$
