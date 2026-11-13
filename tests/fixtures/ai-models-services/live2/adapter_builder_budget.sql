CREATE OR REPLACE FUNCTION security.adapter_builder_budget()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with today as (select (now() at time zone 'Australia/Melbourne')::date d),
  rounds as (select (p->>'cost')::numeric cost from pipeline.uni_adapter_drafts dr cross join lateral jsonb_array_elements(dr.proposals) p, today
             where ((p->>'at')::timestamptz at time zone 'Australia/Melbourne')::date = today.d)
  select jsonb_build_object('used_usd', coalesce((select sum(cost) from rounds), 0), 'proposals', (select count(*) from rounds),
                            'limit_usd', coalesce((security.firecrawl_setting('builder_ai_daily_usd') #>> '{}')::numeric, 0.5),
                            'limit_proposals', coalesce((security.firecrawl_setting('builder_proposals_per_day') #>> '{}')::int, 30),
                            'model', security.firecrawl_setting('builder_model') #>> '{}')
$function$
