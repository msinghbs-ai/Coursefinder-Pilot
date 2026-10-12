CREATE OR REPLACE FUNCTION security.firecrawl_targets_refresh_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n int;
begin
  insert into pipeline.firecrawl_target_cache(provider_id, included, refreshed_at, country, name, domain, rule_match, override_reason, courses)
    select t.provider_id, t.included, now(), t.country, t.name, t.domain, t.rule_match, t.override_reason, t.courses from security.firecrawl_targets_v1() t
  on conflict (provider_id) do update set included = excluded.included, refreshed_at = now(), country = excluded.country, name = excluded.name, domain = excluded.domain, rule_match = excluded.rule_match, override_reason = excluded.override_reason, courses = excluded.courses where pipeline.firecrawl_target_cache.provider_id = excluded.provider_id;
  get diagnostics n = row_count;
  update pipeline.firecrawl_target_cache set included = false, refreshed_at = now() where refreshed_at < now() - interval '30 seconds' and included;
  return n;
end $function$
