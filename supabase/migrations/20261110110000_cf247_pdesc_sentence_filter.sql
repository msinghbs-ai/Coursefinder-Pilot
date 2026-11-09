-- CF-247 F-PDESC delivery (Platform Admin operating model v1.5, 10 Nov 2026: one successful basic-to-enriched provider admission). One weak sentence no longer sinks a proposal whose other sentences are fully supported.
--
-- Production fact (project fxcwkweaxjtknorudmwp, SELECT only, 10 Nov 2026): the AI provider reader has run 94 times. 2 were admitted, the rest were held or are waiting. The 91 reads held on a sentence rule, by rule:
--   verbatim_passage 54, quote_not_on_page 19, unsupported_claim 10, unsupported_sentence 7, unsupported_numeric_claim 1 (and not_stated 12). Every one of those 91 has its proposal stored (3.9 sentences on average).
-- Shared root cause: security.provider_description_validate_v1 held the WHOLE answer on the first sentence that failed any sentence rule. The model (openai/gpt-4.1-mini) copies its quote into the sentence (text = quote) or adds a point the quote
--   does not state ("dedicated to solving the world's biggest problems", support 0.44). Both are single sentences. The University of Sydney read c8dcd88c had five proposed sentences, every quote on the page, and was held for one of them.
-- Offline replay of the 91 stored proposals (no AI call; supabase/held/pdesc_sentence_filter_replay.sql, SELECT only, run on live 10 Nov 2026): each stored sentence is tested alone with the live validator; sentences that pass every rule are kept; the description
--   needs the set minimum of kept sentences and the set length. 70 of 91 would pass the validator (verbatim_passage 39 of 54, quote_not_on_page 15 of 19, unsupported_claim 9 of 10, unsupported_sentence 6 of 7, unsupported_numeric_claim 1 of 1; 2.1 sentences kept
--   of 3.9 on average); 22 of the 70 are also admissible by the machine word policy, the other 48 are declined by it (a refused word or a figure) and wait for a person in Layer 4 within pdesc.machine_pending_max. The word policy (UNSW, Flinders and Monash
--   list) is not changed. The Sydney read c8dcd88c keeps 4 of its 5 sentences. The duplicate and source-age tests are not replayed (they run at the record).
-- What this changes (two function bodies and one setting value; no new setting, job, table, column or consumer object):
--   1 security.provider_description_validate_v1(uuid,text,timestamptz,jsonb): with p_result.drop_failing = true (only the record of a new read sets it) a sentence that fails a sentence rule is LEFT OUT instead of holding the answer.
--     The sentence rules and their order are the same text as before (quote on the page, marketing words, claim words, campus/scholarship/guarantee evidence, complete sentence, numbers, verbatim span, historic context, support): the body runs
--     them in a single-pass loop and a failing sentence sets v_bad instead of returning. Every KEPT sentence passed every rule. The count, length, age and duplicate tests then run on what is kept. Fewer kept sentences than pdesc.min_sentences hold the
--     read with the rule and reason of the FIRST sentence that failed (the hold names stay verbatim_passage, unsupported_sentence ...). The kept sentences are returned (sentences) and the dropped ones, with the rule, the reason, the support
--     and the text, are returned in checks.dropped. Without drop_failing (the machine admission, the human approval, the picker re-check: every other caller) the first failing sentence holds the answer with the same result as before.
--   2 public.svc_provider_description_record(jsonb): asks for drop_failing, and when the outcome is propose or verified stores the KEPT sentences (proposal.sentences, the Layer 4 item, the machine gate) instead of the model's list. A held
--     answer keeps all the model's sentences for the record. Nothing else in the record changes: identity, locks, evidence, quality holds, capacity, the machine gate and its word policy.
--   3 The setting pdesc.identity_reeval_rules (existing; its value, label and help change, no new setting): it also lists the rules the sentence filter now handles (verbatim_passage, quote_not_on_page, unsupported_sentence, unsupported_claim,
--     unsupported_numeric_claim, unsupported_marketing, claim_negated_in_source, incomplete_sentence, historic_claim_context), so a hold made by an earlier reader behaviour is read again ONCE by the current one (worker v0.60.0 stamps
--     provider-description-source-guard-v4; 20261109185000 and 20261110090000 do the rest). The stored page is read again (no Firecrawl, no new fetch); an AI call is made only after the identity proof and the reservation; the AI
--     ceiling (pdesc.ai_usd_max), the daily guard, pdesc.queue_cap, pdesc.queue_per_run, pdesc.tries and rejection memory (unchanged_rejected_evidence) still apply. About US$0.0009 a read. not_stated is not listed (the model said the page does not describe the institution).
--   Worker v0.60.0 (supabase/functions/coverage-sweep): the prompt asks for one short paraphrase per quote, in the quote's key words, nothing added, and states the copy limit from pdesc.verbatim_span_max_chars; the whole answer is no longer
--   held for a copied sentence. Deploy the worker with this migration (the held reads are read again by whichever reader is running).
-- Every admitted sentence is still on the page, supported, not a long copy, and free of the marketing and claim words; the machine word policy, manual locks, identity proof, rejection memory and budgets are untouched.
-- Live definitions this change edits (pg_proc.prosrc md5, read 10 Nov 2026), before -> after:
--   security.provider_description_validate_v1(uuid,text,timestamptz,jsonb) c1d56ef145b0673d3c475fdaa677ae1d -> 7347f51b70a0c4a6cdd01a117080aad5
--   public.svc_provider_description_record(jsonb) 9b2137954bc05501e55e93c8ef9cf448 -> 5dab0348f912018e517671aef376c5b6
-- Each edit is guarded: the migration stops, and nothing is applied, if a live body is neither the one it replaces nor the one it writes; applying it twice changes nothing. The text before is kept in supabase/held/pdesc_sentence_filter_forward_recovery.sql.
-- Depends on 20261109233000 (the record as it leaves it). Consumer API (G3): not touched (internal provider-description functions and one pipeline setting). No operational number is written into code (G2): the minimum sentences, the length, the
--   support share and the copy limit are still read from pipeline settings. No job is added (G1).
-- Replaces: security.provider_description_validate_v1 (the all-or-nothing sentence test: a failing sentence held the answer) and public.svc_provider_description_record (it stored the model's sentence list for a proposal); the earlier text is kept in supabase/held/pdesc_sentence_filter_forward_recovery.sql
-- Retires: nothing
-- Nothing is dropped, deleted or renamed by this migration; the stored proposals and the held reads are not changed (the picker offers them again).

do $g$
declare r record;
begin
  for r in select * from (values ('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'), ('public.svc_provider_description_record(jsonb)'), ('security.pdesc_has_term_v1(text,text)'), ('security.pdesc_support_v1(text,text)'),
                                 ('security.pdesc_claim_check_v1(text,text,text)'), ('security.pdesc_number_norm_v1(text,boolean)'), ('security.pipeline_num_v1(text,numeric)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.identity_reeval_rules') then raise exception 'required setting pdesc.identity_reeval_rules is missing (apply 20261109185000 first)'; end if;
end $g$;

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

-- the whole new body of one function (the attributes of the live function are kept)
create or replace function pg_temp.replace_body(p_sig text, p_before text, p_after text, p_body text) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_tag text := 'AS $function$'; v_at int;
begin
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_at := position(v_tag in v_def);
  if v_at = 0 then raise exception '%: the definition has no function body tag', p_sig; end if;
  execute substring(v_def from 1 for v_at + length(v_tag) - 1) || replace(p_body, chr(13), '') || '$function$';
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.replace_body('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)', 'c1d56ef145b0673d3c475fdaa677ae1d', '7347f51b70a0c4a6cdd01a117080aad5',
$nb$
-- provider-description-autonomy-v1
declare v_host text := security.provider_page_host_v1(p_provider, p_url);
        v_s jsonb := coalesce(p_result->'sentences', '[]'::jsonb); v_n int; v_text text; s jsonb; t text;
        v_sup numeric; v_min_sup numeric := security.pipeline_num_v1('pdesc.support_min_share', 0.6);
        v_dup numeric := security.pipeline_num_v1('pdesc.duplicate_share', 0.8);
        v_current text; v_other record; v_checks jsonb := '{}'::jsonb; v_claim text;
        v_drop boolean := coalesce((p_result->>'drop_failing')::boolean, false); v_keep jsonb := '[]'::jsonb; v_dropped jsonb := '[]'::jsonb; v_bad jsonb; v_first jsonb; v_idx int := 0; v_ret jsonb;
begin
  v_n := jsonb_array_length(v_s);
  v_text := (select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements(v_s) with ordinality e(x, o));
  v_checks := jsonb_build_object('host', v_host, 'sentences', v_n, 'chars', length(coalesce(v_text, '')));
  if v_host <> 'own' then
    return jsonb_build_object('ok', false, 'outcome', 'refused', 'rule', 'wrong_host', 'checks', v_checks,
      'reason', case v_host when 'other_provider' then 'the page is on another provider''s website' when 'no_url' then 'no page address' else 'the page is not on the provider''s own website' end);
  end if;
  -- pilot 2 Nov 2026 16:16: only the provider's own About or Overview page is a description source
  if not (security.provider_description_page_v1(p_provider, p_url)->>'ok')::boolean then
    return jsonb_build_object('ok', false, 'outcome', 'refused', 'rule', security.provider_description_page_v1(p_provider, p_url)->>'rule', 'checks', v_checks,
      'reason', 'the page is not the provider''s own About or Overview page');
  end if;
  if coalesce((p_result->>'about_page')::boolean, false) is false or v_n = 0 then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'not_stated', 'checks', v_checks, 'reason', 'the page does not describe the institution');
  end if;
  if v_n < security.pipeline_num_v1('pdesc.min_sentences', 2) or v_n > security.pipeline_num_v1('pdesc.max_sentences', 5) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'sentence_count', 'checks', v_checks, 'reason', v_n || ' sentence(s), outside the set range');
  end if;
  for s in select x from jsonb_array_elements(v_s) x loop
    v_idx := v_idx + 1; v_bad := null; v_claim := null;
    t := btrim(coalesce(s->>'text', ''));
    -- the sentence rules, in their order, for one sentence: the first that fails sets v_bad and leaves the pass (a single-pass loop)
    <<chk>>
    loop
      if coalesce((s->>'on_page')::boolean, false) is false or nullif(btrim(coalesce(s->>'quote', '')), '') is null then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'quote_not_on_page', 'checks', v_checks, 'reason', 'a sentence''s quote is not on the page: ' || left(t, 120)); exit chk;
      end if;
      if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb)) w
                  where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_marketing', 'checks', v_checks, 'reason', 'a marketing word that is not in the quote: ' || left(t, 120)); exit chk;
      end if;
      if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w
                  where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_claim', 'checks', v_checks, 'reason', 'a ranking, facility, outcome or accreditation claim that is not in the quote: ' || left(t, 120)); exit chk;
      end if;
      -- Platform Admin 5 Nov 2026 20:03 §2: campus, scholarship and guarantee statements are checked against their official quote, never held by keyword alone
      select r into v_claim from (select security.pdesc_claim_check_v1(t, s->>'quote', w) r from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.evidence_claim_words'), '[]'::jsonb)) w) z where r is not null limit 1;
      if v_claim is not null then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', v_claim, 'checks', v_checks, 'reason', case v_claim when 'claim_negated_in_source' then 'the official quote negates a campus, scholarship or guarantee statement that the sentence makes: ' else 'a campus, scholarship or guarantee statement that its official quote does not support: ' end || left(t, 120)); exit chk;
      end if;
      -- Platform Admin 2 Nov 2026 23:24 ("avoid cutting essential conditions or publishing fragments as complete descriptions"): a sentence
      -- that does not end as a sentence (no closing full stop, question or exclamation mark, or an ellipsis) is a fragment; the description is
      -- held, never cut or completed
      if t !~ '[.!?]["'')\]’”]*$' or t ~ '(\.\.\.|…)["'')\]’”]*$' then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'incomplete_sentence', 'checks', v_checks,
          'reason', 'a sentence is not complete (it would be published as a fragment): ' || left(t, 120)); exit chk;
      end if;
      -- Validation 5 Nov 2026 (decision 20:03 §2): numbers are compared after normalising format (80,000 = 80 000; per cent = %), and the quote's number words count (four = 4).
      if exists(select 1 from regexp_matches(security.pdesc_number_norm_v1(t,false),'[0-9]+(?:[.,][0-9]+)*','g') n where not exists(select 1 from regexp_matches(security.pdesc_number_norm_v1(s->>'quote',true),'[0-9]+(?:[.,][0-9]+)*','g') q where q[1]=n[1])) then
        v_bad := jsonb_build_object('ok',false,'outcome','held','rule','unsupported_numeric_claim','reason','A number in a factual claim does not occur in its supporting quote.','checks',v_checks); exit chk;
      end if;
      -- Quote provenance is retained separately; long verbatim spans fail the existing factual description path.
      if exists(select 1 from generate_series(1,greatest(0,length(regexp_replace(t,'\s+',' ','g'))-security.pipeline_num_v1('pdesc.verbatim_span_max_chars',120)::int+1)) n where position(lower(substring(regexp_replace(t,'\s+',' ','g') from n for security.pipeline_num_v1('pdesc.verbatim_span_max_chars',120)::int)) in lower(regexp_replace(s->>'quote','\s+',' ','g')))>0) then
        v_bad := jsonb_build_object('ok',false,'outcome','held','rule','verbatim_passage','reason','A long official passage was copied; a concise source-grounded paraphrase is required.','checks',v_checks); exit chk;
      end if;
      if coalesce(s->>'quote','')~* '\m(former|formerly|previously|renamed|closed|merged|ceased)\M|was known as|became'
        and t~* '\m(is|are|operates|offers)\M' and t!~* '\m(former|formerly|previously|was|were|became|renamed|closed|merged|ceased|history|founded|established|origin|since)\M'
        -- Validation 5 Nov 2026 (decision 20:03 §2): evidence-aware. Held only when the quote's present-tense part does not support the sentence,
        -- i.e. the sentence's claim is the one the quote places in the past; a historic word elsewhere in the quote never holds a supported claim.
        and security.pdesc_present_support_v1(t, s->>'quote') < v_min_sup then
        v_bad := jsonb_build_object('ok',false,'outcome','held','rule','historic_claim_context','reason','Historical source context cannot establish a present institutional identity or operation.','checks',v_checks); exit chk;
      end if;
      v_sup := security.pdesc_support_v1(t, s->>'quote');
      if v_sup < v_min_sup then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_sentence', 'checks', v_checks || jsonb_build_object('support', v_sup),
          'reason', 'a sentence is not supported by its quote (' || v_sup || '): ' || left(t, 120)); exit chk;
      end if;
      exit chk;
    end loop chk;
    if v_bad is not null then
      -- without drop_failing (every caller except the record of a new read) the first failing sentence holds the whole answer, exactly as before
      if not v_drop then return v_bad; end if;
      v_dropped := v_dropped || jsonb_build_object('index', v_idx, 'rule', v_bad->>'rule', 'reason', left(coalesce(v_bad->>'reason', ''), 300), 'text', left(t, 300), 'quote', left(coalesce(s->>'quote', ''), 300), 'support', v_bad#>'{checks,support}');
      v_first := coalesce(v_first, v_bad);
    else
      v_keep := v_keep || jsonb_build_array(s);
    end if;
  end loop;
  -- sentence filter (the record of a new read only): the sentences that failed a rule are left out, the others are checked as a whole description below.
  -- Every kept sentence passed every sentence rule above; the count, the length, the age and the duplicate tests apply to what is kept. Fewer kept sentences than the set
  -- minimum hold the read with the rule of the first sentence that failed. The dropped sentences and why stay in checks.dropped.
  if v_drop and jsonb_array_length(v_dropped) > 0 then
    v_text := (select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements(v_keep) with ordinality e(x, o));
    v_checks := v_checks || jsonb_build_object('sentences', jsonb_array_length(v_keep), 'sentences_given', v_n, 'chars', length(coalesce(v_text, '')), 'dropped', v_dropped);
    if jsonb_array_length(v_keep) < security.pipeline_num_v1('pdesc.min_sentences', 2) then
      return v_first || jsonb_build_object('checks', v_checks);
    end if;
  end if;
  if length(v_text) < security.pipeline_num_v1('pdesc.min_chars', 150) or length(v_text) > security.pipeline_num_v1('pdesc.max_chars', 900) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'length', 'checks', v_checks, 'reason', length(v_text) || ' characters, outside the set range');
  end if;
  if p_captured_at is not null and p_captured_at < now() - make_interval(days => security.pipeline_num_v1('pdesc.source_max_age_days', 365)::int) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'source_outdated', 'checks', v_checks, 'reason', 'the stored page is older than the set age');
  end if;
  -- duplicate: another provider's description held, or another provider's proposal waiting
  select z.provider_id, z.sim into v_other from (
    select p.id provider_id, security.pdesc_similarity_v1(v_text, p.description) sim from catalogue.providers p
     where p.id <> p_provider and nullif(btrim(p.description), '') is not null
    union all
    select r.provider_id, security.pdesc_similarity_v1(v_text, r.proposal->>'description') from pipeline.provider_description_reads r
     where r.provider_id <> p_provider and r.state = 'proposed') z
   where z.sim >= v_dup order by z.sim desc limit 1;
  if v_other.provider_id is not null then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'duplicate_other_provider', 'checks', v_checks || jsonb_build_object('duplicate_of', v_other.provider_id, 'similarity', v_other.sim),
      'reason', 'the same as another provider''s description (' || v_other.sim || ')');
  end if;
  select nullif(btrim(p.description), '') into v_current from catalogue.providers p where p.id = p_provider;
  if v_current is not null and security.pdesc_similarity_v1(v_text, v_current) >= v_dup then
    v_ret := jsonb_build_object('ok', true, 'outcome', 'verified', 'rule', 'same_as_current', 'text', v_text,
      'checks', v_checks || jsonb_build_object('similarity_current', security.pdesc_similarity_v1(v_text, v_current)), 'reason', 'the page still supports the description held');
    if v_drop then v_ret := v_ret || jsonb_build_object('sentences', v_keep); end if;
    return v_ret;
  end if;
  v_ret := jsonb_build_object('ok', true, 'outcome', 'propose', 'rule', case when v_current is null then 'missing' else 'changed' end, 'text', v_text, 'checks', v_checks, 'reason', null);
  if v_drop then v_ret := v_ret || jsonb_build_object('sentences', v_keep); end if;
  return v_ret;
end 
$nb$);

select pg_temp.edit_all('public.svc_provider_description_record(jsonb)', '9b2137954bc05501e55e93c8ef9cf448', '5dab0348f912018e517671aef376c5b6',
array[
$old$    v_chk := security.provider_description_validate_v1(r.provider_id, r.source_url, r.source_captured_at, x->'answer');$old$],
array[
$new$    -- sentence filter (migration 20261110110000): a sentence that fails a sentence rule is left out and the others are kept; a proposal stores and passes on the KEPT sentences (checks.dropped says what was left out and why)
    v_chk := security.provider_description_validate_v1(r.provider_id, r.source_url, r.source_captured_at, x->'answer' || jsonb_build_object('drop_failing', true));
    if v_chk->>'outcome' in ('propose', 'verified') and v_chk ? 'sentences' then x := jsonb_set(x, '{answer,sentences}', v_chk->'sentences'); end if;$new$]);

-- a hold made by an earlier reader behaviour is read again once by the current one (the setting existed for the identity rules; it now also lists the sentence rules the filter handles)
update pipeline.platform_toolset_settings s
   set value = s.value || coalesce((select jsonb_agg(u.w order by u.o) from unnest(array['verbatim_passage', 'quote_not_on_page', 'unsupported_sentence', 'unsupported_claim', 'unsupported_numeric_claim', 'unsupported_marketing',
                                                                                       'claim_negated_in_source', 'incomplete_sentence', 'historic_claim_context']) with ordinality u(w, o) where not (s.value ? u.w)), '[]'::jsonb),
       label = 'Provider descriptions: holds read again when the reader changes',
       help = 'Hold rules (the identity rules provider_name_conflict, provider_name_not_proved, provider_subunit_source, and the sentence rules verbatim_passage, quote_not_on_page, unsupported_sentence, unsupported_claim, unsupported_numeric_claim, unsupported_marketing, claim_negated_in_source, incomplete_sentence, historic_claim_context). When the reader that made such a hold is not the current reader (its behaviour version differs), the provider is offered to the current reader once more, using the stored official page. A hold the current reader still refuses stays held. Empty: these holds are never offered again before the recheck period.',
       reason = 'CF-247 F-PDESC delivery (Platform Admin operating model v1.5, 10 Nov 2026): holds made by the earlier reader behaviour (copied or unsupported sentences) are read again once by the reader that keeps the sentences that pass every rule',
       updated_at = now()
 where s.toolset_key = 'pipeline' and s.key = 'pdesc.identity_reeval_rules' and exists (select 1 from unnest(array['verbatim_passage', 'quote_not_on_page', 'unsupported_sentence', 'unsupported_claim', 'unsupported_numeric_claim', 'unsupported_marketing',
                                                                                       'claim_negated_in_source', 'incomplete_sentence', 'historic_claim_context']) u(w) where not (s.value ? u.w));
