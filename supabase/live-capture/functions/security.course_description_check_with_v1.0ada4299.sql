CREATE OR REPLACE FUNCTION security.course_description_check_with_v1(p_course uuid, p_result jsonb, p_claim_words jsonb, p_marketing_words jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_s jsonb := coalesce(p_result->'sentences', '[]'::jsonb); v_n int; v_text text; s jsonb; t text; v_sup numeric; v_f jsonb; v_other record; v_pid uuid;
        v_min_sup numeric := security.pipeline_num_v1('pdesc.support_min_share', 0.6); v_dup numeric := security.pipeline_num_v1('pdesc.duplicate_share', 0.8);
        v_checks jsonb; v_words text[]; v_title text; v_prov text;
        v_claim jsonb := coalesce(p_claim_words, security.toolset_setting('pipeline', 'enrich.course_description_claim_words'), security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb);
        v_mkt jsonb := coalesce(p_marketing_words, security.toolset_setting('pipeline', 'enrich.course_description_marketing_words'), security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb);
begin
  select c.provider_id, c.canonical_title, coalesce(p.display_name, p.canonical_name) into v_pid, v_title, v_prov
    from catalogue.courses c left join catalogue.providers p on p.id = c.provider_id where c.id = p_course;
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
    -- the per-sentence tests are security.cdesc_sentence_fault_v1 (the one definition, also used to find the sentences a subset recovery sets aside)
    -- 12 Nov 2026 (QA of #1049): the course's own title and provider are verified facts, not claims: they are left out of the sentence's tests (never added to the quote)
    v_f := security.cdesc_sentence_fault_v1(security.cdesc_known_strip_v1(s->>'text', v_title, v_prov), s->>'quote', coalesce((s->>'on_page')::boolean, false), v_claim, v_mkt, v_min_sup);
    if v_f is not null then
      return jsonb_build_object('ok', false, 'rule', v_f->>'rule', 'checks', v_checks || coalesce(v_f->'checks', '{}'::jsonb), 'reason', v_f->>'reason');
    end if;
  end loop;
  if length(v_text) < security.pipeline_num_v1('enrich.course_description_min_chars', 80) or length(v_text) > security.pipeline_num_v1('enrich.course_description_max_chars', 700) then
    return jsonb_build_object('ok', false, 'rule', 'length', 'checks', v_checks, 'reason', length(v_text) || ' characters, outside the set range (held whole, never cut)');
  end if;
  -- boilerplate: the same words as another course of the provider (held, or waiting in Layer 4)
  -- CF-247 IQ-00053 residual: the new text is split into words once, and each other text inline, by the rule of security.pdesc_words_v1 and
  -- security.pdesc_similarity_v1 (distinct lower-case words of 3 or more letters or digits; shared words over all words of both)
  v_words := security.pdesc_words_v1(v_text);
  select z.course_id, z.sim into v_other from (
    select x.course_id, case when cardinality(v_words) = 0 or cardinality(x.wb) = 0 then 0
                             else round(k.n::numeric / (cardinality(v_words) + cardinality(x.wb) - k.n), 4) end sim
      from (select x0.course_id, array(select distinct w from regexp_split_to_table(lower(coalesce(x0.d, '')), '[^a-z0-9]+') w where length(w) >= 3) wb from (
      select c.id course_id, c.description d, c.updated_at at from catalogue.courses c
       where c.provider_id = v_pid and c.id <> p_course and nullif(btrim(c.description), '') is not null
      union all
      select r.entity_id, r.proposed_value->>'description', r.created_at from pipeline.layer4_review_items r join catalogue.courses c on c.id = r.entity_id
       where r.entity_type = 'course' and r.field_code = 'course_description_first_read' and r.status = 'pending' and c.provider_id = v_pid and r.entity_id <> p_course
      order by 3 desc limit security.pipeline_num_v1('enrich.course_description_duplicate_window', 500)::int) x0) x
      cross join lateral (select count(*) n from unnest(v_words) w where w = any (x.wb)) k) z
   where z.sim >= v_dup order by z.sim desc limit 1;
  if v_other.course_id is not null then
    return jsonb_build_object('ok', false, 'rule', 'duplicate_other_course', 'checks', v_checks || jsonb_build_object('duplicate_of', v_other.course_id, 'similarity', v_other.sim),
      'reason', 'the same words as another course''s description (' || v_other.sim || '): text that is not about this course');
  end if;
  return jsonb_build_object('ok', true, 'rule', 'ok', 'text', v_text, 'checks', v_checks, 'reason', null);
end $function$
