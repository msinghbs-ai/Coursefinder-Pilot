-- CF-247 v2.15.250 hotfix (11 Oct 2026): with AI admission on, every answer with a refusal reason failed to record
-- ("malformed array literal: not_a_scholarship"): appending a text literal to the reasons array needs ::text. 22 pages were affected
-- in the first minutes; their answers were sent on to GPT-4.1 mini as failed replies. Those waiting are sent back to Qwen3 30B.
-- Nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := '{"security.scholarship_ai_facts_v1(jsonb,jsonb,jsonb,text)": "a8a9fc2e927a1245f56a6dacc57cd77b"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION security.scholarship_ai_facts_v1(p_answer jsonb, p_checks jsonb, p_rule jsonb, p_label text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare a jsonb := coalesce(p_answer, '{}'::jsonb); k jsonb := coalesce(p_checks, '{}'::jsonb); f jsonb := coalesce(p_rule, '{}'::jsonb) - 'criteria';
        v jsonb := a->'value'; v_val jsonb; v_aud text := a->>'audience'; v_intl boolean; v_admit boolean; v_reasons text[] := '{}';
begin
  v_intl := v_aud in ('international', 'both') and coalesce((k->>'audience')::boolean, false);
  if not coalesce((a->>'is_scholarship')::boolean, false) then v_reasons := v_reasons || 'not_a_scholarship'::text; end if;
  if not coalesce((a->>'single_scholarship')::boolean, false) then v_reasons := v_reasons || 'listing_page'::text; end if;
  if not coalesce((k->>'name')::boolean, false) then v_reasons := v_reasons || 'no_named_title'::text; end if;
  if v_aud = 'domestic' and coalesce((k->>'audience')::boolean, false) then v_reasons := v_reasons || 'domestic_only'::text;
  elsif not v_intl then v_reasons := v_reasons || 'international_not_stated'::text; end if;
  if a->>'offered' = 'no' and coalesce((k->>'offered')::boolean, false) then v_reasons := v_reasons || 'not_offered'::text; end if;
  v_admit := cardinality(v_reasons) = 0;
  if coalesce((k->>'value')::boolean, false) then
    v_val := case v->>'kind'
      when 'percentage' then jsonb_build_object('type', 'percentage', 'percentage', (v->>'percentage')::numeric, 'applies_to', 'tuition_fee', 'context', v->>'quote')
      when 'full_tuition' then jsonb_build_object('type', 'percentage', 'percentage', 100, 'applies_to', 'tuition_fee', 'context', v->>'quote')
      when 'fixed_amount' then jsonb_build_object('type', 'fixed_amount', 'amount', (v->>'amount')::numeric, 'currency', coalesce(nullif(v->>'currency', ''), 'AUD'), 'context', v->>'quote')
      when 'tiers' then jsonb_build_object('type', 'ambiguous', 'amounts', coalesce((select jsonb_agg((t->>'amount')::numeric) from jsonb_array_elements(coalesce(v->'tiers', '[]'::jsonb)) t where t->>'amount' is not null), '[]'::jsonb),
                                           'percentages', coalesce((select jsonb_agg((t->>'percentage')::numeric) from jsonb_array_elements(coalesce(v->'tiers', '[]'::jsonb)) t where t->>'percentage' is not null), '[]'::jsonb), 'context', v->>'quote')
      else null end;
  end if;
  f := f || jsonb_build_object(
    'extracted_by', 'ai', 'extractor', p_label, 'ai', jsonb_build_object('answer', a, 'checks', k),
    'admission', jsonb_build_object('name', a->>'name', 'admit', v_admit, 'reasons', to_jsonb(v_reasons), 'detail_page', coalesce((a->>'single_scholarship')::boolean, false),
                                    'international_explicit', v_intl, 'offered', coalesce(a->>'offered', 'not_stated') <> 'no', 'by', 'ai'),
    'international', v_intl, 'value', v_val,
    'eligibility_excerpt', nullif(a->>'audience_quote', ''),
    'levels', coalesce(a->'levels', '[]'::jsonb), 'levels_text', nullif(a->>'levels_quote', ''), 'levels_from', 'ai',
    'named_courses', jsonb_build_object('codes', '[]'::jsonb, 'titles', coalesce((select jsonb_agg(jsonb_build_object('title', x, 'text', 'Named on the page (AI, quote checked)')) from jsonb_array_elements_text(coalesce(k->'courses_found', '[]'::jsonb)) x), '[]'::jsonb), 'excluded', '[]'::jsonb),
    'dates', jsonb_build_object('open', case when a->>'open_date' ~ '^\d{4}-\d{2}-\d{2}$' and coalesce((k->>'dates')::boolean, false) then jsonb_build_object('date', a->>'open_date', 'text', a->>'dates_quote', 'precision', 'day') end,
                                'close', case when a->>'close_date' ~ '^\d{4}-\d{2}-\d{2}$' and coalesce((k->>'dates')::boolean, false) then jsonb_build_object('date', a->>'close_date', 'text', a->>'dates_quote', 'precision', 'day') end),
    'criteria', coalesce((select jsonb_agg(c) from jsonb_array_elements(coalesce(p_rule->'criteria', '[]'::jsonb)) c where c->>'type' <> 'student_type'), '[]'::jsonb)
                || case when v_intl then jsonb_build_array(jsonb_build_object('type', 'student_type', 'operator', 'in', 'value_codes', case when v_aud = 'both' then jsonb_build_array('international', 'domestic') else jsonb_build_array('international') end, 'text', a->>'audience_quote', 'by', 'ai'))
                        when v_aud = 'domestic' then jsonb_build_array(jsonb_build_object('type', 'student_type', 'operator', 'in', 'value_codes', jsonb_build_array('domestic'), 'text', a->>'audience_quote', 'by', 'ai'))
                        else '[]'::jsonb end);
  return f;
end $function$;

-- pages whose Qwen3 30B answer failed only because of this fault go back to Qwen3 30B
update pipeline.scholarship_ai_queue q set model_code = 'qwen3-30b', step = 1, root_id = null, attempts = 0, next_try_at = now()
 where q.state = 'queued' and q.step = 2 and q.root_id in (select x.queue_id from pipeline.scholarship_ai_extractions x where x.error like 'svc_scholarship_ai_record: malformed array literal%');

do $post$
declare v_expected jsonb := '{"security.scholarship_ai_facts_v1(jsonb,jsonb,jsonb,text)": "a327bec7eb1933792a3ae471f8773ec6"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception '20261011010500 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
