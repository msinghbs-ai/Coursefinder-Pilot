CREATE OR REPLACE FUNCTION security.provider_description_publication_v1(p_state text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  -- one consumer: matched = verified; the feed holds other text or has no item yet = pending; a consumer that does not serve the provider = not applicable (never a failure); not worked out = null
  select case p_state when 'matched' then 'verified' when 'pending' then 'pending' when 'missing' then 'pending' when 'not_applicable' then 'not_applicable' end
$function$
