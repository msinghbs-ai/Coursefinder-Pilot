CREATE OR REPLACE FUNCTION security.flag_provider_held_v1(p_provider_id uuid, p_codes text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (select 1 from pipeline.enrichment_flags f where f.provider_id = p_provider_id and f.entity = 'provider' and f.state = 'raised'
                   and (f.reason_code = any (p_codes) or f.reason_code = 'manual_hold'))
$function$
