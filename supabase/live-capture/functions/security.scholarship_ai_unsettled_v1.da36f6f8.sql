CREATE OR REPLACE FUNCTION security.scholarship_ai_unsettled_v1(p_answer jsonb, p_checks jsonb, p_verdict text, p_error text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case
    when p_error is not null then 'the model''s reply failed: ' || left(p_error, 120)
    when p_verdict = 'unproven' then 'the scholarship''s name is not on the page'
    when p_verdict = 'scholarship' and coalesce(p_answer->>'audience', 'not_stated') <> 'not_stated' and not coalesce((p_checks->>'audience')::boolean, false) then 'who it is for is not proven by a quote on the page'
    when p_verdict = 'scholarship' and coalesce(p_answer->'value'->>'kind', 'not_stated') not in ('not_stated', 'non_monetary') and not coalesce((p_checks->>'value')::boolean, false) then 'the value is not proven by a quote on the page'
    when p_verdict = 'scholarship' and p_answer->>'offered' = 'no' and not coalesce((p_checks->>'offered')::boolean, false) then '"no longer offered" is not proven by a quote on the page'
  end
$function$
