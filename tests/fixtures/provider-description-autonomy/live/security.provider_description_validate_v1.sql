CREATE OR REPLACE FUNCTION security.provider_description_validate_v1(p_provider uuid, p_url text, p_captured_at timestamp with time zone, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_host text := security.provider_page_host_v1(p_provider, p_url);
        v_s jsonb := coalesce(p_result->'sentences', '[]'::jsonb); v_n int; v_text text; s jsonb; t text;
        v_sup numeric; v_min_sup numeric := security.pipeline_num_v1('pdesc.support_min_share', 0.6);
        v_dup numeric := security.pipeline_num_v1('pdesc.duplicate_share', 0.8);
        v_current text; v_other record; v_checks jsonb := '{}'::jsonb;
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
    t := btrim(coalesce(s->>'text', ''));
    if coalesce((s->>'on_page')::boolean, false) is false or nullif(btrim(coalesce(s->>'quote', '')), '') is null then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'quote_not_on_page', 'checks', v_checks, 'reason', 'a sentence''s quote is not on the page: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb)) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_marketing', 'checks', v_checks, 'reason', 'a marketing word that is not in the quote: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_claim', 'checks', v_checks, 'reason', 'a ranking, facility, outcome or accreditation claim that is not in the quote: ' || left(t, 120));
    end if;
    -- Platform Admin 2 Nov 2026 23:24 ("avoid cutting essential conditions or publishing fragments as complete descriptions"): a sentence
    -- that does not end as a sentence (no closing full stop, question or exclamation mark, or an ellipsis) is a fragment; the description is
    -- held, never cut or completed
    if t !~ '[.!?]["'')\]’”]*$' or t ~ '(\.\.\.|…)["'')\]’”]*$' then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'incomplete_sentence', 'checks', v_checks,
        'reason', 'a sentence is not complete (it would be published as a fragment): ' || left(t, 120));
    end if;
    v_sup := security.pdesc_support_v1(t, s->>'quote');
    if v_sup < v_min_sup then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_sentence', 'checks', v_checks || jsonb_build_object('support', v_sup),
        'reason', 'a sentence is not supported by its quote (' || v_sup || '): ' || left(t, 120));
    end if;
  end loop;
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
    return jsonb_build_object('ok', true, 'outcome', 'verified', 'rule', 'same_as_current', 'text', v_text,
      'checks', v_checks || jsonb_build_object('similarity_current', security.pdesc_similarity_v1(v_text, v_current)), 'reason', 'the page still supports the description held');
  end if;
  return jsonb_build_object('ok', true, 'outcome', 'propose', 'rule', case when v_current is null then 'missing' else 'changed' end, 'text', v_text, 'checks', v_checks, 'reason', null);
end $function$

