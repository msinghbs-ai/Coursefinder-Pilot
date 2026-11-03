CREATE OR REPLACE FUNCTION security.website_refusal_v1(p_url text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  -- CF-247 IQ-00063: why a recorded website cannot be used as a site address, or null (an empty website is the no_website path, not this)
  select case
    when nullif(btrim(coalesce(p_url, '')), '') is null then null
    when btrim(p_url) ~ '\s' then 'it contains spaces'
    when btrim(p_url) !~* '^https?://' then 'it is not an http or https address'
    when substring(btrim(p_url) from '^[A-Za-z]+://([^/?#]*)') like '%@%' then 'it has a user part ("' || split_part(substring(btrim(p_url) from '^[A-Za-z]+://([^/?#]*)'), '@', 1) || '@"), as an email address does'
    when lower(substring(btrim(p_url) from '^[A-Za-z]+://([^/?#:]+)')) !~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}\.?$' then 'its host is not a domain name'
  end
$function$

