CREATE OR REPLACE FUNCTION security.scholarship_ai_facts_v1(p_answer jsonb, p_checks jsonb, p_rule jsonb, p_label text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare a jsonb := coalesce(p_answer, '{}'::jsonb); k jsonb := coalesce(p_checks, '{}'::jsonb); f jsonb := case when jsonb_typeof(p_rule) = 'object' then p_rule else '{}'::jsonb end - 'criteria';
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
end $function$
