-- CF-247 F-CDESC (Platform Admin, 10 Nov 2026, Workstream C): recover the paid-for course readings that are stuck AFTER the read because of a few sentences, by a deterministic SUBTRACTIVE subset, with no AI call, no Firecrawl read, no new setting and no word-list change.
-- Course-description machine route only (the provider description lane, pdesc.* and provider_description_*, is not touched). The consumer API (G3) is not touched: catalogue.courses.description is written only by the existing machine admission, exactly as today.
--
-- Evidence (project fxcwkweaxjtknorudmwp, SELECT only, 10 Nov 2026 evening AEDT). 22,279 of 35,689 active courses have no description; the daily read cap enrich.course_text_items_per_day (2000) is used up every day, so new reads are capped (a cap increase is the Platform Admin's decision and is NOT changed here).
-- Readings that were already paid for are stuck after the read:
--   (a) held at the reader by its own check (pipeline.field_enrich_items.state = 'skipped', reason 'held: <rule>'), latest reading of an active course without a description: length 818, unsupported_claim 645, sentence_count 575, quote_not_on_page 302, unsupported_sentence 178,
--       duplicate_other_course 23, incomplete_sentence 9, unsupported_marketing 6; for about two thirds the reader (model and prompt) is provable from the stored AI answer (pipeline.enrich_ai_answers holds exactly the reading's sentences);
--   (b) waiting in Layer 4 after a machine decline caused by one or a few sentences: policy_refused_word 399 and policy_figure 376 (pipeline.course_description_machine_admissions, outcome declined, current policy stamp, none transient).
-- The design (docs/platform/SHARED-SOURCE-TO-PUBLISHED-ENRICHMENT-DESIGN.md sections 4.1, 4.2 and 5) says: recover a source-supported candidate from wording holds before re-reading, reuse the unchanged stored proof, never re-spend AI or Firecrawl, never override a human refusal or a lock.
--
-- What this changes:
--   1. security.cdesc_sentence_fault_v1 is the ONE definition of the per-sentence tests of the course description check (quote on the page, marketing word, claim word, complete sentence, support by the quote). security.course_description_check_with_v1 now calls it in its sentence loop;
--      the result of the check is unchanged for every input (proved by the fixture against the body from before).
--   2. security.cdesc_subset_plan_v1 (read only) plans the subset of a reading: ONLY the sentences that fail a per-sentence test or the machine wording policy (unsupported claim, marketing word, quote not on the page, unsupported or incomplete sentence, refused word, figure, markup) are set aside.
--      Nothing is ever cut for length: every sentence that passes is kept, in its original order. A reading whose only fault is its length or sentence count (every sentence passes), or whose remainder is still over the set limits, stays held as it is and is counted
--      as over_length_needs_decision (whether to cut for length is the Platform Admin's decision and is NOT taken here). A kept sentence that opens by pointing back (This / It / They / The program / Another / And / Which / However ... or a quote or bracket) right after a sentence that was set aside is
--      NOT used (it would read as a fragment of the missing sentence): that reading stays as it is. The remainder must then pass the SAME full check (security.course_description_check_v1: sentence range, quote on the page, support, length, duplicate guard of the provider) and the
--      machine wording policy. No word is added, reworded or cut.
--   3. security.cdesc_subset_recover_v1 (part of the existing job course-description-machine, before the settle) hands each plan that passes to the EXISTING path inside one sub-transaction that is rolled back unless the machine rule admits it:
--      (a) a held reading goes through security.enrich_course_text_record_v1 (identity proof, bound page unchanged, manual lock, already filled, the provider's places enrich.course_description_pending_max, then the Layer 4 item and the machine rule runs on it as for a fresh reading);
--      (b) a waiting item declined for policy_* / check_* is rewritten to its subset (the original reading and the original proposal are kept inside the subset record) and settled by security.course_description_machine_admit_v1, which runs every machine test again
--          (identity, page margin, stored page, rejection memory, manual hold, duplicates, the wording policy). A reading is tried once for each policy stamp. A reading the reader cannot be proved for (no model and prompt recorded or stored) is not tried.
--      Failures that dropping cannot fix (identity, wrong page, generic page, duplicate of another course, lock, human rejection, remainder below the minimum or still over the limits, the page not supporting the text) stay exactly as they are: nothing is written.
--      No read happens, so the daily read cap is not consumed; the provider places and the policy stamp are respected.
--   4. security.course_description_machine_admit_v1 records an admission whose reading carries a subset with the distinct via 'subset_of_reading' and adds the sentences set aside and why to the decision reason, the decision state and the ledger checks (the original reading, quotes, evidence and history stay).
--   5. security.course_description_machine_run_v1 runs the recovery before the settle.
--   6. Data Delivery: the existing course description flow gains one additive key "subset" (security.data_delivery_cdesc_subset_v1, read only): recovered by subset (24 hours, 7 days, kept, withdrawn) by cause, and the readings still held or waiting by the reason the last attempt gave. Existing keys are unchanged.
--
--   7. security.cdesc_item_detail_v1 and public.admin_course_description_item_v1 (read only, new): the stored latest description item of a course (state, reason, attempts, source, evidence_id, storage_path), so the Fill / refresh result shows, per field, what was examined and whether the field was tried at all (attempts 0: no valid source was read, which is never counted as an attempt or as evidence of absence). The recovery above only ever takes readings that were read (attempts 1 or more, reason 'held: <rule>'); a never-tried item is not touched.
--   8. security.cdesc_page_kind_v1 (read only, new): whether the bound page of a course is a page about THIS course. A university About / Overview / Who we are / Our story / Facts and figures / About-<university> page never stands in for a course page (Platform Admin standing rule), and it fails closed:
--      a missing bound page or address fails. It is used by the subset recovery AND by the owning layer, security.course_description_machine_check_v1 (change 9), so the settle and fresh-reading routes cannot admit such a page either.
--   9. security.course_description_machine_check_v1 gains one md5-guarded step after the existing wrong_page_kind test: the same security.cdesc_page_kind_v1 test, declined as wrong_page_kind (a person decides in Layer 4).
--
-- ACTIVATION (stated plainly): applying this migration IS the activation of the subset recovery. security.course_description_machine_run_v1 (job course-description-machine) calls it on its next run, inside the already approved course machine policy (enrich.course_description_machine_on = 1);
-- no switch other than that one exists. To pause it: set enrich.course_description_machine_on to 0 (Settings, with a reason), or run the forward recovery (supabase/held/cdesc_subset_recovery_forward_recovery.sql). To take back what it admitted:
-- supabase/held/cdesc_subset_bulk_withdraw.sql (paste file, nothing applies it) withdraws every admission whose checks carry subset_of_reading through the existing withdraw function.
-- Settings: none added or changed (G2): every limit is read from the settings the check already reads (min and max sentences, max characters, support share, claim and marketing words, pending_max, recheck days, the daily read figure as the run's upper bound as the replay does). The time box is marked -- fixed: (20 s of its own time and 45 s after the job began, whichever is first; part (a) takes at most 60 % of it so part (b) is not starved).
-- Live definitions this change edits (pg_proc.prosrc md5, read 10 Nov 2026), before -> after (the migration stops, and applies nothing, if a live body is neither):
--   security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)  6e65745a7863f0dae97a743821475eb0 -> d310fa64f61f2243df1416d3e48f6bab
--   security.course_description_machine_admit_v1(uuid,text)            69b8911fe24f041b4cf67a844d8d8f6f -> 569f3ceb95c3d31b378ce7288b7abd24
--   security.course_description_machine_check_v1(uuid)                 4c321730269064b42ff9ac10a114336b -> 2a5b91aa6b93b920bbb80df9920aca09
--   security.course_description_machine_run_v1()                       faa6dab1bfeef3464ba86fac11b34766 -> 42c73e9c0f376150e7778104dfa9830a
--   security.data_delivery_cdesc_flow_v1()                             bd500303727d5c11a708aa99341809a4 -> 3d4c538fc23977018982bc64023a4690
-- Forward recovery (the original bodies, byte for byte): supabase/held/cdesc_subset_recovery_forward_recovery.sql.
-- Consumer API (G3): not touched. No public.website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_*, svc_website_settings_v1, api.* object, table column or edge function is read for change or changed.
-- Withdrawal: an admission by subset is withdrawn like any machine admission, with public.admin_course_description_machine_withdraw_v1(course, reason) (Platform Admin).
-- Replaces: the per-sentence loop of security.course_description_check_with_v1 (now security.cdesc_sentence_fault_v1, same result), the admission audit of security.course_description_machine_admit_v1 (adds the subset record), the page test of security.course_description_machine_check_v1 (one added step), the job body security.course_description_machine_run_v1 and the flow key set of security.data_delivery_cdesc_flow_v1 (edited in place, md5-guarded)
-- Retires: nothing
-- Nothing is dropped or deleted by this migration. No description, Layer 4 item, reading, ledger row or setting is changed by applying it (the job does that afterwards, through the existing record and admission functions).

do $g$
declare r record;
begin
  for r in select * from (values ('security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)'), ('security.course_description_check_v1(uuid,jsonb)'), ('security.course_description_machine_check_v1(uuid)'), ('security.course_description_machine_admit_v1(uuid,text)'),
                                 ('security.course_description_machine_run_v1()'), ('security.data_delivery_cdesc_flow_v1()'), ('security.enrich_course_text_record_v1(bigint,jsonb)'), ('security.cdesc_machine_text_check_v1(uuid,text,jsonb)'),
                                 ('security.cdesc_reading_provenance_v1(bigint,jsonb,jsonb)'), ('security.cdesc_provider_slots_v1(uuid)'), ('security.cdesc_learner_word_ok_v1(text,text,text)'), ('security.cdesc_recheck_held_v1()'),
                                 ('security.course_description_trusted_v1(uuid)'), ('security.course_description_machine_policy_stamp_v1()'), ('security.pdesc_has_term_v1(text,text)'), ('security.pdesc_support_v1(text,text)'),
                                 ('security.toolset_setting(text,text)'), ('security.pipeline_num_v1(text,numeric)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing (apply 20261110180000 first)', r.sig; end if;
  end loop;
  if to_regclass('pipeline.course_description_machine_admissions') is null or to_regclass('pipeline.enrich_ai_answers') is null or to_regclass('pipeline.field_enrich_items') is null or to_regclass('pipeline.layer4_review_items') is null then raise exception 'a table this change relies on is missing'; end if;
end $g$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- new functions
CREATE OR REPLACE FUNCTION security.cdesc_sentence_fault_v1(p_text text, p_quote text, p_on_page boolean, p_claim jsonb, p_mkt jsonb, p_min_support numeric) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare t text := btrim(coalesce(p_text, '')); v_sup numeric;
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
  -- a sentence that does not end as a sentence is a fragment: held, never cut or completed (Platform Admin 2 Nov 2026 23:24)
  if t !~ '[.!?]["'')\]’”]*$' or t ~ '(\.\.\.|…)["'')\]’”]*$' then
    return jsonb_build_object('rule', 'incomplete_sentence', 'reason', 'a sentence is not complete (it would be published as a fragment): ' || left(t, 120));
  end if;
  v_sup := security.pdesc_support_v1(t, p_quote);
  if v_sup < p_min_support then
    return jsonb_build_object('rule', 'unsupported_sentence', 'checks', jsonb_build_object('support', v_sup), 'reason', 'a sentence is not supported by its quote (' || v_sup || '): ' || left(t, 120));
  end if;
  return null;
end $function$;
comment on function security.cdesc_sentence_fault_v1(text, text, boolean, jsonb, jsonb, numeric) is 'CF-247 F-CDESC: the one definition of the per-sentence tests of the course description check (quote on the page, marketing word, claim word with the learner word, complete sentence, support by the quote). Returns null when the sentence passes, else {rule, reason, checks}. Used by security.course_description_check_with_v1 and by the subset recovery. Read only.';
revoke all on function security.cdesc_sentence_fault_v1(text, text, boolean, jsonb, jsonb, numeric) from public, anon, authenticated;

-- The page the reading was taken from must be a page about THIS course. A university About / Overview / Who we are / Our story / Facts and figures page never stands in for a course page (Platform Admin standing rule).
-- Returns null when the page is fine, else the reason: no_bound_page (no address: fails closed), no_course_in_address (the home page), university_about_page, host_page_no_course_evidence.
-- Address rules (file extensions are stripped first, a trailing index / default page name is ignored):
--   an institution-level segment fails, matched by pattern (about-us, about-<anything>, who-we-are, our-story / our-values ..., why-study-with-us, facts-and-figures, at-a-glance, university-profile ...);
--   a bare "about" / "overview" (or about-this-course) in the middle of the address is a parent section (/about/faculty-of-nursing) and fails;
--   as the LAST segment it is a course tab and is accepted only when the segment before it names the course: it holds ALL the distinctive words of the course title (word-set containment), the award word of the title when it has one,
--   and is not a faculty / school / department style segment;
--   a page proved only by the host (identity_basis host_page) needs one such course segment anywhere in the address.
-- Read only; used by the subset recovery and by security.course_description_machine_check_v1.
CREATE OR REPLACE FUNCTION security.cdesc_page_kind_v1(p_url text, p_title text, p_basis text) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
declare v_path text; v_segs text[]; v_n int; v_tok text[]; v_ta text[]; v_st text[]; v_good boolean[]; v_i int; v_clean text; v_dis int;
        -- fixed: the names a university gives its institution-level pages and its course tabs (structure of the web, not an operating value)
        v_inst constant text := '^(about-us|aboutus|about-(?!(this|the|your|our)-(course|program|programme|degree|qualification|unit|study)s?(-|$))[a-z0-9-]+|[a-z0-9-]+-about-us|who-we-are|why-(study|choose|come|join|learn)-(with|at|in)-[a-z0-9-]+|why-us|our-(story|history|values|university|college|institute|mission|vision|people|campus|campuses)(-[a-z0-9-]+)?|facts-(and|n|&)-figures|facts-figures|at-a-glance|(university|college|institute)-(overview|profile|facts)[a-z0-9-]*)$';
        v_amb constant text := '^(about|overview|about-(this|the|your)-(course|program|programme|degree|qualification))$';
        -- fixed: award words and joining words never identify a subject; a word of fewer than four letters never does either (of, in, and, the ...)
        v_award constant text[] := array['bachelor', 'master', 'masters', 'doctor', 'diploma', 'certificate', 'graduate', 'postgraduate', 'honours', 'associate'];
        v_stop constant text[] := array['bachelor', 'master', 'masters', 'doctor', 'diploma', 'certificate', 'graduate', 'postgraduate', 'honours', 'associate', 'degree', 'advanced', 'with', 'level', 'course', 'program', 'programme'];
        -- fixed: a segment that names a faculty, school or department (a part of the university) is not a course
        v_fac constant text[] := array['faculty', 'faculties', 'school', 'schools', 'department', 'departments', 'dept', 'college', 'colleges', 'institute', 'centre', 'center', 'division', 'campus', 'university'];
begin
  if nullif(btrim(coalesce(p_url, '')), '') is null then return 'no_bound_page'; end if;
  v_path := lower(regexp_replace(split_part(split_part(btrim(p_url), '#', 1), '?', 1), '^[a-z][a-z0-9+.-]*://[^/]*', ''));
  v_segs := array(select regexp_replace(x, '\.(html?|shtml|aspx?|php|jsp|cfm)$', '') from regexp_split_to_table(v_path, '/') with ordinality t(x, o) where x <> '' order by o);
  v_n := coalesce(array_length(v_segs, 1), 0);
  while v_n > 1 and v_segs[v_n] in ('index', 'default', 'home') loop v_segs := v_segs[1 : v_n - 1]; v_n := v_n - 1; end loop;
  if v_n = 0 then return 'no_course_in_address'; end if;
  if exists (select 1 from unnest(v_segs) x where x ~ v_inst) then return 'university_about_page'; end if;
  -- a bare about / overview anywhere but at the end is a parent section of the university
  for v_i in 1 .. v_n - 1 loop
    if v_segs[v_i] ~ v_amb then return 'university_about_page'; end if;
  end loop;
  if v_segs[v_n] !~ v_amb and p_basis is distinct from 'host_page' then return null; end if;
  -- the course title: its distinctive subject words and its award words
  v_clean := regexp_replace(regexp_replace(lower(coalesce(p_title, '')), 'level\s*\d+', ' ', 'g'), '[^a-z0-9]+', ' ', 'g');
  v_tok := array(select distinct w from regexp_split_to_table(v_clean, ' ') w where length(w) >= 4 and not (w = any (v_stop))); -- fixed: a word of fewer than four letters never identifies a subject
  v_ta := array(select distinct w from regexp_split_to_table(v_clean, ' ') w where w = any (v_award));
  v_dis := coalesce(array_length(v_tok, 1), 0);
  v_good := array_fill(false, array[v_n]);
  for v_i in 1 .. v_n loop
    continue when v_segs[v_i] ~ v_amb;
    v_st := array(select w from regexp_split_to_table(v_segs[v_i], '[-_]+') w where w <> '');
    -- the segment names the course: all the distinctive title words (word-set containment), an award word of the title if it has one, and no faculty / school / department word the title does not carry
    v_good[v_i] := v_dis > 0 and v_tok <@ v_st and (cardinality(v_ta) = 0 or v_ta && v_st)
                   and not exists (select 1 from unnest(v_st) w where w = any (v_fac) and not (w = any (v_tok)));
  end loop;
  if v_segs[v_n] ~ v_amb then
    if v_n >= 2 and v_good[v_n - 1] then return null; end if;
    return 'university_about_page';
  end if;
  if true = any (v_good) then return null; end if;
  return 'host_page_no_course_evidence';
end $function$;
comment on function security.cdesc_page_kind_v1(text, text, text) is 'CF-247 F-CDESC: null when the address of a bound page is a page about the course; no_bound_page (no address, fails closed), no_course_in_address, university_about_page for an institution-level About / Overview / Who we are / Our story / Facts and figures address or a parent /about/ section, host_page_no_course_evidence for a page proved only by its host with no course in the address. Read only.';
revoke all on function security.cdesc_page_kind_v1(text, text, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.cdesc_subset_plan_v1(p_course uuid, p_provider uuid, p_value jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_s jsonb := coalesce(p_value->'sentences', '[]'::jsonb); n int; i int; s jsonb; f jsonb; t text; v_pol text;
        v_min int := greatest(1, security.pipeline_num_v1('enrich.course_description_min_sentences', 1)::int); v_max int := security.pipeline_num_v1('enrich.course_description_max_sentences', 4)::int;
        v_maxc int := security.pipeline_num_v1('enrich.course_description_max_chars', 700)::int; v_sup numeric := security.pipeline_num_v1('pdesc.support_min_share', 0.6);
        v_claim jsonb := coalesce(security.toolset_setting('pipeline', 'enrich.course_description_claim_words'), security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb);
        v_mkt jsonb := coalesce(security.toolset_setting('pipeline', 'enrich.course_description_marketing_words'), security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb);
        v_fault text[]; v_kept int[] := '{}'; v_drop jsonb := '[]'::jsonb; v_len int := 0; v_add int; v_over boolean; v_sents jsonb := '[]'::jsonb; v_chk jsonb; v_orig text; v_page text;
begin
  if jsonb_typeof(v_s) is distinct from 'array' or jsonb_array_length(v_s) = 0 then return jsonb_build_object('ok', false, 'rule', 'no_sentences', 'reason', 'the reading holds no sentences'); end if;
  n := jsonb_array_length(v_s); v_fault := array_fill(null::text, array[n]);
  -- 0. the bound page must be a page about this course (an institution-level About page never stands in for it)
  select coalesce(security.cdesc_page_kind_v1(g.url, c.canonical_title, g.identity_basis), 'ok') into v_page from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id where g.course_id = p_course limit 1;
  if not found then v_page := 'no_bound_page'; end if; -- fails closed: no bound page row is no proof of the page
  if v_page <> 'ok' then return jsonb_build_object('ok', false, 'rule', v_page, 'reason', 'the bound page is not a page about this course (' || v_page || ')'); end if;
  -- 1. the sentences that fail a per-sentence test or the machine wording policy
  for i in 1 .. n loop
    s := v_s->(i - 1);
    f := security.cdesc_sentence_fault_v1(s->>'text', s->>'quote', coalesce((s->>'on_page')::boolean, false), v_claim, v_mkt, v_sup);
    if f is not null then v_fault[i] := f->>'rule';
    else
      v_pol := security.cdesc_machine_text_check_v1(p_provider, s->>'text', jsonb_build_array(s));
      if v_pol is not null then v_fault[i] := 'policy_' || split_part(v_pol, ':', 1); end if;
    end if;
  end loop;
  -- 2. every sentence that passes is kept, in its original order. Nothing is cut for length or sentence count: a reading whose only fault is its size stays held (the Platform Admin decides that separately)
  for i in 1 .. n loop
    s := v_s->(i - 1); t := btrim(coalesce(s->>'text', ''));
    if v_fault[i] is not null then v_drop := v_drop || jsonb_build_object('index', i, 'text', t, 'cause', v_fault[i]); continue; end if;
    v_add := length(t) + case when cardinality(v_kept) > 0 then 1 else 0 end;
    v_kept := v_kept || i; v_len := v_len + v_add; v_sents := v_sents || s;
  end loop;
  v_over := cardinality(v_kept) > v_max or v_len > v_maxc;
  if jsonb_array_length(v_drop) = 0 then
    if v_over then return jsonb_build_object('ok', false, 'rule', 'over_length_needs_decision', 'reason', 'every sentence passes; the reading is over the set sentence or character limit and is held whole (a decision to cut is not taken here)'); end if;
    return jsonb_build_object('ok', false, 'rule', 'nothing_to_drop', 'reason', 'every sentence passes: dropping sentences cannot change the outcome');
  end if;
  if cardinality(v_kept) < v_min then return jsonb_build_object('ok', false, 'rule', 'remainder_below_minimum', 'reason', cardinality(v_kept) || ' sentence(s) are left, fewer than the set minimum', 'dropped', v_drop); end if;
  if v_over then return jsonb_build_object('ok', false, 'rule', 'over_length_needs_decision', 'reason', 'after the failing sentences are set aside the remainder is still over the set sentence or character limit; it is held whole (a decision to cut is not taken here)', 'dropped', v_drop); end if;
  -- 3. a kept sentence that points back to the sentence before it, which was set aside for a fault, would be published as a fragment of it (the opener list is wider than pronouns: QA, 10 Nov 2026)
  for i in 2 .. n loop
    continue when not (i = any (v_kept)) or v_fault[i - 1] is null;
    -- fixed: a structural test of the grammar (a sentence that opens with a pronoun, a connecting word, "the program" or a quote or bracket), not a tunable limit
    if btrim(coalesce(v_s->(i - 1)->>'text', '')) ~* '^\s*(((this|these|that|those|it|its|they|their|them|he|she|his|her|such|both|also|however|therefore|thus|moreover|furthermore|additionally|in addition|as a result|another|alternatively|further|and|which|here|each|but|or|so|yet|then|instead|otherwise|similarly|likewise|meanwhile|for example|for instance|in particular|the (program|programme|course|degree|qualification|major))\M)|["''“‘(\[«])' then
      return jsonb_build_object('ok', false, 'rule', 'depends_on_dropped_sentence', 'reason', 'sentence ' || i || ' opens by pointing back to sentence ' || (i - 1) || ', which is set aside', 'dropped', v_drop);
    end if;
  end loop;
  -- 4. the remainder goes through the SAME full check and the machine wording policy
  v_chk := security.course_description_check_v1(p_course, p_value || jsonb_build_object('sentences', v_sents));
  if not coalesce((v_chk->>'ok')::boolean, false) then return jsonb_build_object('ok', false, 'rule', 'remainder_' || coalesce(v_chk->>'rule', 'failed'), 'reason', v_chk->>'reason', 'dropped', v_drop); end if;
  v_pol := security.cdesc_machine_text_check_v1(p_provider, v_chk->>'text', v_sents);
  if v_pol is not null then return jsonb_build_object('ok', false, 'rule', 'remainder_policy_' || split_part(v_pol, ':', 1), 'reason', v_pol, 'dropped', v_drop); end if;
  select string_agg(btrim(x->>'text'), ' ' order by o) into v_orig from jsonb_array_elements(v_s) with ordinality e(x, o);
  return jsonb_build_object('ok', true, 'text', v_chk->>'text', 'sentences', v_sents, 'check', v_chk,
    'subset', jsonb_build_object('rule', 'subset_of_reading', 'original_count', n, 'kept_count', cardinality(v_kept), 'kept', to_jsonb(v_kept), 'dropped', v_drop,
                                 'original', jsonb_build_object('sentences', v_s, 'text', v_orig, 'check', p_value->'check')));
end $function$;
comment on function security.cdesc_subset_plan_v1(uuid, uuid, jsonb) is 'CF-247 F-CDESC: the deterministic subtractive plan for a course description reading. Only the sentences that fail a per-sentence test (security.cdesc_sentence_fault_v1) or the machine wording policy are set aside; every other sentence is kept in its original order; nothing is reworded, added or cut, and nothing is dropped for length (a reading over the limits stays held: over_length_needs_decision). A kept sentence that opens by pointing back to a set-aside sentence is not used. The remainder must pass the same full check (security.course_description_check_v1) and the wording policy. Returns {ok, text, sentences, check, subset} or {ok false, rule, reason}. Read only.';
revoke all on function security.cdesc_subset_plan_v1(uuid, uuid, jsonb) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.cdesc_subset_recover_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare r record; v_stamp text := security.course_description_machine_policy_stamp_v1(); v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; -- derived: never more in a run than the platform reads in a day (as the replay)
        v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int; v_t0 timestamptz := clock_timestamp(); v_dl timestamptz; v_dl_a timestamptz; v_tb boolean := false; v_prov jsonb; v_plan jsonb; v_sub jsonb; v_val jsonb; v_res text; v_why text; v_msg text; v_adm jsonb; v_slots jsonb := '{}'::jsonb; v_n int;
        v_looked int := 0; v_rec_a int := 0; v_rec_b int := 0; v_by jsonb := '{}'::jsonb; v_no jsonb := '{}'::jsonb; v_full int := 0; v_item uuid;
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  -- fixed: the whole subset step ends 20 s after it began or 45 s after the job began, whichever comes first, so the replay, the settle and the follow-up that come after it keep their share of the 120 s statement time-out of the job (live runs average 31 s, the longest was 74 s)
  v_dl := least(v_t0 + make_interval(secs => 20), statement_timestamp() + make_interval(secs => 45));
  -- fixed: part (a) may use 60 % of that time box, so part (b) is never starved behind it (what part (a) leaves is part (b)'s)
  v_dl_a := v_t0 + (v_dl - v_t0) * 0.6;
  -- (a) a reading held by the reader's own check: the latest reading of an active course that has no description
  for r in select e.id, e.course_id, e.value, e.quote, c.provider_id, btrim(split_part(e.reason, ':', 2)) cause
             from pipeline.field_enrich_items e join catalogue.courses c on c.id = e.course_id
            where e.field = 'description' and e.state = 'skipped' and e.reason ~ '^held: (sentence_count|length|unsupported_claim|quote_not_on_page|unsupported_sentence|unsupported_marketing|incomplete_sentence):'
              and jsonb_typeof(e.value->'sentences') = 'array' and c.lifecycle_status = 'active' and nullif(btrim(c.description), '') is null
              and e.updated_at > now() - make_interval(days => v_days)
              and e.id = (select max(x.id) from pipeline.field_enrich_items x where x.course_id = e.course_id and x.field = 'description')
              and coalesce(e.value->'subset_attempt'->>'stamp', '') <> v_stamp
            order by e.id limit v_cap loop
    if clock_timestamp() > v_dl_a then v_tb := true; exit; end if;
    v_looked := v_looked + 1; v_why := null; v_sub := null;
    -- the provider's places (enrich.course_description_pending_max): a provider whose places are all taken is left for a later run (nothing is written, so it is not marked)
    if not v_slots ? r.provider_id::text then v_slots := v_slots || jsonb_build_object(r.provider_id::text, security.cdesc_provider_slots_v1(r.provider_id)); end if;
    if (v_slots->>r.provider_id::text)::int <= 0 then v_full := v_full + 1; continue; end if;
    if security.course_description_trusted_v1(r.provider_id) then continue; end if; -- a provider whose first descriptions a person approved is written by the existing trusted route, not by the machine rule
    begin
      v_prov := security.cdesc_reading_provenance_v1(r.id, r.value);
      if nullif(v_prov->>'model', '') is null or nullif(v_prov->>'prompt', '') is null then v_why := 'reader_unrecorded';
      else
        v_plan := security.cdesc_subset_plan_v1(r.course_id, r.provider_id, r.value);
        if not coalesce((v_plan->>'ok')::boolean, false) then v_why := coalesce(v_plan->>'rule', 'plan_failed');
        else
          v_sub := (v_plan->'subset') || jsonb_build_object('cause', r.cause, 'stamp', v_stamp, 'at', now());
          begin
            v_val := (r.value - 'subset_attempt' - 'check') || jsonb_build_object('sentences', v_plan->'sentences', 'subset_of_reading', v_sub);
            v_res := security.enrich_course_text_record_v1(r.id, jsonb_build_object('value', v_val, 'quote', r.quote, 'model', v_prov->>'model', 'prompt_version', v_prov->>'prompt', 'worker', v_prov->>'worker'));
            if v_res is distinct from 'review' then raise exception 'cdesc_subset:record_%', coalesce(v_res, 'nothing'); end if;
            -- recording the waiting item runs the machine rule on it (the trigger of the reading); the subset stands only if that admitted it
            if not exists (select 1 from catalogue.courses c where c.id = r.course_id and c.description = v_plan->>'text') then
              select a.reason_code into v_why from pipeline.course_description_machine_admissions a
               where a.review_item_id = (select (f.value->>'review_item_id')::uuid from pipeline.field_enrich_items f where f.id = r.id) and a.outcome = 'declined' order by a.id desc limit 1;
              raise exception 'cdesc_subset:machine_%', coalesce(v_why, 'not_admitted');
            end if;
            v_rec_a := v_rec_a + 1; v_by := jsonb_set(v_by, array[r.cause], to_jsonb(coalesce((v_by->>r.cause)::int, 0) + 1)); v_why := 'recovered';
          exception when others then
            get stacked diagnostics v_msg = message_text;
            v_why := case when v_msg like 'cdesc_subset:%' then substr(v_msg, length('cdesc_subset:') + 1) else 'error' end; -- the sub-transaction is rolled back: nothing of the attempt stays
          end;
        end if;
      end if;
    exception when others then v_why := 'error';
    end;
    if v_why is distinct from 'recovered' then
      v_no := jsonb_set(v_no, array[v_why], to_jsonb(coalesce((v_no->>v_why)::int, 0) + 1));
      update pipeline.field_enrich_items set value = value || jsonb_build_object('subset_attempt', jsonb_build_object('stamp', v_stamp, 'result', v_why, 'at', now())) where id = r.id and state = 'skipped'; -- noted for this policy stamp; updated_at stays, so the queue's own timing is not moved
    end if;
  end loop;
  -- (b) a waiting first description that the machine declined for its wording (or a check that changed): the item and its reading are rewritten to the subset, and the machine rule decides
  for r in select i.id item_id, i.entity_id course_id, c.provider_id, f.id rid, f.value, d.reason_code cause, i.proposed_value
             from pipeline.layer4_review_items i
             join catalogue.courses c on c.id = i.entity_id and c.lifecycle_status = 'active' and nullif(btrim(c.description), '') is null
             join pipeline.course_description_machine_admissions d on d.review_item_id = i.id and d.outcome = 'declined' and d.withdrawn_at is null and not d.transient and d.policy_stamp = v_stamp
                  and (d.reason_code like 'policy\_%' or d.reason_code like 'check\_%') and d.reason_code not in ('check_duplicate_other_course', 'check_not_stated')
             join pipeline.field_enrich_items f on f.id = case when coalesce(i.proposed_value->>'item_id', '') ~ '^\d+$' then (i.proposed_value->>'item_id')::bigint end and f.state = 'review' and f.course_id = i.entity_id
            where i.entity_type = 'course' and i.field_code = 'course_description_first_read' and i.status = 'pending' and jsonb_typeof(f.value->'sentences') = 'array'
              and coalesce(f.value->'subset_attempt'->>'stamp', '') <> v_stamp
            order by i.created_at, i.id limit v_cap loop
    if clock_timestamp() > v_dl then v_tb := true; exit; end if;
    v_looked := v_looked + 1; v_why := null;
    begin
      v_plan := security.cdesc_subset_plan_v1(r.course_id, r.provider_id, r.value);
      if not coalesce((v_plan->>'ok')::boolean, false) then v_why := coalesce(v_plan->>'rule', 'plan_failed');
      else
        v_sub := (v_plan->'subset') || jsonb_build_object('cause', r.cause, 'stamp', v_stamp, 'at', now());
        begin
          update pipeline.field_enrich_items set value = (value - 'subset_attempt') || jsonb_build_object('sentences', v_plan->'sentences', 'text', v_plan->>'text', 'check', v_plan->'check', 'subset_of_reading', v_sub) where id = r.rid and state = 'review';
          update pipeline.layer4_review_items set proposed_value = proposed_value || jsonb_build_object('description', v_plan->>'text', 'checks', v_plan->'check'->'checks',
                   'sentences', (select jsonb_agg(jsonb_build_object('text', x->>'text', 'quote', x->>'quote') order by o) from jsonb_array_elements(v_plan->'sentences') with ordinality e(x, o)),
                   'subset_of_reading', (v_sub - 'original') || jsonb_build_object('original_proposal', jsonb_build_object('description', r.proposed_value->>'description', 'sentences', r.proposed_value->'sentences')))
           where id = r.item_id and status = 'pending';
          v_adm := security.course_description_machine_admit_v1(r.item_id, 'subset_of_reading');
          if not coalesce((v_adm->>'ok')::boolean, false) then raise exception 'cdesc_subset:machine_%', coalesce(v_adm->>'rule', 'not_admitted'); end if;
          v_rec_b := v_rec_b + 1; v_by := jsonb_set(v_by, array[r.cause], to_jsonb(coalesce((v_by->>r.cause)::int, 0) + 1)); v_why := 'recovered';
        exception when others then
          get stacked diagnostics v_msg = message_text;
          v_why := case when v_msg like 'cdesc_subset:%' then substr(v_msg, length('cdesc_subset:') + 1) else 'error' end; -- rolled back: the item and its reading are as they were
        end;
      end if;
    exception when others then v_why := 'error';
    end;
    if v_why is distinct from 'recovered' then
      v_no := jsonb_set(v_no, array[v_why], to_jsonb(coalesce((v_no->>v_why)::int, 0) + 1));
      update pipeline.field_enrich_items set value = value || jsonb_build_object('subset_attempt', jsonb_build_object('stamp', v_stamp, 'result', v_why, 'at', now())) where id = r.rid and state = 'review';
    end if;
  end loop;
  return jsonb_build_object('on', true, 'looked_at', v_looked, 'recovered_held_readings', v_rec_a, 'recovered_waiting_items', v_rec_b, 'recovered_by_cause', v_by, 'not_recovered_by_reason', v_no, 'provider_places_full', v_full, 'time_box_reached', v_tb);
end $function$;
comment on function security.cdesc_subset_recover_v1() is 'CF-247 F-CDESC: part of the job course-description-machine, before the settle. For a course reading stuck after the read because of a few sentences (held by the reader''s check, or waiting in Layer 4 after a machine decline for its wording), plans the deterministic subset (security.cdesc_subset_plan_v1) and, if it passes, hands it to the existing path inside a sub-transaction that is rolled back unless the machine rule admits it: security.enrich_course_text_record_v1 for a held reading, security.course_description_machine_admit_v1 for a waiting item. No AI call, no page read, no read-cap use; the provider places and the policy stamp are respected; a reading is tried once per policy stamp. Needs enrich.course_description_machine_on = 1. Time-boxed to 20 s and to 45 s after the job began; part (a) takes at most 60 % of the box.';
revoke all on function security.cdesc_subset_recover_v1() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.data_delivery_cdesc_subset_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_stamp text := security.course_description_machine_policy_stamp_v1(); v_by jsonb; v_no jsonb; v_g jsonb;
begin
  select jsonb_build_object('retained_total', count(*) filter (where a.withdrawn_at is null),
                            'admitted_24h', count(*) filter (where a.withdrawn_at is null and a.created_at > now() - interval '1 day'),   -- fixed: report windows
                            'admitted_7d', count(*) filter (where a.withdrawn_at is null and a.created_at > now() - interval '7 days'),   -- fixed: report windows
                            'withdrawn_total', count(*) filter (where a.withdrawn_at is not null)) into v_g
    from pipeline.course_description_machine_admissions a where a.outcome = 'admitted' and a.checks ? 'subset_of_reading';
  select coalesce(jsonb_agg(jsonb_build_object('code', k, 'n', n) order by n desc, k), '[]'::jsonb) into v_by
    from (select a.checks->'subset_of_reading'->>'cause' k, count(*) n from pipeline.course_description_machine_admissions a
           where a.outcome = 'admitted' and a.withdrawn_at is null and a.checks ? 'subset_of_reading' group by 1) z;
  select coalesce(jsonb_agg(jsonb_build_object('code', k, 'n', n) order by n desc, k), '[]'::jsonb) into v_no
    from (select e.value->'subset_attempt'->>'result' k, count(*) n from pipeline.field_enrich_items e
           where e.field = 'description' and e.state in ('skipped', 'review') and e.value->'subset_attempt'->>'stamp' = v_stamp group by 1) z;
  return jsonb_build_object('known', true, 'counted_at', now(), 'unit', 'courses', 'recovered', v_g, 'recovered_by_cause', v_by, 'not_recovered_by_reason', v_no);
exception when others then
  return jsonb_build_object('known', false, 'reason', 'The subset recovery counts could not be read: ' || sqlerrm);
end $function$;
comment on function security.data_delivery_cdesc_subset_v1() is 'CF-247 F-CDESC: read-only figures for the subset recovery of course readings in Data Delivery: descriptions admitted by subset (kept, 24 hours, 7 days, withdrawn) by the cause that held the reading, and the readings still held or waiting by the reason the last attempt of this policy stamp gave. A count that cannot be made returns known false, never 0.';
revoke all on function security.data_delivery_cdesc_subset_v1() from public, anon, authenticated;

-- security.cdesc_item_detail_v1 / public.admin_course_description_item_v1 (read only): for each course, the latest description item exactly as the table holds it, so the Fill / refresh result can show, per field,
-- the value or empty, the source examined (source, evidence_id, storage_path), the reason, the attempts and (in the screen) the next action. An item with attempts 0 was never tried: no valid source was read.
-- No class, state or enum is added: the screen reads attempts and reason as they are. Nothing is written.
CREATE OR REPLACE FUNCTION security.cdesc_item_detail_v1(p_course_ids uuid[]) returns jsonb
language sql stable security definer set search_path to '' as $function$
  select coalesce(jsonb_agg(jsonb_build_object('course_id', c.id, 'field', 'description', 'catalogue_chars', length(btrim(coalesce(c.description, ''))),
           'item', case when e.id is null then null else jsonb_build_object('id', e.id, 'state', e.state, 'reason', e.reason, 'attempts', e.attempts, 'source', e.source,
                      'evidence_id', e.evidence_id, 'storage_path', e.storage_path, 'reading_chars', length(btrim(coalesce(e.value->>'text', ''))), 'at', e.updated_at) end) order by c.id), '[]'::jsonb)
    from catalogue.courses c
    left join lateral (select x.id, x.state, x.reason, x.attempts, x.source, x.evidence_id, x.storage_path, x.value, x.updated_at from pipeline.field_enrich_items x
                        where x.course_id = c.id and x.field = 'description' order by x.id desc limit 1) e on true
   where c.id = any (p_course_ids)
$function$;
revoke all on function security.cdesc_item_detail_v1(uuid[]) from public, anon, authenticated;
comment on function security.cdesc_item_detail_v1(uuid[]) is 'CF-247 F-CDESC: the latest description item of each course as stored (state, reason, attempts, source, evidence, storage path); read only. attempts 0 means no valid source was read, which is not evidence of absence.';
CREATE OR REPLACE FUNCTION public.admin_course_description_item_v1(p_course_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_cap int := 200; -- fixed: the same bound as public.admin_course_description_state_v1 (a hand-made call)
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_course_ids is null or cardinality(p_course_ids) = 0 then return jsonb_build_object('courses', '[]'::jsonb); end if;
  if cardinality(p_course_ids) > v_cap then raise exception 'ask for at most % courses at a time', v_cap; end if;
  return jsonb_build_object('read_at', now(), 'courses', security.cdesc_item_detail_v1(p_course_ids));
end $function$;
revoke all on function public.admin_course_description_item_v1(uuid[]) from public, anon;
grant execute on function public.admin_course_description_item_v1(uuid[]) to authenticated, service_role;
comment on function public.admin_course_description_item_v1(uuid[]) is 'CF-247 F-CDESC: read-only latest description item of the given courses for the Fill / refresh result (rank 3 and above).';

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

-- 1. the check: the sentence loop calls the one definition of the per-sentence tests
select pg_temp.edit_all('security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)', '6e65745a7863f0dae97a743821475eb0', 'd310fa64f61f2243df1416d3e48f6bab',
  array[$o1$s jsonb; t text; v_sup numeric; v_other record;$o1$,
        $o2$    t := btrim(coalesce(s->>'text', ''));
    if coalesce((s->>'on_page')::boolean, false) is false or nullif(btrim(coalesce(s->>'quote', '')), '') is null then
      return jsonb_build_object('ok', false, 'rule', 'quote_not_on_page', 'checks', v_checks, 'reason', 'a sentence''s words are not on the course page: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(v_mkt) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'rule', 'unsupported_marketing', 'checks', v_checks, 'reason', 'a marketing word that is not in the quote: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(v_claim) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w) and not security.cdesc_learner_word_ok_v1(w, t, s->>'quote')) then
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
$o2$],
  array[$n1$s jsonb; t text; v_sup numeric; v_f jsonb; v_other record;$n1$,
        $n2$    -- the per-sentence tests are security.cdesc_sentence_fault_v1 (the one definition, also used to find the sentences a subset recovery sets aside)
    v_f := security.cdesc_sentence_fault_v1(s->>'text', s->>'quote', coalesce((s->>'on_page')::boolean, false), v_claim, v_mkt, v_min_sup);
    if v_f is not null then
      return jsonb_build_object('ok', false, 'rule', v_f->>'rule', 'checks', v_checks || coalesce(v_f->'checks', '{}'::jsonb), 'reason', v_f->>'reason');
    end if;
$n2$]);

-- 2. the admission: the audit of an admission by subset
select pg_temp.edit_all('security.course_description_machine_admit_v1(uuid,text)', '69b8911fe24f041b4cf67a844d8d8f6f', '569f3ceb95c3d31b378ce7288b7abd24',
  array[$o1$v_stamp text; v_next text; v_tr boolean;$o1$,
        $o2$    v_text := v->>'text';$o2$,
        $o3$      insert into pipeline.layer4_decisions (review_item_id, action, actor_id, reason, before_value, proposed_value, final_value, evidence_id, layer2_state, layer3_state, change_control_ref)$o3$,
        $o4$coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'actor_kind', 'machine', 'via', coalesce(p_via, 'settle')), coalesce(i.layer3_state, '{}'::jsonb), v_ref) returning id into v_dec;$o4$,
        $o5$coalesce(v->'checks', '{}'::jsonb) || jsonb_build_object('decision_id', v_dec, 'via', coalesce(p_via, 'settle'), 'source_recheck', v->>'source_recheck', 'captured_at', v->>'captured_at'),$o5$],
  array[$n1$v_stamp text; v_next text; v_tr boolean; v_sub jsonb;$n1$,
        $n2$    v_text := v->>'text';
    -- a reading that carries a subset (security.cdesc_subset_recover_v1): the admission says so, in its own via and in its reason
    select f.value->'subset_of_reading' into v_sub from pipeline.field_enrich_items f where f.id = (v->>'reading_item_id')::bigint;
    if v_sub is not null then p_via := 'subset_of_reading'; v_sub := v_sub - 'original'; end if;$n2$,
        $n3$      if v_sub is not null then
        v_reason := v_reason || format(' Subset of the reading: %s of its %s sentences were kept in their original order; set aside: %s. Nothing was reworded, added or cut; the original reading, its quotes and its history are kept.',
                                       v_sub->>'kept_count', v_sub->>'original_count', coalesce((select string_agg('sentence ' || (d->>'index') || ' (' || (d->>'cause') || ')', ', ' order by (d->>'index')::int) from jsonb_array_elements(v_sub->'dropped') d), 'none'));
      end if;
      insert into pipeline.layer4_decisions (review_item_id, action, actor_id, reason, before_value, proposed_value, final_value, evidence_id, layer2_state, layer3_state, change_control_ref)$n3$,
        $n4$coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'actor_kind', 'machine', 'via', coalesce(p_via, 'settle')) || case when v_sub is not null then jsonb_build_object('subset_of_reading', v_sub) else '{}'::jsonb end, coalesce(i.layer3_state, '{}'::jsonb), v_ref) returning id into v_dec;$n4$,
        $n5$coalesce(v->'checks', '{}'::jsonb) || jsonb_build_object('decision_id', v_dec, 'via', coalesce(p_via, 'settle'), 'source_recheck', v->>'source_recheck', 'captured_at', v->>'captured_at') || case when v_sub is not null then jsonb_build_object('subset_of_reading', v_sub) else '{}'::jsonb end,$n5$]);

-- 2b. the owning layer of the machine rule: a university About / Overview page (or a page with no address, or a host-only page with no course in it) is never a course page, for every route that admits (settle, fresh reading, subset)
select pg_temp.edit_all('security.course_description_machine_check_v1(uuid)', '4c321730269064b42ff9ac10a114336b', '2a5b91aa6b93b920bbb80df9920aca09',
  array[$o1$v_kind text; v_prov jsonb; v_many boolean := false;$o1$,
        $o2$  v_fid := case when coalesce($o2$],
  array[$n1$v_kind text; v_pk text; v_prov jsonb; v_many boolean := false;$n1$,
        $n2$  -- the page must be a page about THIS course: not a university About / Overview page, not a page with no address (security.cdesc_page_kind_v1)
  v_pk := security.cdesc_page_kind_v1(g.url, c.canonical_title, g.identity_basis);
  if v_pk is not null then
    return security.cdesc_machine_fail_v1('wrong_page_kind', 'The bound page is not a page about this course (' || v_pk || '; ' || coalesce(g.url, 'no address') || ').', 'A person decides in Layer 4.'); end if;
  v_fid := case when coalesce($n2$]);

-- 3. the job: the recovery runs before the settle
select pg_temp.replace_all('security.course_description_machine_run_v1()', 'faa6dab1bfeef3464ba86fac11b34766', '42c73e9c0f376150e7778104dfa9830a', $ddl$
create or replace function security.course_description_machine_run_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_a jsonb; v_b jsonb; v_h jsonb; v_s jsonb;
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  -- one failure never stops the run: each part reports its own error
  begin v_h := security.cdesc_recheck_held_v1(); exception when others then v_h := jsonb_build_object('error', sqlerrm); end;
  begin v_s := security.cdesc_subset_recover_v1(); exception when others then v_s := jsonb_build_object('error', sqlerrm); end;
  begin v_a := security.course_description_machine_settle_v1(); exception when others then v_a := jsonb_build_object('error', sqlerrm); end;
  begin v_b := security.course_description_machine_consumer_recheck_v1(); exception when others then v_b := jsonb_build_object('error', sqlerrm); end;
  return jsonb_build_object('on', true, 'held', v_h, 'subset', v_s, 'settle', v_a, 'consumer', v_b);
end $function$
$ddl$);

-- 4. Data Delivery: the additive key "subset" in the existing course description flow
select pg_temp.edit_all('security.data_delivery_cdesc_flow_v1()', 'bd500303727d5c11a708aa99341809a4', '3d4c538fc23977018982bc64023a4690',
  array[$o1$'declined_by_cause', v_dec, 'held_by_cause', v_held,$o1$],
  array[$n1$'declined_by_cause', v_dec, 'held_by_cause', v_held, 'subset', security.data_delivery_cdesc_subset_v1(),$n1$]);

-- ----------------------------------------------------------------------------------------------------------------------------------------- register
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.cdesc_sentence_fault_v1', 'Layer 4', 'The one definition of the per-sentence tests of the course description check (read only)', 'active', '{}', '20261110230000'),
 ('function', 'security.cdesc_subset_plan_v1', 'Layer 4', 'Deterministic subtractive plan of a course reading: sentences set aside, leading sentences kept, remainder checked in full (read only)', 'active', '{}', '20261110230000'),
 ('function', 'security.cdesc_subset_recover_v1', 'Layer 4', 'Recovery of stuck course readings by subset through the existing record and machine admission (no AI call, no page read)', 'active', '{}', '20261110230000'),
 ('function', 'security.data_delivery_cdesc_subset_v1', 'Platform', 'Subset recovery figures for Data Delivery (recovered and not recovered by cause; read only)', 'active', '{}', '20261110230000'),
 ('function', 'security.cdesc_page_kind_v1', 'Layer 4', 'Whether the bound page of a course is a page about the course (not a university About page); read only, used by the subset recovery', 'active', '{}', '20261110230000'),
 ('function', 'security.cdesc_item_detail_v1', 'Platform', 'The latest description item of each course as stored: reason, attempts, source, evidence (read only)', 'active', '{}', '20261110230000'),
 ('function', 'public.admin_course_description_item_v1', 'Platform', 'Per-field result of Fill / refresh course description: the stored item with attempts, source and evidence (read only, rank 3)', 'active', '{}', '20261110230000')
on conflict do nothing;

-- ----------------------------------------------------------------------------------------------------------------------------------------- post-check
do $post$ begin
  if security.pipeline_num_v1('enrich.course_description_review_first', 0) < 1 then raise exception 'post-check: review_first must be untouched'; end if;
  if position('cdesc_sentence_fault_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)'::regprocedure)) = 0 then raise exception 'post-check: the check does not use the one sentence test'; end if;
  if position('subset_of_reading' in (select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_admit_v1(uuid,text)'::regprocedure)) = 0 then raise exception 'post-check: the admission does not record a subset'; end if;
  if position('cdesc_page_kind_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_check_v1(uuid)'::regprocedure)) = 0 then raise exception 'post-check: the machine check does not test the kind of page'; end if;
  if position('cdesc_subset_recover_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_run_v1()'::regprocedure)) = 0 then raise exception 'post-check: the job does not run the subset recovery'; end if;
  if position('data_delivery_cdesc_subset_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_cdesc_flow_v1()'::regprocedure)) = 0 then raise exception 'post-check: the flow does not carry the subset key'; end if;
end $post$;
