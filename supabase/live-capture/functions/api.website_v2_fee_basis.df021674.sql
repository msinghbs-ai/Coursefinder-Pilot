CREATE OR REPLACE FUNCTION api.website_v2_fee_basis(p_basis text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select case when p_basis ~* 'total|course' and p_basis !~* 'annual' then 'course_total'
              when p_basis ~* 'session|semester|trimester|unit|credit' then 'per_session'
              when p_basis ~* 'indicative' then 'indicative_annual'
              when p_basis ~* 'annual|per.?year|yearly' then 'annual'
              else 'unspecified' end
$function$
