CREATE OR REPLACE FUNCTION security.fc_billed_today_v1()
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with o as (select v.observed_at, v.remaining_units, v.period_end from pipeline.vendor_credit_observations v
               join pipeline.layer2_acquisition_providers p on p.id = v.provider_id and p.provider_key = 'firecrawl'
              where v.observed_at > security.fc_day_start_v1() - interval '1 hour'),
       l as (select * from o order by observed_at desc limit 1),
       f as (select o.* from o, l where o.period_end = l.period_end order by o.observed_at limit 1)
  select coalesce(greatest(0, (select remaining_units from f) - (select remaining_units from l)), 0)
$function$
