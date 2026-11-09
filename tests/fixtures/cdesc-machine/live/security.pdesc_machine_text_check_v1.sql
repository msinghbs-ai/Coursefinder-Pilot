CREATE OR REPLACE FUNCTION security.pdesc_machine_text_check_v1(p_provider uuid, p_text text, p_codes text[] DEFAULT '{}'::text[])
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- no sentences = no quotes to check: the strict rule, as before (the register-fact profile, tier 4, has none)
  return security.pdesc_machine_text_check_ctx_v1(p_provider, p_text, p_codes, '[]'::jsonb);
end $function$;
