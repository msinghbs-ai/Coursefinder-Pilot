CREATE OR REPLACE FUNCTION api.website_v2_provider_campuses(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'pipeline', 'security'
AS $function$
  select coalesce(jsonb_agg(distinct jsonb_build_object('city', security.place_presentable(k.city), 'postcode', k.postcode, 'subdivision_code', s.code,
           'metro_area', rc.metro_area, 'regional_category', rc.category, 'regional_category_name', rc.category_name)), '[]'::jsonb)
  from catalogue.campuses k
  left join ref.subdivisions s on s.id = k.subdivision_id
  left join pipeline.campus_regional_class rc on rc.campus_id = k.id
  where k.provider_id = p_provider_id and nullif(btrim(k.city),'') is not null and coalesce(k.status,'active') <> 'inactive'
$function$
