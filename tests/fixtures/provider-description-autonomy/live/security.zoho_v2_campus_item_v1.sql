CREATE OR REPLACE FUNCTION security.zoho_v2_campus_item_v1(p_campus_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'campus_id', coalesce(k.stable_key, k.id::text), 'name', k.name, 'campus_code', k.campus_code,
    'provider_id', p.stable_key, 'cricos_provider_code', security.zoho_v2_provider_cricos_v1(p.id), 'provider_name', coalesce(p.display_name, p.canonical_name),
    'address_line1', k.address_line1, 'address_line2', k.address_line2, 'city', k.city, 'postcode', k.postcode,
    'subdivision_code', (select s.code from ref.subdivisions s where s.id = k.subdivision_id),
    'country_code', (select c.iso_alpha2 from ref.countries c where c.id = coalesce(k.country_id, p.country_id)),
    'latitude', k.latitude, 'longitude', k.longitude, 'phone', k.phone, 'website', k.website,
    'metro_area', rc.metro_area, 'regional_category', rc.category,
    'course_count', (select count(*) from catalogue.course_campuses cc join catalogue.courses c on c.id = cc.course_id where cc.campus_id = k.id and c.lifecycle_status = 'active'),
    'status', coalesce(k.status, 'active'), 'updated_at', k.updated_at)
  from catalogue.campuses k join catalogue.providers p on p.id = k.provider_id
  left join pipeline.campus_regional_class rc on rc.campus_id = k.id
  where k.id = p_campus_id and p.lifecycle_status = 'active'
    and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
$function$
;

