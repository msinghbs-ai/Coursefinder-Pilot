CREATE OR REPLACE FUNCTION security.provider_hosts_v1(p_provider uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(array_agg(distinct h) filter (where h <> ''), '{}'::text[]) from (
    select regexp_replace(lower(coalesce(substring(p.website from '^(?:https?://)?([^/?#:]+)'), '')), '^www\.', '') h
      from catalogue.providers p where p.id = p_provider
    union all
    select regexp_replace(x, '^www\.', '')
      from catalogue.providers p, jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'binding.provider_host_aliases'), '[]'::jsonb)) e,
           regexp_split_to_table(lower(btrim(substr(e, strpos(e, '=') + 1))), '\s+') x
     where p.id = p_provider and lower(split_part(e, '=', 1)) = lower(p.stable_key)
    union all
    select regexp_replace(lower(d.domain), '^(https?://)?(www\.)?', '') from pipeline.provider_extra_domains d where d.provider_id = p_provider and d.state = 'approved') z
$function$

