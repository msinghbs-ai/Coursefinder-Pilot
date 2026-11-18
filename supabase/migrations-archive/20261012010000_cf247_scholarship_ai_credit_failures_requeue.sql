-- CF-247 (12 Oct 2026, 03:00): the OpenRouter key reached its US$75 limit at 02:18 and every AI call failed with HTTP 402 until the
-- Platform Admin raised it to US$125 (about 02:50). Pages whose reading failed only for credit are read again from the first model,
-- and the Layer 4 › AI could not decide items opened only because of credit failures are closed as superseded. Also: a page whose
-- stored rule facts were a bare JSON value failed to record ("cannot delete from scalar"); such facts are now treated as empty.
-- Nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := '{"security.scholarship_ai_facts_v1(jsonb,jsonb,jsonb,text)": "a327bec7eb1933792a3ae471f8773ec6"}'::jsonb;
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
end $function$;

-- Layer 4 items opened only because the model could not be paid for
with r as (
  update pipeline.scholarship_ai_reviews set status = 'superseded', decided_at = now(), note = 'AI credit ran out (HTTP 402); read again from the first model'
   where status = 'pending' and (reason like '%HTTP 402%' or reason like '%cannot delete from scalar%' or reason like '%statement timeout%')
  returning candidate_id, scholarship_id, provider_id, url, storage_path)
insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, candidate_id, scholarship_id, provider_id, url, storage_path)
select a.model_code, a.prompt_version, case when r.scholarship_id is not null then 'reread' else 'admit' end, r.candidate_id, r.scholarship_id, r.provider_id, r.url, r.storage_path
  from r cross join security.scholarship_ai_active_v1() a
 where not exists (select 1 from pipeline.scholarship_ai_queue q where q.state in ('queued', 'leased') and ((r.candidate_id is not null and q.candidate_id = r.candidate_id) or (r.scholarship_id is not null and q.scholarship_id = r.scholarship_id)));
-- Queue items still waiting on a credit failure start again from the first model with fresh attempts
update pipeline.scholarship_ai_queue q set model_code = a.model_code, step = 1, root_id = null, attempts = 0, next_try_at = now()
  from security.scholarship_ai_active_v1() a
 where q.state = 'queued' and q.run_kind in ('admit', 'reread') and exists (select 1 from pipeline.scholarship_ai_extractions e where e.queue_id = q.id and e.error like 'HTTP 402%');
-- Items whose second-model step failed for credit (the first model's answer was not the problem) go back to the first model too
update pipeline.scholarship_ai_queue q set model_code = a.model_code, step = 1, root_id = null, attempts = 0, next_try_at = now()
  from security.scholarship_ai_active_v1() a
 where q.state = 'queued' and q.step = 2 and exists (select 1 from pipeline.scholarship_ai_extractions e where e.queue_id = q.root_id and e.error like 'HTTP 402%');

do $post$
declare v_expected jsonb := '{"security.scholarship_ai_facts_v1(jsonb,jsonb,jsonb,text)": "452f9b5f421314fd5ad94ba0c9212e11"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception '20261012010000 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
