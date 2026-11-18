CREATE OR REPLACE FUNCTION security.cdesc_known_strip_v1(p_text text, p_title text, p_provider text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare t text := coalesce(p_text, ''); x text;
begin
  -- the course's own title and provider (and the provider without Pty Ltd, Limited, Ltd or Inc) are taken out of a sentence, as whole phrases, before its tests;
  -- fixed: a name shorter than 4 characters is left in (an acronym such as MBA is also a common word in a sentence)
  foreach x in array array[p_title, p_provider, regexp_replace(coalesce(p_provider, ''), '\s+(pty\.?\s+ltd\.?|limited|ltd\.?|inc\.?)$', '', 'i')] loop
    continue when length(btrim(coalesce(x, ''))) < 4;
    t := regexp_replace(t, '(^|[^[:alnum:]])' || regexp_replace(btrim(x), '([.+*?^$(){}|/\\\[\]-])', '\\\1', 'g') || '(?![[:alnum:]])', '\1', 'gi');
  end loop;
  return t;
end $function$
