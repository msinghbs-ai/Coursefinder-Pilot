CREATE OR REPLACE FUNCTION security.provider_description_validate_v1(p_provider uuid, p_url text, p_captured_at timestamp with time zone, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-autonomy-v1
declare v_host text := security.provider_page_host_v1(p_provider, p_url);
        v_s jsonb := coalesce(p_result->'sentences', '[]'::jsonb); v_n int; v_text text; s jsonb; t text;
        v_sup numeric; v_light boolean := security.pipeline_num_v1('pdesc.prompt_on', 0) >= 1; -- 20261112010000: the prompt profile
        v_min_sup numeric := case when security.pipeline_num_v1('pdesc.prompt_on', 0) >= 1 then security.pipeline_num_v1('pdesc.prompt_support_min_share', 0.5) else security.pipeline_num_v1('pdesc.support_min_share', 0.6) end;
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
  if v_n = 0 then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'not_stated', 'checks', v_checks, 'reason', 'the page does not describe the institution');
  end if;
  -- CF-247 F-PDESC (20261110250000): the model's about_page flag no longer vetoes sentences; it is recorded and every sentence rule below decides
  if coalesce((p_result->>'about_page')::boolean, false) is false then v_checks := v_checks || jsonb_build_object('about_page_flag', false); end if;
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
      if v_light and exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.prompt_refused_words'), '[]'::jsonb)) w where security.pdesc_has_term_v1(t, w)) then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'refused_topic', 'checks', v_checks, 'reason', 'a word a description never carries (ranking, award, outcome, promotion, fees, visas): ' || left(t, 120)); exit chk;
      end if;
      if not v_light and exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb)) w
                  where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_marketing', 'checks', v_checks, 'reason', 'a marketing word that is not in the quote: ' || left(t, 120)); exit chk;
      end if;
      if not v_light and exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w
                  where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_claim', 'checks', v_checks, 'reason', 'a ranking, facility, outcome or accreditation claim that is not in the quote: ' || left(t, 120)); exit chk;
      end if;
      -- Platform Admin 5 Nov 2026 20:03 §2: campus, scholarship and guarantee statements are checked against their official quote, never held by keyword alone
      select r into v_claim from (select security.pdesc_claim_check_v1(t, s->>'quote', w) r from jsonb_array_elements_text(case when v_light then '[]'::jsonb else coalesce(security.toolset_setting('pipeline', 'pdesc.evidence_claim_words'), '[]'::jsonb) end) w) z where r is not null limit 1;
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
      if not v_light and exists(select 1 from generate_series(1,greatest(0,length(regexp_replace(t,'\s+',' ','g'))-security.pipeline_num_v1('pdesc.verbatim_span_max_chars',120)::int+1)) n where position(lower(substring(regexp_replace(t,'\s+',' ','g') from n for security.pipeline_num_v1('pdesc.verbatim_span_max_chars',120)::int)) in lower(regexp_replace(s->>'quote','\s+',' ','g')))>0) then
        v_bad := jsonb_build_object('ok',false,'outcome','held','rule','verbatim_passage','reason','A long official passage was copied; a concise source-grounded paraphrase is required.','checks',v_checks); exit chk;
      end if;
      if not v_light and coalesce(s->>'quote','')~* '\m(former|formerly|previously|renamed|closed|merged|ceased)\M|was known as|became'
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
  -- 20261112010000 (prompt profile): the first sentence names the provider (no description opens with "It ..." or "They ...")
  if v_light and not exists (select 1 from catalogue.providers p cross join lateral unnest(security.pdesc_name_forms_v1(array[p.canonical_name, p.display_name, p.short_name])) nm /* 20261112023700: name forms */
                              where p.id = p_provider and length(btrim(coalesce(nm, ''))) >= security.pipeline_num_v1('pdesc.name_min_chars', 3)
                                and security.pdesc_has_term_v1(replace((select btrim(x->>'text') from jsonb_array_elements(case when v_drop and jsonb_array_length(v_dropped) > 0 then v_keep else v_s end) with ordinality e(x, o) order by o limit 1), '&', ' and '), btrim(nm))) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'first_sentence_no_name', 'checks', v_checks, 'reason', 'the first sentence does not name the provider');
  end if;
  if length(v_text) < security.pipeline_num_v1('pdesc.min_chars', 150) or length(v_text) > security.pipeline_num_v1('pdesc.max_chars', 900) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'length', 'checks', v_checks, 'reason', length(v_text) || ' characters, outside the set range');
  end if;
  if p_captured_at is not null and p_captured_at < now() - make_interval(days => security.pipeline_num_v1('pdesc.source_max_age_days', 365)::int) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'source_outdated', 'checks', v_checks, 'reason', 'the stored page is older than the set age');
  end if;
  -- duplicate: another provider's description held, or another provider's proposal waiting
  select z.provider_id, z.sim into v_other from (
    select f.id provider_id, security.pdesc_similarity_v1(v_text, f.description) sim from (
      -- the cheap count first (a word of the description is always a substring of it, so the count is never below the true overlap; 0.0001 covers the four-decimal rounding of the similarity): a row that cannot reach duplicate_share is not worked out
      select p.id, p.description from catalogue.providers p cross join (select security.pdesc_words_v1(v_text) wa offset 0) w
       where p.id <> p_provider and nullif(btrim(p.description), '') is not null
         and (select count(*) from unnest(w.wa) x where position(x in lower(p.description)) > 0) >= (v_dup - 0.0001) * cardinality(w.wa) -- fixed: rounding slack of pdesc_similarity_v1 (four decimals)
       offset 0) f -- offset 0: optimisation fence, so the count runs before the similarity
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
$function$
