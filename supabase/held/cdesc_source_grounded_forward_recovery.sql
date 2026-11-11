-- HELD forward recovery for migration 20261112170000_cf247_cdesc_source_grounded_v1.sql (CF-247 F-CDESC). NOT a migration: run by hand only on the Platform Admin's decision.
-- Restores the three edited bodies byte for byte (each md5-guarded; applying it twice changes nothing). The worker keeps writing with cdesc-source-grounded-v1 until coverage-sweep is redeployed at v0.71.0;
-- the two new functions (security.cdesc_prompt_version_v1, security.cdesc_prompt_supersede_v1) and the two settings stay, unused by the restored bodies. Layer 4 items already superseded stay superseded (their record is in
-- pipeline.layer4_supersessions and can be reversed there).
create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this recovery restores from (body md5 %)', p_sig, md5(v_src); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.cdesc_sentence_fault_v1(text,text,boolean,jsonb,jsonb,numeric)', 'c17adb1d759d24cf8b41bcdeac7c6b54', '0aacac45e2a294a51db82777a9d1bc19',
  array[$o0$declare t text := btrim(coalesce(p_text, '')); v_sup numeric;
        v_run int := security.pipeline_num_v1('enrich.course_description_copy_run_words', 10)::int;
        v_gen jsonb := coalesce(security.toolset_setting('pipeline', 'enrich.course_description_generic_phrases'), '[]'::jsonb); v_sw text[]; v_qw text; i int;$o0$,
        $o1$  -- cdesc-source-grounded-v1 (CF-247 F-CDESC, 12 Nov 2026): a stock phrase that says nothing about this course is held, whatever the page says
  if exists (select 1 from jsonb_array_elements_text(v_gen) w where security.pdesc_has_term_v1(t, w)) then
    return jsonb_build_object('rule', 'generic_phrase', 'reason', 'a generic phrase that says nothing specific about this course: ' || left(t, 120));
  end if;
  -- a sentence that does not end as a sentence is a fragment$o1$,
        $o2$  -- cdesc-source-grounded-v1: a run of v_run words of the sentence, in order, in its source passage is the page's text, not an original description (0 = off)
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
  return null;$o2$],
  array[$n0$declare t text := btrim(coalesce(p_text, '')); v_sup numeric;$n0$,
        $n1$  -- a sentence that does not end as a sentence is a fragment$n1$,
        $n2$  return null;$n2$]);

select pg_temp.edit_all('security.enrich_course_text_gaps_v1(text[])', 'ddba9b553a63a9e38c49782a0b0d29c9', '66d9dad4eb0d743b804097b1bf9d38d2',
  array[$o0$                                  and a.answer->'value'->'sentences' = e.value->'sentences')) unproven,
               -- cdesc-source-grounded-v1 (CF-247 F-CDESC, 12 Nov 2026): a description reading held by a check, or superseded in Layer 4, that an earlier prompt made is read once more with the released prompt
               -- (a reading held behind the provider's places passed its checks: it follows a decision through course_description_promote_held_v1 and is not read again here)
               (f = 'description' and e.state = 'skipped' and ((e.reason like 'held%' and e.reason not like 'held\_first\_admission:%') or e.reason like 'superseded:%')
                and coalesce(e.value->>'prompt_version', e.value->'reader'->>'prompt', '') <> security.cdesc_prompt_version_v1()) old_prompt$o0$,
        $o1$case when coalesce(l.unproven, false) then 0 when l.state is null or coalesce(l.old_prompt, false) then 1$o1$,
        $o2$or coalesce(l.unproven, false) or coalesce(l.old_prompt, false) or l.updated_at <$o2$],
  array[$n0$                                  and a.answer->'value'->'sentences' = e.value->'sentences')) unproven$n0$,
        $n1$case when coalesce(l.unproven, false) then 0 when l.state is null then 1$n1$,
        $n2$or coalesce(l.unproven, false) or l.updated_at <$n2$]);

select pg_temp.edit_all('security.course_description_machine_run_v1()', '545a874051466f132221de12160fbd46', '42c73e9c0f376150e7778104dfa9830a',
  array[$o0$declare v_a jsonb; v_b jsonb; v_h jsonb; v_s jsonb; v_p jsonb;$o0$,
        $o1$  -- cdesc-source-grounded-v1 (CF-247 F-CDESC, 12 Nov 2026): waiting descriptions an earlier prompt made that the machine declined for good are superseded and read again
  begin v_p := security.cdesc_prompt_supersede_v1(); exception when others then v_p := jsonb_build_object('error', sqlerrm); end;
  begin v_h := security.cdesc_recheck_held_v1();$o1$,
        $o2$return jsonb_build_object('on', true, 'prompt', v_p, 'held', v_h,$o2$],
  array[$n0$declare v_a jsonb; v_b jsonb; v_h jsonb; v_s jsonb;$n0$,
        $n1$  begin v_h := security.cdesc_recheck_held_v1();$n1$,
        $n2$return jsonb_build_object('on', true, 'held', v_h,$n2$]);

