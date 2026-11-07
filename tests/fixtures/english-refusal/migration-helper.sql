create or replace function security.provider_fact_refusal_v1(p_error text) returns boolean
language sql immutable set search_path to 'pg_catalog' as $function$
  -- the names the worker (coverage-sweep useFcWhy / time budget) writes when it refuses a paid read before making it
  select coalesce(p_error in ('budget', 'credits_refused', 'credits_reserve', 'target_list_refused', 'no_firecrawl_key', 'time budget'), false)  -- fixed: the worker's own refusal names
$function$;
comment on function security.provider_fact_refusal_v1(text) is 'CF-247 7 Nov 2026: whether a provider-page read error is a refusal made before the read (credits, target list, run time) and not the page failing.';
