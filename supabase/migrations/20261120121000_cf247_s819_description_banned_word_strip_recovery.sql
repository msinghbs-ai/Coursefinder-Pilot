-- CF-247 S1-RM-Design (Platform Admin 20 Nov 2026 10:21, s819): a valid university description is no longer parked in Layer 4 for days over one
-- promotional word (for example "innovative") that the platform's own word list already names.
--   1 security.description_strip_words_v1(entity, sentences) NEW (read only, not callable by the browser roles): removes the promotional words of the
--     list the readers use (pdesc.superlatives for universities, enrich.course_description_marketing_words for courses) from each sentence's text,
--     together with an intensifier straight before it ("most", "very", "highly", "truly", "particularly"), then tidies the spaces and punctuation, the
--     article ("an innovative university" becomes "a university") and the capital letter. Each sentence's quote is left exactly as it is on the page.
--     It never adds a word. It returns the sentences, every word removed (sentence and word), and whether anything changed.
--   2 security.provider_description_machine_admit_v1(item): when the reading is declined only for a refused word (validation_refused_word or
--     machine_text_refused_word) on an official page reading (stored, direct, firecrawl), the words are removed and the SAME validation (host, About page,
--     sentence and character ranges, every quote on the page, age, duplicate guard) and the SAME machine gate (lock, rejection memory, withdrawal,
--     identity, name, full text check) run again on the result. If everything passes it is admitted by the existing machine admission (rule
--     pdesc-machine-v1, the machine actor); the ledger reason starts "words_removed:" and keeps the original text, sentences and the words removed.
--     If anything fails, the reading stays declined exactly as before and the existing sentence-subset recovery still runs; the ledger says what was tried.
--     The hourly settle that already re-checks waiting descriptions applies this to the ones waiting now. A word that is not promotional (for example
--     "campus", "fee", "ranked") is never removed: those stay with a person.
-- One in-place, md5-guarded edit of the admission function (four fragments). Nothing else changes: word lists, settings, thresholds, the validation, the gate.
-- G1: no job. G2: the word lists are the existing settings; the intensifiers are part of the rule's grammar (fixed). G3: no consumer API object;
-- security.consumer_api_check_v1() is read before and after (75 functions, 48 relations).
-- Replaces: nothing (adds a recovery step before the sentence-subset recovery)
-- Retires: nothing
-- Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;

create or replace function security.description_strip_text_v1(p_text text, p_words text[])
returns jsonb language plpgsql immutable set search_path to '' as $f$
declare t text := coalesce(p_text, ''); w text; e text; v_removed text[] := '{}'; v_before text;
begin
  -- longest first, so "world-class" goes before "class" and "world class" before "world"
  foreach w in array (select coalesce(array_agg(x order by length(x) desc, x), '{}') from unnest(coalesce(p_words, '{}')) x where btrim(x) <> '') loop
    e := regexp_replace(btrim(w), '([^[:alnum:][:space:]])', '\\\1', 'g');
    v_before := t;
    -- fixed: the intensifiers that only qualify the removed word; a following "and"/"or" joining two removed words is handled below
    t := regexp_replace(t, '(^|[^[:alnum:]])((most|very|highly|truly|particularly)\s+)?' || e || '(?=$|[^[:alnum:]])', '\1', 'gi');
    if t is distinct from v_before then v_removed := v_removed || lower(btrim(w)); end if;
  end loop;
  if cardinality(v_removed) = 0 then return jsonb_build_object('text', p_text, 'removed', '[]'::jsonb, 'changed', false); end if;
  -- tidy: a conjunction or comma left with nothing to join, doubled punctuation, spaces
  t := regexp_replace(t, '\m(and|or)\s+(?=(and|or)\M)', '', 'gi');
  t := regexp_replace(t, '(\m(a|an|the)\s+)(and|or)\s+', '\1', 'gi');
  t := regexp_replace(t, '\m(a|an|the)\s*,\s*', '\1 ', 'gi');
  t := regexp_replace(t, '\s*,\s*(and|or)\s*(?=[.!?;:]|$)', '', 'gi');
  t := regexp_replace(t, '\m(and|or)\s*(?=[,.!?;:]|$)', '', 'gi');
  t := regexp_replace(t, ',\s*(?=[,.!?;:])', '', 'g');
  t := regexp_replace(t, '\s+([,.!?;:])', '\1', 'g');
  t := regexp_replace(t, '\s{2,}', ' ', 'g');
  t := regexp_replace(t, '^[\s,;:]+', '');
  t := btrim(t);
  -- the article agrees with the word that now follows it
  t := regexp_replace(t, '\m(a)\s+(?=(hour|honour|honest|heir)|([aeio])|(u(?!ni|se|su|ti|tu|ra|re)))', '\1n ', 'gi');
  t := regexp_replace(t, '\m(an)\s+(?=(uni|use|usu|uti|utu|eu|one\M)|[b-df-hj-np-tv-zB-DF-HJ-NP-TV-Z])(?!(hour|honour|honest|heir))', 'a ', 'g');
  t := regexp_replace(t, '\m(An)\s+(?=([Uu]ni|[Uu]se|[Uu]su|[Uu]ti|[Uu]tu|[Ee]u|[Oo]ne\M)|[b-df-hj-np-tv-zB-DF-HJ-NP-TV-Z])(?!([Hh]our|[Hh]onour|[Hh]onest|[Hh]eir))', 'A ', 'g');
  if t <> '' then t := upper(left(t, 1)) || substr(t, 2); end if;
  return jsonb_build_object('text', t, 'removed', to_jsonb(v_removed), 'changed', true);
end $f$;
revoke all on function security.description_strip_text_v1(text, text[]) from public, anon, authenticated;
comment on function security.description_strip_text_v1(text, text[]) is 'CF-247 s819: removes the named promotional words (and an intensifier straight before one) from a text and tidies spaces, punctuation, the article and the capital letter. Never adds a word.';

create or replace function security.description_strip_words_v1(p_entity text, p_sentences jsonb)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
declare v_words text[]; s jsonb; r jsonb; n int := 0; v_out jsonb := '[]'::jsonb; v_removed jsonb := '[]'::jsonb; v_changed boolean := false; v_short boolean := false;
begin
  v_words := array(select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', case when p_entity = 'course' then 'enrich.course_description_marketing_words' else 'pdesc.superlatives' end), '[]'::jsonb)));
  for s in select * from jsonb_array_elements(coalesce(p_sentences, '[]'::jsonb)) loop
    n := n + 1;
    r := security.description_strip_text_v1(s->>'text', v_words);
    if (r->>'changed')::boolean then
      v_changed := true;
      v_removed := v_removed || (select coalesce(jsonb_agg(jsonb_build_object('sentence', n, 'word', x)), '[]'::jsonb) from jsonb_array_elements_text(r->'removed') x);
      if coalesce(array_length(regexp_split_to_array(nullif(btrim(r->>'text'), ''), '\s+'), 1), 0) < 4 then v_short := true; end if;  -- fixed: a sentence of fewer than four words is not a sentence left
      v_out := v_out || jsonb_build_array(s || jsonb_build_object('text', r->>'text', 'text_before_strip', s->>'text'));
    else
      v_out := v_out || jsonb_build_array(s);
    end if;
  end loop;
  return jsonb_build_object('sentences', v_out, 'removed', v_removed, 'changed', v_changed and not v_short, 'too_short', v_short);
end $f$;
revoke all on function security.description_strip_words_v1(text, jsonb) from public, anon, authenticated;
comment on function security.description_strip_words_v1(text, jsonb) is 'CF-247 s819: the promotional words of the readers'' own list removed from each sentence''s text (quotes unchanged), for the admission''s word-strip recovery.';

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.cf_edit_def('security.provider_description_machine_admit_v1(uuid)'::regprocedure, 'e6a6f70bf5de372987df17c380cb5106',
  array[$o1$v_text0 text; -- sentence-subset recovery$o1$,
        $o2$  if v_decline in ('machine_text_refused_word', 'machine_text_figure', 'machine_text_entity_encoded') and v_tier in ('stored', 'direct', 'firecrawl') then -- fixed: the three refusals of the text rule that leaving a sentence out can remove$o2$,
        $o3$    v_reason := v_reason || format(' Sentence subset of the reading: %s of %s sentences kept, %s left out because the automatic text rule refused them; nothing was reworded or added.', v_subinfo->>'kept_sentences', v_subinfo->>'given_sentences', jsonb_array_length(v_subinfo->'dropped'));$o3$,
        $o4$case when v_subinfo is not null then 'subset_of_reading: ' else '' end$o4$],
  array[$n1$v_text0 text; v_strip jsonb; -- sentence-subset recovery; s819 word strip$n1$,
        $n2$  -- s819 (Platform Admin 20 Nov 2026 10:21): a reading declined only for a promotional word of the readers' list has those words removed from its sentences
  -- (quotes unchanged, nothing added) and the SAME validation and machine gate run again; if both pass, it is admitted below like any other reading.
  if v_decline in ('validation_refused_word', 'machine_text_refused_word') and v_tier in ('stored', 'direct', 'firecrawl') then -- fixed: the two refusals a word strip can remove
    v_strip := security.description_strip_words_v1('provider', v_sent);
    v_try := jsonb_build_object('method', 'word_strip', 'refusal', v_decline, 'reason', v_reason, 'words_removed', coalesce(v_strip->'removed', '[]'::jsonb), 'too_short', v_strip->'too_short', 'at', now());
    if not coalesce((v_strip->>'changed')::boolean, false) then
      v_try := v_try || jsonb_build_object('result', case when coalesce((v_strip->>'too_short')::boolean, false) then 'sentence_too_short_after_strip' else 'no_promotional_word_to_remove' end);
    else
      v_check := security.provider_description_validate_v1(i.entity_id, v_read.source_url, v_read.source_captured_at, jsonb_build_object('about_page', true, 'sentences', v_strip->'sentences'));
      if coalesce(v_check->>'outcome', '') not in ('propose', 'verified') or nullif(v_check->>'text', '') is null then
        v_try := v_try || jsonb_build_object('result', 'stripped_validation_' || coalesce(v_check->>'rule', 'changed'), 'stripped_reason', v_check->>'reason');
      else
        v_gate2 := security.provider_description_machine_gate_v1(i.entity_id, v_check->>'text', jsonb_build_object('tier', v_tier, 'codes', v_codes, 'sentences', v_strip->'sentences'));
        if not coalesce((v_gate2->>'ok')::boolean, false) then
          v_try := v_try || jsonb_build_object('result', 'stripped_' || coalesce(v_gate2->>'rule', 'not_ok'), 'stripped_reason', v_gate2->>'reason');
        else
          v_text0 := v_text;
          v_subinfo := jsonb_build_object('method', 'word_strip', 'refusal', v_decline, 'refusal_reason', v_reason, 'words_removed', v_strip->'removed', 'dropped', '[]'::jsonb,
                         'kept_sentences', jsonb_array_length(v_strip->'sentences'), 'given_sentences', jsonb_array_length(v_sent),
                         'original_text_chars', length(v_text0), 'original_text_md5', md5(v_text0), 'original_text', v_text0, 'original_sentences', v_sent, 'original_read_id', v_read.id,
                         'original_evidence_id', i.evidence_id, 'source_url', v_read.source_url, 'source_hash', v_read.content_hash, 'review_item_id', i.id);
          v_sent := v_strip->'sentences'; v_text := v_check->>'text'; v_gate := v_gate2; v_decline := null; v_reason := null;
          v_facts := coalesce((select jsonb_agg(jsonb_build_object('sentence', s->>'text', 'quote', s->>'quote', 'source_url', v_read.source_url, 'source_hash', v_read.content_hash, 'evidence_id', v_read.evidence_id,
                    'captured_at', v_read.source_captured_at, 'model', v_read.model, 'prompt_version', v_read.prompt_version, 'worker', v_read.worker)) from jsonb_array_elements(v_sent) s), '[]'::jsonb);
          v_try := v_try || jsonb_build_object('result', 'adopted');
        end if;
      end if;
    end if;
  end if;
  if v_decline in ('machine_text_refused_word', 'machine_text_figure', 'machine_text_entity_encoded') and v_tier in ('stored', 'direct', 'firecrawl') then -- fixed: the three refusals of the text rule that leaving a sentence out can remove$n2$,
        $n3$    v_reason := v_reason || case when v_subinfo ? 'words_removed' then format(' Promotional words removed from the reading: %s; nothing else was reworded or added, every quote is unchanged, and the validation and machine gate ran again on the result.', (select string_agg(x->>'word', ', ') from jsonb_array_elements(v_subinfo->'words_removed') x))
      else format(' Sentence subset of the reading: %s of %s sentences kept, %s left out because the automatic text rule refused them; nothing was reworded or added.', v_subinfo->>'kept_sentences', v_subinfo->>'given_sentences', jsonb_array_length(v_subinfo->'dropped')) end;$n3$,
        $n4$case when v_subinfo ? 'words_removed' then 'words_removed: ' when v_subinfo is not null then 'subset_of_reading: ' else '' end$n4$]);

-- post-checks: the strip on known phrases, then the waiting descriptions held for a word, each tried in a sub-block that is always rolled back
do $$
declare r jsonb; v_o text := ''; it record; v_n int := 0; v_ok int := 0; v_res jsonb; v_t0 timestamptz := clock_timestamp(); v_tried int := 0; v_why text := ''; v_words text[] := array['innovative', 'leading', 'world-class', 'vibrant', 'best'];
begin
  r := security.description_strip_text_v1('UTS is an innovative university of technology in Sydney.', v_words);
  if r->>'text' <> 'UTS is a university of technology in Sydney.' then raise exception 'post-check: strip 1 gave %', r->>'text'; end if;
  r := security.description_strip_text_v1('It is one of the most innovative and vibrant universities in Australia.', v_words);
  if r->>'text' <> 'It is one of the universities in Australia.' then raise exception 'post-check: strip 2 gave %', r->>'text'; end if;
  r := security.description_strip_text_v1('A world-class, leading research university with an open campus.', v_words);
  if r->>'text' <> 'A research university with an open campus.' then raise exception 'post-check: strip 3 gave %', r->>'text'; end if;
  r := security.description_strip_text_v1('An innovative university. An innovative campus.', v_words);
  if r->>'text' <> 'A university. A campus.' then raise exception 'post-check: strip 5 gave %', r->>'text'; end if;
  r := security.description_strip_text_v1('The university offers courses in Sydney.', v_words);
  if (r->>'changed')::boolean then raise exception 'post-check: strip 4 changed clean text'; end if;
  v_o := 'strip examples pass';
  for it in select i.id from pipeline.layer4_review_items i join pipeline.provider_description_machine_admissions m on m.review_item_id = i.id and m.outcome = 'declined'
             where i.status = 'pending' and i.field_code = 'provider_description' and m.reason ~ '(validation_refused_word|machine_text_refused_word|word, figure or markup)' loop
    v_n := v_n + 1;
    continue when v_tried >= 3 or clock_timestamp() - v_t0 > interval '30 seconds';  -- fixed: the post-check tries a sample; the hourly settle does the rest
    v_tried := v_tried + 1;
    begin
      v_res := security.provider_description_machine_admit_v1(it.id);
      if coalesce((v_res->>'ok')::boolean, false) then v_ok := v_ok + 1; else v_why := v_why || coalesce(v_res->>'rule', '?') || ';'; end if;
      raise exception 'ROLLBACK-POSTCHECK';
    exception when others then if sqlerrm <> 'ROLLBACK-POSTCHECK' then v_o := v_o || ' | ' || left(sqlerrm, 80); end if;
    end;
  end loop;
  v_o := v_o || format(' | waiting for a word: %s; tried %s, admitted %s (not: %s); machine admission on: %s', v_n, v_tried, v_ok, v_why, security.pipeline_num_v1('pdesc.machine_admit_on', 0));
  perform set_config('cf247.s819_postcheck', v_o, true);
  raise notice 's819 post-checks: %', v_o;
end $$;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API moved during this change: %', v;
  end if;
end $g$;
