CREATE OR REPLACE FUNCTION security.course_description_claim_eval_v1(p_words jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_list jsonb := coalesce(security.toolset_setting('pipeline', 'enrich.course_description_claim_words'), security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb);
        v_cap int := security.pipeline_num_v1('enrich.course_description_report_max', 500)::int; v_ex int := security.pipeline_num_v1('enrich.course_description_examples', 3)::int;
        v_days int := security.pipeline_num_v1('enrich.course_description_held_days', 7)::int; v_out jsonb := '[]'::jsonb; w text; v_rest jsonb; v_one jsonb;
begin
  -- the window of this evaluation is the held-reasons window; the word list is the course list; every other rule runs again on each reading
  for w in select x from jsonb_array_elements_text(coalesce(p_words, v_list)) x loop
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_rest from jsonb_array_elements_text(v_list) x where x <> w;
    with items as (
      select f.id, f.course_id, f.value from pipeline.field_enrich_items f
       where f.field = 'description' and f.state = 'skipped' and f.reason like 'held: unsupported\_claim%' and f.updated_at >= now() - make_interval(days => v_days)
       order by f.updated_at desc limit v_cap),
    hit as (
      select i.id, i.course_id, i.value,
             (select s->>'text' from jsonb_array_elements(coalesce(i.value->'sentences', '[]'::jsonb)) s where security.pdesc_has_term_v1(s->>'text', w) and not security.pdesc_has_term_v1(s->>'quote', w) limit 1) txt,
             (select s->>'quote' from jsonb_array_elements(coalesce(i.value->'sentences', '[]'::jsonb)) s where security.pdesc_has_term_v1(s->>'text', w) and not security.pdesc_has_term_v1(s->>'quote', w) limit 1) qt,
             (select count(distinct x) from jsonb_array_elements_text(v_list) x, jsonb_array_elements(coalesce(i.value->'sentences', '[]'::jsonb)) s
               where security.pdesc_has_term_v1(s->>'text', x) and not security.pdesc_has_term_v1(s->>'quote', x)) n_words
        from items i),
    h2 as (select hit.* from hit where hit.txt is not null),
    r as (select h2.*, security.course_description_check_with_v1(h2.course_id, h2.value, v_rest, null) chk, coalesce(h2.qt ~* '\m(you|your)\M', false) reader from h2)
    select jsonb_build_object('word', w, 'held', count(*), 'only_this_word', count(*) filter (where r.n_words = 1),
             'passes_every_other_rule_without_it', count(*) filter (where (r.chk->>'ok')::boolean),
             'next_rule', coalesce((select jsonb_object_agg(z.rule, z.n) from (select r2.chk->>'rule' rule, count(*) n from r r2 where not (r2.chk->>'ok')::boolean group by 1) z), '{}'::jsonb),
             'quote_addresses_the_reader', count(*) filter (where r.reader),
             -- suggestions for a person to judge, not a ruling: the page says "you" where the sentence says the word (suggested harmless) or it does not (suggested a real claim)
             'suggested_harmless', coalesce((select jsonb_agg(jsonb_build_object('text', e.txt, 'quote', e.qt)) from (select r3.txt, r3.qt from r r3 where r3.reader order by r3.id limit v_ex) e), '[]'::jsonb),
             'suggested_claim', coalesce((select jsonb_agg(jsonb_build_object('text', e.txt, 'quote', e.qt)) from (select r3.txt, r3.qt from r r3 where not r3.reader order by r3.id limit v_ex) e), '[]'::jsonb))
      into v_one from r;
    if coalesce((v_one->>'held')::int, 0) > 0 then v_out := v_out || jsonb_build_array(v_one); end if;
  end loop;
  return jsonb_build_object('window_days', v_days, 'evaluated_up_to', v_cap, 'words', v_out,
    'note', 'Evaluation only. Removing a word is a Platform Admin decision made as a recorded setting change; every other rule still applies after it.');
end $function$
