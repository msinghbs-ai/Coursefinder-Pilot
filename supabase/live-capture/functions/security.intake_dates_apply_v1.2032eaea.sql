CREATE OR REPLACE FUNCTION security.intake_dates_apply_v1(p_limit integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- 4 Nov 2026 (Run now): the body is security.intake_dates_apply_v1(integer, uuid[]); no selector is the scheduled job, as before
  return security.intake_dates_apply_v1(p_limit, null::uuid[]);
end $function$
