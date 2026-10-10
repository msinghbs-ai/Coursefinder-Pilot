CREATE OR REPLACE FUNCTION api.website_v2_annual(p_opts jsonb, p_reg numeric, p_weeks numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'api'
AS $function$
  with pt as (select api.website_v2_latest_fee(p_opts) o)
  select case when (select o from pt) is not null then
              case api.website_v2_fee_basis((select o->>'basis' from pt))
                   when 'annual' then ((select o->>'amount' from pt))::numeric
                   when 'indicative_annual' then ((select o->>'amount' from pt))::numeric
                   when 'course_total' then case when p_weeks >= 52 then round(((select o->>'amount' from pt))::numeric / (p_weeks/52.0)) end end
              when p_reg >= 1000 and p_weeks >= 52 then round(p_reg / (p_weeks/52.0)) end
$function$
