CREATE OR REPLACE FUNCTION security.ai_use_allowed_v1(p_use text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- Decision 5 E-7 (2 Nov 2026): one rule for every lane (credit floor, daily ceiling, lane guard), in security.ai_use_refusal_v1
  return security.ai_use_refusal_v1(p_use) is null;
end $function$

