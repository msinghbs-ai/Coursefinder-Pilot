CREATE OR REPLACE FUNCTION security.provider_page_host_v1(p_provider uuid, p_url text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with u as (select regexp_replace(lower(coalesce(substring(p_url from '^https?://([^/?#:]+)'), '')), '^www\.', '') host)
  select case when u.host = '' then 'no_url'
              when exists (select 1 from unnest(security.provider_hosts_v1(p_provider)) h where h <> '' and (u.host = h or u.host like '%.' || h)) then 'own'
              when exists (select 1 from catalogue.providers o, lateral (select regexp_replace(lower(coalesce(substring(o.website from '^(?:https?://)?([^/?#:]+)'), '')), '^www\.', '') b) ob
                            where o.id <> p_provider and o.lifecycle_status = 'active' and ob.b <> '' and (u.host = ob.b or u.host like '%.' || ob.b)) then 'other_provider'
              else 'unknown_host' end
    from u
$function$
