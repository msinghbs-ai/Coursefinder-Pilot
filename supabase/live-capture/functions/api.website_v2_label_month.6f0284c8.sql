CREATE OR REPLACE FUNCTION api.website_v2_label_month(p_label text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select m.n from (values (1,'jan'),(2,'feb'),(3,'mar'),(4,'apr'),(5,'may'),(6,'jun'),(7,'jul'),(8,'aug'),(9,'sep'),(10,'oct'),(11,'nov'),(12,'dec')) m(n,k)
  where strpos(lower(coalesce(p_label,'')), m.k) > 0
  order by strpos(lower(p_label), m.k) limit 1
$function$
