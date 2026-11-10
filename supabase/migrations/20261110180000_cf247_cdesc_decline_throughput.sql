-- CF-247 F-CDESC (Platform Admin directive 10 Nov 2026 14:02): scale the course-description machine admission by removing the avoidable causes of declines and holds. Course-description machine route only (the provider description lane, pdesc.* and provider_description_*, is not touched).
--
-- Evidence (project fxcwkweaxjtknorudmwp, SELECT only, 10 Nov 2026 ~14:30 AEDT). 1,524 first readings reached Layer 4: 366 admitted by the machine, 1,158 waiting; the ledger holds one decline for every one of the 1,158 (1,149 non-transient). By ROOT CAUSE:
--   policy_refused_word 413 (pathway 74+9, leading 63, campus 52+3, employment 45, employers 32, innovative 15, award 13, accredited 13, ...) and policy_figure 297 (credit points, paper codes, 100-level, Year 1 ... as well as durations and counts);
--   identity_margin_thin 177 (48+10+1 with the page bound by the course's own CRICOS code on the page; 28+20+15+11+4+2+2 by an AI match; 18+18 by a title match under 0.1 over the runner-up);
--   binding_ambiguous 97; reader_unrecorded 75 (the held reading never recorded its model and prompt version; 55 of the 75 have the stored AI answer that did); duplicate_exact_waiting 66 (24 wordings, each one declined because its twin WAITS, so neither can ever be admitted)
--   and duplicate_near_other_provider 22 (the same mutual wait); evidence_moved 9 (transient). Before Layer 4 a further 794 readings are held at the reader because a sentence holds the word "students" that its quote does not (the quote says "you"), 807 by length, 578 by sentence count,
--   302 quote_not_on_page, 180 unsupported_sentence; and 583 readings that were already paid for are held behind the provider cap (pending_max = 10) in 29 universities whose 10 places are filled by descriptions the machine has already declined for good (1,149 of the 1,158 waiting).
--   The eligible denominator is 22,514 active courses without a description that hold a stored, read, identity-proved page; 17,463 of them have never been read. The daily reading cap enrich.course_text_items_per_day = 500 is used in full every day (500 standing readings a day since 4 Nov); AI spend on the lane is about US$1.4 a day against budgets.ai_daily_ceiling_usd = 14.
--
-- What this changes (course-description machine route only; every protection stays: identity proof, the page margin, stored-evidence recency and hash lineage, per-sentence quote on the page, manual locks, holds, rejection memory, human/machine actor separation, the duplicate tests, the AI budgets;
-- enrich.course_description_review_first stays 100000: it is not changed, and the post-check only reads it to prove it is still on):
--   1. Reader provenance. security.cdesc_reading_provenance_v1 reads the model, prompt version and worker from the Layer 4 item, else from the reading (recorded from this change on), else from the stored AI answer (pipeline.enrich_ai_answers) only when that answer holds EXACTLY the sentences
--      of the reading. security.course_description_machine_check_v1 uses it, so a reading whose reader is provable is no longer declined as reader_unrecorded; one with no provable reader still is. The reader is also recorded on every held reading and on the Layer 4 item a held reading is promoted to.
--   2. The provider places. security.cdesc_provider_slots_v1 counts the provider's waiting descriptions the machine has NOT already declined for good under the current policy (a person decides those; they no longer occupy a place a new reading needs). Used by security.enrich_course_text_record_v1 (the cap),
--      security.course_description_promote_held_v1 and the standing queue. Held readings then take their places (job course-description-machine promotes them, see 5). No place is created for a description the machine could still admit.
--   3. The learner word. A sentence that says "students" where its on-page quote says "you" (or gives the instruction) is not a population claim. security.cdesc_learner_word_ok_v1 admits a word from the new list enrich.course_description_learner_words (ships "students") only when the quote is on the page, the word is not in the quote, the quote speaks to the reader (it holds you / your, or a clause that opens with the same verb the sentence
--      gives the word: "Learn about ..." for "Students learn about ..."; a quote about the profession proves nothing and stays held), and the sentence states no population (a figure beside it, "our/international/former/top/current students", "students from over ...", "students who/are/have ...", "of students", "student satisfaction" ...); security.course_description_check_with_v1 uses it. Every other claim word still needs the same word in the quote.
--   4. The machine wording policy for a course. security.cdesc_machine_text_check_v1 runs the SAME shared policy (security.pdesc_machine_text_check_ctx_v1, every list and the figures rule, unchanged) on the sentences after four structural things are set aside: "leading" as a verb or direction (leading to / into / towards, leading teams / people / others / a team; "leading the way", "leading the nation" and "leading providers" are NOT set aside and still refuse);
--      programme structure (N points, N-point, N credit points, 100-level, Year 1, Level 7; and a paper code such as CHHE 701 only in a sentence that names a paper, course, unit, subject or module and holds no money word, no $ and no currency code beside a number, so AUD 250 / USD 120 / NZD 300 still refuse); a word from the new list enrich.course_description_supported_words (ships pathway, pathways) in a sentence whose on-page quote holds the same word; and the learner word of 3. Every figure written in digits (durations, hours, weeks, counts, prices) still refuses; a figure written as a word (for example "three years") is not caught by the shared figures rule, which is unchanged
--      here, and so is not caught now either. Campuses, employment, accreditation and every superlative still refuse.
--   5. The page margin. A page bound by the course's own CRICOS code on the page (basis cricos_code_on_page, Decision 265) is a code proof, not a score contest; the margin test no longer declines it when no other course is bound to the same address (the same address means the same web address with the query, the fragment and a trailing slash set aside and the case ignored, or the same stored evidence). An AI match still declines, and so does a title match under 0.1.
--   6. The mutual wait. Two courses with the same (or nearly the same) wording both waiting declined each other for good. An item now waits for an OLDER twin (earlier created, same wording) that is not already parked for another reason; the oldest goes on to the remaining tests and, once admitted, every later twin is declined as
--      duplicate_exact_described / duplicate_near_other_provider. No duplicate is ever admitted. Wording that waits at three or more different providers (shared training-package wording) keeps the old rule: every waiting twin blocks, nothing is tie-broken.
--   7. Replay without a new AI call. security.cdesc_recheck_held_v1 (called by the job course-description-machine before it settles) (a) runs the live text check again on each reader-held reading once per policy stamp and, where it now passes and its reader is provable, hands it to the one existing record
--      function exactly as the reader would have (identity, lock, page unchanged, cap, then Layer 4 and the machine rule), and (b) promotes held first-admission readings into free provider places. No AI call, no spend.
--   8. Fair queue. security.enrich_course_text_gaps_v1 takes the same eligible courses in the same priority but in rounds across providers (the first course of every provider, then the second ...) and leaves out a university whose places are all taken by descriptions that wait for a person, so one large provider cannot take the whole day.
--      A reading held behind the provider's places whose reader was never recorded and is not proved by a stored answer (about 357 of the 583) is read once more, first, so the reader is recorded; it uses the day's reads (enrich.course_text_items_per_day) and the lane's existing AI spend, about US$0.0015 a read.
--   9. Data Delivery: the existing course-description stages gain one additive key "flow" (security.data_delivery_cdesc_flow_v1, read only): the eligible denominator and its stages, admissions and retained net gain, every decline and hold by cause, today's reads against the cap, last admission, the job schedule and the active blocker.
-- The policy stamp (security.course_description_machine_policy_stamp_v1) reads every enrich.course_description_* setting, so the two new lists change it and every declined item is looked at again once under this change; a decline is never carried over.
--
-- Settings: two new lists (G2), enrich.course_description_learner_words and enrich.course_description_supported_words, control class human; no setting value that exists is changed. enrich.course_text_items_per_day (500) is the binding limit on reads and is NOT changed here: the Platform Admin decides (see the hand-back).
-- Live definitions this change edits (pg_proc.prosrc md5, read 10 Nov 2026), before -> after (the migration stops, and applies nothing, if a live body is neither):
--   security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)  3bb5d62b5e86cd7c76707171e02a3ae5 -> 6e65745a7863f0dae97a743821475eb0
--   security.course_description_machine_check_v1(uuid)                 3e0fe24d762e7fc4348865ea09499690 -> 4c321730269064b42ff9ac10a114336b
--   security.enrich_course_text_record_v1(bigint,jsonb)                c52c1969a80f2d3db1d81a4e46a49cd9 -> 82e93b8b73d1f13ac3fd62dbb59264f9
--   security.course_description_promote_held_v1(uuid)                  1c990fb9c93b1841195160a0e9a712ae -> 2f46bf63e50726d67bdd9d7cf74e915a
--   security.enrich_course_text_gaps_v1(text[])                        5352bc7ea7bbf3ef00bd616f2897f2f4 -> 66d9dad4eb0d743b804097b1bf9d38d2
--   security.course_description_machine_run_v1()                       452e3ae1ed2ab196865e2905ad2801e1 -> faa6dab1bfeef3464ba86fac11b34766
--   security.data_delivery_cdesc_stages_v1()                           d2a913a4d294f71fadf949bff6786f94 -> bf7c8c712273ae99b885e748ff58b998
-- Forward recovery (the original bodies, byte for byte): supabase/held/cdesc_decline_throughput_forward_recovery.sql.
-- Consumer API (G3): not touched. No public.website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_*, svc_website_settings_v1, api.* object, table column or edge function is read for change or changed. catalogue.courses.description is written only by the existing machine admission.
-- No number is added to the code (G2): the places come from enrich.course_description_pending_max, the reads from enrich.course_text_items_per_day, the margin 0.1 stays the existing line marked fixed, the word lists are settings. A time box below is marked -- fixed:.
-- Replaces: the seven function bodies above are edited in place (md5-guarded); the mutual wait between twin waiting descriptions, the held provider place count and the unrecorded reader of a provable reading are replaced by the rules above
-- Retires: nothing
-- Nothing is dropped or deleted by this migration. No description, Layer 4 item, reading or ledger row is changed by applying it (the job does that afterwards, through the existing record and admission functions).

do $g$
declare r record;
begin
  for r in select * from (values ('security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)'), ('security.course_description_machine_check_v1(uuid)'), ('security.enrich_course_text_record_v1(bigint,jsonb)'), ('security.course_description_promote_held_v1(uuid)'),
                                 ('security.enrich_course_text_gaps_v1(text[])'), ('security.course_description_machine_run_v1()'), ('security.data_delivery_cdesc_stages_v1()'), ('security.pdesc_machine_text_check_ctx_v1(uuid,text,text[],jsonb)'),
                                 ('security.pdesc_has_term_v1(text,text)'), ('security.toolset_setting(text,text)'), ('security.pipeline_num_v1(text,numeric)'), ('security.course_description_machine_policy_stamp_v1()'),
                                 ('security.course_description_machine_settle_v1()'), ('security.course_description_machine_consumer_recheck_v1()'), ('security.course_description_trusted_v1(uuid)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing (apply 20261110060100 and 20261110100100 first)', r.sig; end if;
  end loop;
  if to_regclass('pipeline.course_description_machine_admissions') is null or to_regclass('pipeline.enrich_ai_answers') is null or to_regclass('pipeline.field_enrich_items') is null then raise exception 'a table this change relies on is missing'; end if;
end $g$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- two lists (G2; the words are settings, changed in Settings with a reason)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'enrich.course_description_learner_words', 'Course description: words that may stand for the reader',
  'A claim word (Course description: claim words) that a sentence may use in place of "you" when its quote is on the course page and does not hold the word itself, because the page speaks to the reader ("you will study ...") and the sentence says "students study ...". It is allowed only when the sentence states no population: no figure beside the word, no "our", "international", "former" or "all" students, no "students from over ...", no "of students", no "student satisfaction". A word that is not listed here still needs the same word in its quote. Removing a word restores the earlier rule.',
  'list', '["students"]'::jsonb, null, null, 'words', 1123, 'Course description and deadline',
  'security.cdesc_learner_word_ok_v1; security.course_description_check_with_v1; security.cdesc_machine_text_check_v1',
  'CF-247 F-CDESC (Platform Admin directive 10 Nov 2026): 794 readings were held because "students" stands where the quote says "you"'),
 ('pipeline', 'enrich.course_description_supported_words', 'Course description: words kept when the quote holds them',
  'Words the machine wording policy refuses for provider descriptions (Machine refused words) that a COURSE description may keep when the sentence that uses one has a quote on the course page that holds the same word (a course''s own pathway statement, for example "the degree may be a pathway to a PhD"). Every other list and the figures rule still apply to the rest of the sentence. Remove a word to refuse it again.',
  'list', '["pathway", "pathways"]'::jsonb, null, null, 'words', 1124, 'Course description and deadline',
  'security.cdesc_scrub_sentence_v1; security.cdesc_machine_text_check_v1',
  'CF-247 F-CDESC (Platform Admin directive 10 Nov 2026): 83 course descriptions declined for a pathway statement the official page itself makes')
on conflict (toolset_key, key) do nothing;
do $cc$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'pipeline' and table_name = 'platform_toolset_settings' and column_name = 'control_class') then
    execute $q$update pipeline.platform_toolset_settings set control_class = 'human' where toolset_key = 'pipeline' and key in ('enrich.course_description_learner_words', 'enrich.course_description_supported_words') and control_class is null$q$;
  end if;
end $cc$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- new functions (read only unless stated)
create or replace function security.cdesc_reading_provenance_v1(p_item bigint, p_value jsonb, p_l3 jsonb default null) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare v_m text; v_p text; v_w text; a jsonb;
begin
  -- 1. recorded on the Layer 4 item
  v_m := nullif(btrim(p_l3->>'model'), ''); v_p := nullif(btrim(p_l3->>'prompt'), ''); v_w := nullif(btrim(p_l3->>'worker'), '');
  if v_m is not null and v_p is not null then return jsonb_build_object('model', v_m, 'prompt', v_p, 'worker', v_w, 'from', 'layer4_item'); end if;
  -- 2. recorded on the reading itself (held readings, from this change on)
  v_m := nullif(btrim(p_value->'reader'->>'model'), ''); v_p := nullif(btrim(p_value->'reader'->>'prompt'), ''); v_w := nullif(btrim(p_value->'reader'->>'worker'), '');
  if v_m is not null and v_p is not null then return jsonb_build_object('model', v_m, 'prompt', v_p, 'worker', v_w, 'from', 'reading'); end if;
  -- 3. the AI answer stored for this reading, only when it holds exactly the sentences the reading holds (the same reading, not another attempt)
  select x.answer into a from pipeline.enrich_ai_answers x
   where x.item_id = p_item and nullif(btrim(x.answer->>'model'), '') is not null and nullif(btrim(x.answer->>'prompt_version'), '') is not null
     and x.answer->'value'->'sentences' is not null and x.answer->'value'->'sentences' = p_value->'sentences'
   order by x.id desc limit 1;
  if a is not null then return jsonb_build_object('model', a->>'model', 'prompt', a->>'prompt_version', 'worker', nullif(btrim(a->>'worker'), ''), 'from', 'ai_answer'); end if;
  return jsonb_build_object('from', 'none');
end $f$;
comment on function security.cdesc_reading_provenance_v1(bigint, jsonb, jsonb) is 'CF-247 F-CDESC: the model, prompt version and worker that made a course description reading: from the Layer 4 item, else the reading, else the stored AI answer that holds exactly the reading''s sentences; otherwise none (the machine rule then declines the item as reader_unrecorded). Read only.';
revoke all on function security.cdesc_reading_provenance_v1(bigint, jsonb, jsonb) from public, anon, authenticated;

create or replace function security.cdesc_learner_word_ok_v1(p_word text, p_text text, p_quote text) returns boolean
language plpgsql stable security definer set search_path to '' as $f$
declare w text := lower(btrim(coalesce(p_word, ''))); v_t text := lower(coalesce(p_text, '')); v_q text := lower(coalesce(p_quote, '')); v_verb text;
begin
  if w = '' or w !~ '^[a-z]+$' then return false; end if; -- fixed: a plain word only, so it can sit inside the pattern below
  if not exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_learner_words'), '[]'::jsonb)) x where lower(btrim(x)) = w) then return false; end if;
  if not security.pdesc_has_term_v1(p_text, w) or security.pdesc_has_term_v1(p_quote, w) then return false; end if;
  -- the quote must speak to the reader: a second-person pronoun, or a clause that opens with the verb the sentence gives the word ("Learn about ..." for "Students learn about ...")
  v_verb := substring(v_t from ('\m' || w || '\s+(?:(?:will|can|may|could|should|also|then)\s+)*([a-z]{3,})\M'));
  if v_verb in ('for', 'the', 'and', 'who', 'are', 'from', 'with', 'into', 'that', 'their', 'have', 'has', 'was', 'were', 'not') then v_verb := null; end if; -- fixed: function words are not a verb
  if v_q !~ '\myou(r|rs|rself)?\M' and (v_verb is null or v_q !~ ('(^|[.:;!?]\s*)' || v_verb || '\M')) then return false; end if;
  -- a population statement is not a stand-in for "you"
  return v_t !~ ('([0-9][0-9,.]*\s+([a-z-]+\s+)?' || w || '|' || w || '\s+(from\s+(over|more|across|around)|come|choose|rate|say|report|achieve|graduate|who|are|have|often|typically|usually|consistently|regularly)|(international|former|past|successful|our|alumni|graduate|all|many|most|other|some|top|best|brightest|talented|gifted|enrolled|current)\s+' || w
                 || '|of\s+' || w || '|' || w || '''?s?\s+(satisfaction|outcomes|success))');
end $f$;
comment on function security.cdesc_learner_word_ok_v1(text, text, text) is 'CF-247 F-CDESC: true when the claim word is in enrich.course_description_learner_words, the sentence holds it, its quote does not (the page says "you"), and the sentence states no population (a figure beside it, our/international/former/all/top/current students, students from over ..., students who/are/have ..., of students, student satisfaction), and the quote speaks to the reader (you / your, or a clause that opens with the verb the sentence gives the word). Read only.';
revoke all on function security.cdesc_learner_word_ok_v1(text, text, text) from public, anon, authenticated;

create or replace function security.cdesc_scrub_sentence_v1(p_text text, p_quote text) returns text
language plpgsql stable security definer set search_path to '' as $f$
declare t text := coalesce(p_text, ''); w text;
begin
  -- "leading" as a verb or direction is not a ranking
  t := regexp_replace(t, '\mleading\s+(to|into|towards?|teams?|people|others|(a|the)\s+teams?|and\s+(managing|supervising|motivating))\M', ' ', 'gi');
  t := regexp_replace(t, '\mteam[- ]leading\M', ' ', 'gi');
  -- programme structure, not a claim: points, paper codes, levels, years of study
  t := regexp_replace(t, '\m[0-9]+(\s*-\s*|\s+)(credit\s+)?points?\M', ' ', 'gi');
  -- a paper code (CHHE 701) only in a sentence that names a paper, course, unit, subject or module and holds no money: never a currency code beside an amount (AUD 250)
  if t ~* '\m(papers?|courses?|units?|subjects?|modules?)\M'
     and t !~* '(\$|\m(fees?|costs?|costing|prices?|priced|tuition|dollars?|payable|charges?|scholarships?)\M|\m(aud|usd|nzd|eur|gbp|cad|sgd|cny|jpy|inr|hkd|chf)\s?[0-9])' then
    t := regexp_replace(t, '\m[A-Z]{3,5}\s?[0-9]{3}\M', ' ', 'g');
  end if;
  t := regexp_replace(t, '\m[0-9]{3}-level\M', ' ', 'gi');
  t := regexp_replace(t, '\m(year|level)\s+[0-9]\M', ' ', 'gi');
  -- a word the course may keep when the sentence's own on-page quote holds it
  for w in select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_supported_words'), '[]'::jsonb)) loop
    if w ~ '^[A-Za-z]+$' and security.pdesc_has_term_v1(p_quote, w) then t := regexp_replace(t, '\m' || w || '\M', ' ', 'gi'); end if;
  end loop;
  -- the learner word
  for w in select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_learner_words'), '[]'::jsonb)) loop
    if security.cdesc_learner_word_ok_v1(w, p_text, p_quote) then t := regexp_replace(t, '\m' || lower(w) || '\M', ' ', 'gi'); end if;
  end loop;
  return t;
end $f$;
comment on function security.cdesc_scrub_sentence_v1(text, text) is 'CF-247 F-CDESC: the sentence with the parts that are not claims set aside before the shared wording policy reads it: leading as a verb (to / into / towards / teams / people / others / a team), programme structure (N points, 100-level, Year 1, and a paper code only in a sentence that names a paper, course, unit, subject or module with no money word, $ or currency code beside a number), a supported word (enrich.course_description_supported_words) and the learner word. Used only to TEST the wording; the sentence that is stored and published is never changed. Read only.';
revoke all on function security.cdesc_scrub_sentence_v1(text, text) from public, anon, authenticated;

create or replace function security.cdesc_machine_text_check_v1(p_provider uuid, p_text text, p_sentences jsonb) returns text
language plpgsql stable security definer set search_path to '' as $f$
declare v_s jsonb; v_t text; v_norm text := regexp_replace(lower(btrim(coalesce(p_text, ''))), '\s+', ' ', 'g');
begin
  if jsonb_typeof(p_sentences) is distinct from 'array' or jsonb_array_length(p_sentences) = 0
     or v_norm is distinct from (select regexp_replace(lower(string_agg(btrim(x->>'text'), ' ' order by o)), '\s+', ' ', 'g') from jsonb_array_elements(p_sentences) with ordinality e(x, o)) then
    -- no quote speaks for this text: the shared policy runs on it as it is
    return security.pdesc_machine_text_check_ctx_v1(p_provider, p_text, '{}', p_sentences);
  end if;
  select jsonb_agg(jsonb_set(x, '{text}', to_jsonb(security.cdesc_scrub_sentence_v1(x->>'text', x->>'quote'))) order by o),
         string_agg(btrim(security.cdesc_scrub_sentence_v1(x->>'text', x->>'quote')), ' ' order by o)
    into v_s, v_t from jsonb_array_elements(p_sentences) with ordinality e(x, o);
  return security.pdesc_machine_text_check_ctx_v1(p_provider, v_t, '{}', v_s);
end $f$;
comment on function security.cdesc_machine_text_check_v1(uuid, text, jsonb) is 'CF-247 F-CDESC: the shared machine wording policy (security.pdesc_machine_text_check_ctx_v1: every list and the figures rule, unchanged) applied to a course description after security.cdesc_scrub_sentence_v1 has set aside what is not a claim. Returns null when the wording is admitted, else the first refused word, figure or markup. Read only.';
revoke all on function security.cdesc_machine_text_check_v1(uuid, text, jsonb) from public, anon, authenticated;

create or replace function security.cdesc_parked_other_v1(p_item uuid) returns boolean
language sql stable security definer set search_path to '' as $f$
  -- the machine has declined this waiting item for good for a reason that is not a duplicate: it cannot be admitted, so it does not hold up a twin
  select exists (select 1 from pipeline.course_description_machine_admissions d where d.review_item_id = p_item and d.outcome = 'declined' and d.withdrawn_at is null and not d.transient and d.reason_code not like 'duplicate\_%')
$f$;
comment on function security.cdesc_parked_other_v1(uuid) is 'CF-247 F-CDESC: true when the machine rule has declined the waiting item for good for a reason other than a duplicate (it cannot be admitted, so it must not hold up a twin with the same wording). Read only.';
revoke all on function security.cdesc_parked_other_v1(uuid) from public, anon, authenticated;

create or replace function security.cdesc_provider_slots_v1(p_provider uuid) returns integer
language sql stable security definer set search_path to '' as $f$
  -- the places a provider still has for first descriptions waiting in Layer 4: enrich.course_description_pending_max less the waiting items the machine has NOT declined for good under the current policy (those wait for a person and take no place a reading could use)
  select security.pipeline_num_v1('enrich.course_description_pending_max', 10)::int - count(*)::int
    from pipeline.layer4_review_items q join catalogue.courses c on c.id = q.entity_id
   where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending' and c.provider_id = p_provider
     and not exists (select 1 from pipeline.course_description_machine_admissions d where d.review_item_id = q.id and d.outcome = 'declined' and d.withdrawn_at is null and not d.transient
                        and d.policy_stamp = security.course_description_machine_policy_stamp_v1())
$f$;
comment on function security.cdesc_provider_slots_v1(uuid) is 'CF-247 F-CDESC: the places a provider has left for first course descriptions waiting in Layer 4: enrich.course_description_pending_max less the waiting items that the machine rule has not already declined for good under the current policy stamp. Read only.';
revoke all on function security.cdesc_provider_slots_v1(uuid) from public, anon, authenticated;

create or replace function security.cdesc_recheck_held_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare r record; v_stamp text := security.course_description_machine_policy_stamp_v1(); v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; -- derived: never more in a run than the platform reads in a day
        v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int; v_t0 timestamptz := clock_timestamp(); v_prov jsonb; v_chk jsonb; v_res text; v_looked int := 0; v_noprov int := 0; v_replayed int := 0; v_to_l4 int := 0; v_promoted int := 0; v_p uuid;
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  -- (a) a reading held by a check is looked at again once for each policy stamp: where the live text check now passes and the reader is provable, the one record function takes it as the reader would have
  for r in select e.id, e.course_id, e.value, e.quote from pipeline.field_enrich_items e
            where e.field = 'description' and e.state = 'skipped' and e.reason like 'held: %' and e.course_id is not null and jsonb_typeof(e.value->'sentences') = 'array'
              and e.value->>'recheck_stamp' is distinct from v_stamp and e.updated_at > now() - make_interval(days => v_days)
            order by e.id limit v_cap loop
    exit when clock_timestamp() - v_t0 > make_interval(secs => 20); -- fixed: stays well inside the 120 s statement time-out of the job, with the settle and the follow-up that come after
    v_looked := v_looked + 1;
    begin
      v_prov := security.cdesc_reading_provenance_v1(r.id, r.value);
      v_chk := security.course_description_check_v1(r.course_id, r.value);
      if nullif(v_prov->>'model', '') is null or nullif(v_prov->>'prompt', '') is null then
        v_noprov := v_noprov + 1;
        update pipeline.field_enrich_items set value = value || jsonb_build_object('recheck_stamp', v_stamp) where id = r.id; -- noted; updated_at stays, so the queue's own timing is not moved
      elsif not coalesce((v_chk->>'ok')::boolean, false) then
        update pipeline.field_enrich_items set value = value || jsonb_build_object('recheck_stamp', v_stamp) where id = r.id;
      else
        v_res := security.enrich_course_text_record_v1(r.id, jsonb_build_object('value', r.value || jsonb_build_object('recheck_stamp', v_stamp), 'quote', r.quote,
                                                            'model', v_prov->>'model', 'prompt_version', v_prov->>'prompt', 'worker', v_prov->>'worker'));
        v_replayed := v_replayed + 1; if v_res = 'review' then v_to_l4 := v_to_l4 + 1; end if;
      end if;
    exception when others then null; -- one reading never stops the rest; it is looked at again on the next stamp
    end;
  end loop;
  -- (b) held first-admission readings take the places that are free (declined descriptions no longer fill them)
  for v_p in select distinct e.provider_id from pipeline.field_enrich_items e
              where e.field = 'description' and e.state = 'skipped' and e.reason like 'held\_first\_admission:%' and e.provider_id is not null order by 1 loop
    exit when clock_timestamp() - v_t0 > make_interval(secs => 25); -- fixed: with (a) it stays inside the time box above
    begin v_promoted := v_promoted + security.course_description_promote_held_v1(v_p); exception when others then null; end;
  end loop;
  return jsonb_build_object('on', true, 'looked_at', v_looked, 'no_provable_reader', v_noprov, 'replayed', v_replayed, 'to_layer4', v_to_l4, 'promoted_into_free_places', v_promoted);
end $f$;
comment on function security.cdesc_recheck_held_v1() is 'CF-247 F-CDESC: part of the job course-description-machine. (a) Each reading held by a text check is looked at again once per policy stamp with the live check; one that now passes, whose reader is provable and that is still on the course''s bound page goes through the one record function (identity, lock, cap, Layer 4, then the machine rule) exactly as a fresh reading. (b) Held first-admission readings take the provider places that are free. No AI call, no spend; nothing is admitted here (the machine rule does that). Needs enrich.course_description_machine_on = 1.';
revoke all on function security.cdesc_recheck_held_v1() from public, anon, authenticated;

create or replace function security.cdesc_job_info_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare v_s text;
begin
  begin select j.schedule into v_s from cron.job j where j.jobname = 'course-description-machine' limit 1; exception when others then v_s := null; end;
  return jsonb_build_object('schedule', v_s);
end $f$;
comment on function security.cdesc_job_info_v1() is 'CF-247 F-CDESC: the cron schedule of the job course-description-machine, or null when it cannot be read. Read only.';
revoke all on function security.cdesc_job_info_v1() from public, anon, authenticated;

create or replace function security.data_delivery_cdesc_flow_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; v_pmax int := security.pipeline_num_v1('enrich.course_description_pending_max', 10)::int;
        v_on boolean := security.pipeline_num_v1('enrich.course_description_machine_on', 0) >= 1; v_stamp text := security.course_description_machine_policy_stamp_v1();
        v_day int; v_full int; v_parked int; v_el jsonb; v_blocker text; v_info jsonb := security.cdesc_job_info_v1(); v_dec jsonb; v_held jsonb; v_gain jsonb; v_last timestamptz; v_lastd timestamptz;
begin
  -- the eligible denominator and where each course is: active, no description, a stored, read, identity-proved page (the rule the standing queue uses)
  select jsonb_build_object('active_courses', (select count(*) from catalogue.courses where lifecycle_status = 'active'),
                            'without_description', count(*), 'never_read', count(*) filter (where z.state is null),
                            'waiting_in_layer4', count(*) filter (where z.state = 'review'),
                            'held_behind_provider_cap', count(*) filter (where z.state = 'skipped' and z.reason like 'held\_first\_admission:%'),
                            'held_by_a_check', count(*) filter (where z.state = 'skipped' and z.reason like 'held: %'),
                            'read_other', count(*) filter (where z.state is not null and z.state <> 'review' and not (z.state = 'skipped' and (z.reason like 'held\_first\_admission:%' or z.reason like 'held: %'))))
    into v_el
    from (select m.cid, l.state, l.reason from (select c.id cid from catalogue.courses c where c.lifecycle_status = 'active' and nullif(btrim(c.description), '') is null
                                                   and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.evidence_id is not null and g.status in ('bound', 'ambiguous') and g.read_status = 'read' and g.identity_basis is not null)) m
            left join lateral (select e.state, e.reason from pipeline.field_enrich_items e where e.course_id = m.cid and e.field = 'description' order by e.id desc limit 1) l on true) z;
  select count(*) into v_day from pipeline.field_enrich_items e join pipeline.admin_jobs j on j.id = e.job_id
   where e.field = 'description' and e.created_at > now() - interval '1 day' and coalesce((j.args->>'standing')::boolean, false); -- fixed: the cap is a day's
  select count(*) into v_full from (select c.provider_id from pipeline.layer4_review_items q join catalogue.courses c on c.id = q.entity_id
                                     where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending'
                                       and not exists (select 1 from pipeline.course_description_machine_admissions d where d.review_item_id = q.id and d.outcome = 'declined' and d.withdrawn_at is null and not d.transient and d.policy_stamp = v_stamp)
                                     group by 1 having count(*) >= v_pmax) z;
  select count(*) into v_parked from pipeline.layer4_review_items q where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending'
     and exists (select 1 from pipeline.course_description_machine_admissions d where d.review_item_id = q.id and d.outcome = 'declined' and d.withdrawn_at is null and not d.transient and d.policy_stamp = v_stamp);
  select coalesce(jsonb_agg(jsonb_build_object('code', k, 'n', n) order by n desc, k), '[]'::jsonb) into v_dec
    from (select d.reason_code k, count(*) n from pipeline.course_description_machine_admissions d join pipeline.layer4_review_items q on q.id = d.review_item_id and q.status = 'pending' where d.outcome = 'declined' and d.withdrawn_at is null group by 1) z;
  select coalesce(jsonb_agg(jsonb_build_object('code', k, 'n', n) order by n desc, k), '[]'::jsonb) into v_held
    from (select case when f.reason like 'held\_first\_admission:%' then 'held_first_admission' else btrim(split_part(f.reason, ':', 2)) end k, count(*) n from pipeline.field_enrich_items f
           where f.field = 'description' and f.state = 'skipped' and (f.reason like 'held: %' or f.reason like 'held\_first\_admission:%') group by 1) z;
  select jsonb_build_object('admitted_24h', count(*) filter (where a.outcome = 'admitted' and a.withdrawn_at is null and a.created_at > now() - interval '1 day'),   -- fixed: report windows
                            'admitted_7d', count(*) filter (where a.outcome = 'admitted' and a.withdrawn_at is null and a.created_at > now() - interval '7 days'),
                            'withdrawn_7d', count(*) filter (where a.outcome = 'admitted' and a.withdrawn_at is not null and a.created_at > now() - interval '7 days'),
                            'retained_total', count(*) filter (where a.outcome = 'admitted' and a.withdrawn_at is null)),
         max(a.created_at) filter (where a.outcome = 'admitted'), max(a.created_at) filter (where a.outcome = 'declined')
    into v_gain, v_last, v_lastd from pipeline.course_description_machine_admissions a;
  v_blocker := case when not v_on then 'The automatic admission switch is off (Settings, Course descriptions: automatic admission).'
                    when v_day >= v_cap then format('The daily reading cap is used up: %s of %s reads today (Settings, enrich.course_text_items_per_day). Admissions are limited by how many courses are read a day.', v_day, v_cap)
                    when v_full > 0 then format('%s universities have every place taken by descriptions that wait for a person (enrich.course_description_pending_max); their further readings are held.', v_full)
                    else null end;
  return jsonb_build_object('known', true, 'counted_at', now(), 'unit', 'courses', 'eligible', v_el, 'gain', v_gain,
    'declined_by_cause', v_dec, 'held_by_cause', v_held,
    'reads', jsonb_build_object('today', v_day, 'daily_cap', v_cap, 'universities_with_all_places_taken', v_full, 'parked_for_a_person', v_parked),
    'run', jsonb_build_object('automatic_admission_on', v_on, 'last_admission_at', v_last, 'last_decline_at', v_lastd, 'schedule', v_info->>'schedule'),
    'blocker', v_blocker);
exception when others then
  return jsonb_build_object('known', false, 'reason', 'The flow counts could not be read: ' || sqlerrm);
end $f$;
comment on function security.data_delivery_cdesc_flow_v1() is 'CF-247 F-CDESC: read-only figures for the course description stages in Data Delivery: the eligible denominator (active, no description, a stored read identity-proved page) and where each course is, retained admissions in 24 hours and 7 days, every decline and hold by cause, reads today against enrich.course_text_items_per_day, universities with every place taken, the last admission, the job schedule and the active blocker. A count that cannot be made returns known false, never 0.';
revoke all on function security.data_delivery_cdesc_flow_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the md5-guarded edits
create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
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

create or replace function pg_temp.replace_all(p_sig text, p_before text, p_after text, p_ddl text) returns text language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
begin
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change replaces (body md5 %)', p_sig, md5(v_src); end if;
  execute p_ddl;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the replacement has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

-- 1. the reader check: "students" where the quote says "you"
select pg_temp.edit_all('security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)', '3bb5d62b5e86cd7c76707171e02a3ae5', '6e65745a7863f0dae97a743821475eb0',
  array[$o1$                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'rule', 'unsupported_claim'$o1$],
  array[$n1$                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w) and not security.cdesc_learner_word_ok_v1(w, t, s->>'quote')) then
      return jsonb_build_object('ok', false, 'rule', 'unsupported_claim'$n1$]);

-- 2. the machine rule's evaluator: provable reader, code-proof page margin, course wording policy, twin tie-break
select pg_temp.edit_all('security.course_description_machine_check_v1(uuid)', '3e0fe24d762e7fc4348865ea09499690', '4c321730269064b42ff9ac10a114336b',
  array[$o1$v_recheck text := 'not_run'; v_kind text;$o1$,
        $o2$  if g.basis = 'ai_match' or (g.score is not null and g.runner_up is not null and g.score - g.runner_up < 0.1) then -- fixed:$o2$,
        $o3$  if nullif(btrim(i.layer3_state->>'model'), '') is null or nullif(btrim(i.layer3_state->>'prompt'), '') is null then$o3$,
        $o4$  v_pol := security.pdesc_machine_text_check_ctx_v1(p.id, v_text, '{}', v_sents);$o4$,
        $o5$  select o.entity_id into v_other from pipeline.layer4_review_items o where o.field_code = i.field_code and o.status = 'pending' and o.entity_id <> c.id and md5(security.cdesc_norm_v1(o.proposed_value->>'description')) = v_md5 limit 1;$o5$,
        $o6$r.status in ('pending', 'approved', 'edited_approved') and r.entity_id <> c.id and c2.provider_id <> c.provider_id$o6$,
        $o7$    'model', i.layer3_state->>'model', 'prompt_version', i.layer3_state->>'prompt', 'worker', i.layer3_state->>'worker', 'source_recheck', v_recheck,$o7$],
  array[$n1$v_recheck text := 'not_run'; v_kind text; v_prov jsonb; v_many boolean := false;$n1$,
        $n2$  -- a page bound by the course's own CRICOS code on the page (Decision 265) is a code proof, not a score contest: the margin does not apply to it while no other course is bound to the same address
  if g.basis = 'ai_match' or (g.score is not null and g.runner_up is not null and g.score - g.runner_up < 0.1
                              and not (g.basis = 'cricos_code_on_page' and not exists (select 1 from pipeline.coverage_course_pages g2 where g2.provider_id = g.provider_id and g2.course_id <> g.course_id
                                                                                                                       and (g2.url = g.url or lower(regexp_replace(regexp_replace(g2.url, '[?#].*$', ''), '/+$', '')) = lower(regexp_replace(regexp_replace(g.url, '[?#].*$', ''), '/+$', ''))
                                                                                                                            or (g2.evidence_id is not null and g2.evidence_id = g.evidence_id))))) then -- fixed:$n2$,
        $n3$  -- the reader: recorded on the item, else on the reading, else the stored AI answer that holds exactly this reading's sentences
  v_prov := security.cdesc_reading_provenance_v1(f.id, f.value, i.layer3_state);
  if nullif(v_prov->>'model', '') is null or nullif(v_prov->>'prompt', '') is null then$n3$,
        $n4$  v_pol := security.cdesc_machine_text_check_v1(p.id, v_text, v_sents);$n4$,
        $n5$  -- a twin that waits is only a reason to wait when it is OLDER and can still be admitted; otherwise two courses with the same wording would decline each other for good
  -- wording that waits at three or more different providers is shared training-package wording: nothing is tie-broken, every waiting twin blocks as before
  select count(distinct c3.provider_id) >= 3 into v_many from pipeline.layer4_review_items o3 join catalogue.courses c3 on c3.id = o3.entity_id
   where o3.field_code = i.field_code and o3.status = 'pending' and md5(security.cdesc_norm_v1(o3.proposed_value->>'description')) = v_md5;
  select o.entity_id into v_other from pipeline.layer4_review_items o where o.field_code = i.field_code and o.status = 'pending' and o.entity_id <> c.id and md5(security.cdesc_norm_v1(o.proposed_value->>'description')) = v_md5
     and (v_many or ((o.created_at, o.id) < (i.created_at, i.id) and not security.cdesc_parked_other_v1(o.id))) limit 1;$n5$,
        $n6$(r.status in ('approved', 'edited_approved') or (r.status = 'pending' and (v_many or ((r.created_at, r.id) < (i.created_at, i.id) and not security.cdesc_parked_other_v1(r.id))))) and r.entity_id <> c.id and c2.provider_id <> c.provider_id$n6$,
        $n7$    'model', v_prov->>'model', 'prompt_version', v_prov->>'prompt', 'worker', v_prov->>'worker', 'source_recheck', v_recheck,$n7$]);

-- 3. the one record function: the provider's places, and the reader recorded on a held reading
select pg_temp.edit_all('security.enrich_course_text_record_v1(bigint,jsonb)', 'c52c1969a80f2d3db1d81a4e46a49cd9', '82e93b8b73d1f13ac3fd62dbb59264f9',
  array[$o1$update pipeline.field_enrich_items set state = 'skipped', value = coalesce(p_r->'value', '{}'::jsonb) || jsonb_build_object('check', v_chk),$o1$,
        $o2$    if (select count(*) from pipeline.layer4_review_items r join catalogue.courses c on c.id = r.entity_id
         where r.entity_type = 'course' and r.field_code = 'course_description_first_read' and r.status = 'pending' and c.provider_id = v_pid)
       >= security.pipeline_num_v1('enrich.course_description_pending_max', 10) then$o2$,
        $o3$value = p_r->'value' || jsonb_build_object('text', v_text, 'check', v_chk), quote = left(coalesce(p_r->>'quote', i.quote), 300), updated_at = now() where id = i.id;
      return 'held_first_admission';$o3$],
  array[$n1$update pipeline.field_enrich_items set state = 'skipped', value = coalesce(p_r->'value', '{}'::jsonb) || jsonb_build_object('check', v_chk, 'reader', jsonb_build_object('model', p_r->>'model', 'prompt', p_r->>'prompt_version', 'worker', p_r->>'worker')),$n1$,
        $n2$    -- the provider's places: pending_max less the waiting descriptions the machine has not already declined for good (those wait for a person and take no place a reading could use)
    if security.cdesc_provider_slots_v1(v_pid) <= 0 then$n2$,
        $n3$value = p_r->'value' || jsonb_build_object('text', v_text, 'check', v_chk, 'reader', jsonb_build_object('model', p_r->>'model', 'prompt', p_r->>'prompt_version', 'worker', p_r->>'worker')), quote = left(coalesce(p_r->>'quote', i.quote), 300), updated_at = now() where id = i.id;
      return 'held_first_admission';$n3$]);

-- 4. the promotion of held readings: the same places, and the reader carried to the Layer 4 item
select pg_temp.edit_all('security.course_description_promote_held_v1(uuid)', '1c990fb9c93b1841195160a0e9a712ae', '2f46bf63e50726d67bdd9d7cf74e915a',
  array[$o1$  v_slots := security.pipeline_num_v1('enrich.course_description_pending_max', 10)::int
           - (select count(*) from pipeline.layer4_review_items q join catalogue.courses c on c.id = q.entity_id
               where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending' and c.provider_id = p_provider);$o1$,
        $o2$            jsonb_build_object('item_id', r.id, 'held_first_admission', true),$o2$],
  array[$n1$  v_slots := security.cdesc_provider_slots_v1(p_provider);$n1$,
        $n2$            jsonb_build_object('item_id', r.id, 'held_first_admission', true) || jsonb_strip_nulls(jsonb_build_object('model', security.cdesc_reading_provenance_v1(r.id, r.value)->>'model', 'prompt', security.cdesc_reading_provenance_v1(r.id, r.value)->>'prompt', 'worker', security.cdesc_reading_provenance_v1(r.id, r.value)->>'worker')),$n2$]);

-- 5. the standing queue: rounds across providers, and no reading for a university whose places are all taken by descriptions that wait for a person
select pg_temp.replace_all('security.enrich_course_text_gaps_v1(text[])', '5352bc7ea7bbf3ef00bd616f2897f2f4', '66d9dad4eb0d743b804097b1bf9d38d2', $ddl$
create or replace function security.enrich_course_text_gaps_v1(p_fields text[])
 returns table(provider_id uuid, course_id uuid, field text, pri integer)
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int;
        f text; v_room int; v_gmax int := security.pipeline_num_v1('enrich.course_description_pending_global_max', 0)::int;
        v_pmax int := security.pipeline_num_v1('enrich.course_description_pending_max', 10)::int; v_stamp text := security.course_description_machine_policy_stamp_v1();
begin
  foreach f in array array['description', 'deadline'] loop
    continue when not (f = any (coalesce(p_fields, '{}'::text[])));
    -- back-pressure (CF-247 C-DESC 8 Nov 2026): no new description readings while v_gmax descriptions already wait for a person (0 = off)
    continue when f = 'description' and v_gmax > 0
      and (select count(*) from pipeline.layer4_review_items q where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending') >= v_gmax;
    select v_cap - count(*) into v_room from pipeline.field_enrich_items e join pipeline.admin_jobs j on j.id = e.job_id
     where e.field = f and e.created_at > now() - interval '1 day' and coalesce((j.args->>'standing')::boolean, false);  -- fixed: the cap is a day's
    continue when coalesce(v_room, 0) <= 0;
    return query
      with miss as (
        select c.id cid, c.provider_id pid from catalogue.courses c
         where c.lifecycle_status = 'active'
           and case f when 'description' then nullif(btrim(c.description), '') is null else security.enrich_deadline_missing_v1(c.id) end
           -- read from the stored page only: the slice's rule (bound, or ambiguous with an identity proof, read)
           and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.evidence_id is not null and g.status in ('bound', 'ambiguous')
                         and g.read_status = 'read' and g.identity_basis is not null)),
      last as (
        select distinct on (e.course_id) e.course_id cid, e.state, e.updated_at, e.reason,
               -- a reading held behind the provider's places that never recorded which model and prompt made it, and has no stored answer that proves it: it is read once more so the reader is recorded (the machine rule admits only a provable reader)
               (e.reason like 'held\_first\_admission:%' and nullif(e.value->'reader'->>'model', '') is null
                and not exists (select 1 from pipeline.enrich_ai_answers a where a.item_id = e.id and nullif(a.answer->>'model', '') is not null and nullif(a.answer->>'prompt_version', '') is not null
                                  and a.answer->'value'->'sentences' = e.value->'sentences')) unproven
          from pipeline.field_enrich_items e where e.field = f and e.course_id in (select m.cid from miss m) order by e.course_id, e.id desc),
      -- a university whose every place for a first description is taken by a description that waits for a person (and that the machine has not declined for good) gets no new reading until one is decided
      full_p as (
        select c.provider_id pid from pipeline.layer4_review_items q join catalogue.courses c on c.id = q.entity_id
         where f = 'description' and q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending'
           and not exists (select 1 from pipeline.course_description_machine_admissions d where d.review_item_id = q.id and d.outcome = 'declined' and d.withdrawn_at is null and not d.transient and d.policy_stamp = v_stamp)
         group by 1 having count(*) >= v_pmax and not security.course_description_trusted_v1(c.provider_id)),
      pick as (
        select m.pid, m.cid, case when coalesce(l.unproven, false) then 0 when l.state is null then 1
                                  when exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.cid and g.read_at > l.updated_at) then 0 else 2 end pri
          from miss m left join last l on l.cid = m.cid
         where not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = m.cid and k.field in (f, 'all'))
           and coalesce(l.state, '') not in ('queued', 'waiting', 'ai', 'leased', 'review')
           and (l.state is null or l.state = 'filled' or l.reason = 'provider unpublished' or coalesce(l.unproven, false) or l.updated_at < now() - make_interval(days => v_days)
                or exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.cid and g.read_at > l.updated_at))
           and not security.enrich_item_held_v1(m.cid, f)
           and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = m.pid)
           and not exists (select 1 from full_p fp where fp.pid = m.pid))
      select z.pid, z.cid, f, z.pri
        from (select p.pid, p.cid, p.pri, row_number() over (partition by p.pid, p.pri order by p.cid) rn from pick p) z
       order by z.pri, z.rn, z.cid
       limit v_room;
  end loop;
end $function$
$ddl$);

-- 6. the job: replay the held readings and fill the free places before the settle
select pg_temp.replace_all('security.course_description_machine_run_v1()', '452e3ae1ed2ab196865e2905ad2801e1', 'faa6dab1bfeef3464ba86fac11b34766', $ddl$
create or replace function security.course_description_machine_run_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_a jsonb; v_b jsonb; v_h jsonb;
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  -- one failure never stops the run: each part reports its own error
  begin v_h := security.cdesc_recheck_held_v1(); exception when others then v_h := jsonb_build_object('error', sqlerrm); end;
  begin v_a := security.course_description_machine_settle_v1(); exception when others then v_a := jsonb_build_object('error', sqlerrm); end;
  begin v_b := security.course_description_machine_consumer_recheck_v1(); exception when others then v_b := jsonb_build_object('error', sqlerrm); end;
  return jsonb_build_object('on', true, 'held', v_h, 'settle', v_a, 'consumer', v_b);
end $function$
$ddl$);

-- 7. Data Delivery: the additive key "flow" in the existing course description stages
select pg_temp.edit_all('security.data_delivery_cdesc_stages_v1()', 'd2a913a4d294f71fadf949bff6786f94', 'bf7c8c712273ae99b885e748ff58b998',
  array[$o1$    'validation', jsonb_build_object('not_yet_checked_by_machine'$o1$],
  array[$n1$    'flow', security.data_delivery_cdesc_flow_v1(),
    'validation', jsonb_build_object('not_yet_checked_by_machine'$n1$]);

-- ----------------------------------------------------------------------------------------------------------------------------------------- register
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.cdesc_reading_provenance_v1', 'Layer 4', 'Model, prompt and worker of a course description reading (item, reading or the matching stored AI answer)', 'active', '{}', '20261110180000'),
 ('function', 'security.cdesc_learner_word_ok_v1', 'Layer 4', 'A learner word the sentence may use where its quote says you (no population statement)', 'active', '{}', '20261110180000'),
 ('function', 'security.cdesc_scrub_sentence_v1', 'Layer 4', 'A course sentence with what is not a claim set aside before the shared wording policy reads it (test only)', 'active', '{}', '20261110180000'),
 ('function', 'security.cdesc_machine_text_check_v1', 'Layer 4', 'The shared machine wording policy applied to a course description after the structural parts are set aside', 'active', '{}', '20261110180000'),
 ('function', 'security.cdesc_parked_other_v1', 'Layer 4', 'True when a waiting description is declined for good for a reason that is not a duplicate', 'active', '{}', '20261110180000'),
 ('function', 'security.cdesc_provider_slots_v1', 'Layer 4', 'Places a provider has left for first course descriptions waiting in Layer 4 (declined items take none)', 'active', '{}', '20261110180000'),
 ('function', 'security.cdesc_recheck_held_v1', 'Layer 4', 'Replay of held course description readings and promotion into free places (no AI call)', 'active', '{}', '20261110180000'),
 ('function', 'security.cdesc_job_info_v1', 'Platform', 'Schedule of the job course-description-machine (read only)', 'active', '{}', '20261110180000'),
 ('function', 'security.data_delivery_cdesc_flow_v1', 'Platform', 'Course description flow figures for Data Delivery (eligible denominator, net gain, causes, reads, blocker; read only)', 'active', '{}', '20261110180000')
on conflict do nothing;

-- ----------------------------------------------------------------------------------------------------------------------------------------- post-check
do $post$ begin
  if security.pipeline_num_v1('enrich.course_description_review_first', 0) < 1 then raise exception 'post-check: review_first must be untouched'; end if;
  if position('cdesc_learner_word_ok_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)'::regprocedure)) = 0 then raise exception 'post-check: the reader check does not use the learner word'; end if;
  if position('cdesc_reading_provenance_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_check_v1(uuid)'::regprocedure)) = 0 then raise exception 'post-check: the evaluator does not use the provable reader'; end if;
  if position('cdesc_recheck_held_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_run_v1()'::regprocedure)) = 0 then raise exception 'post-check: the job does not replay held readings'; end if;
  if position('data_delivery_cdesc_flow_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_cdesc_stages_v1()'::regprocedure)) = 0 then raise exception 'post-check: the stages do not carry the flow key'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('enrich.course_description_learner_words', 'enrich.course_description_supported_words')) <> 2 then raise exception 'post-check: the two lists are missing'; end if;
end $post$;
