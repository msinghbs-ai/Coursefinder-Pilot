CREATE OR REPLACE FUNCTION security.zoho_v2_provider_item_v1(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p catalogue.providers%rowtype; v jsonb;
begin
  select * into p from catalogue.providers where id = p_provider_id;
  if p.id is null or p.lifecycle_status <> 'active' or exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id) then return null; end if;
  -- the website item where the provider has courses (rankings, outcomes, logo, campuses summary), else the basic facts
  select w.item into v from pipeline.website_sync_items w where w.entity = 'provider' and w.item_key = p.stable_key and w.removed_at is null;
  v := coalesce(v, jsonb_build_object('provider_id', p.stable_key, 'name', coalesce(p.display_name, p.canonical_name), 'legal_name', p.canonical_name,
         'website', p.website, 'institution_type', api.website_v2_institution_type(p.id), 'course_count', 0, 'publication_status', 'published'));
  return v || jsonb_build_object(
    'cricos_provider_code', security.zoho_v2_provider_cricos_v1(p.id),
    'country_code', (select c.iso_alpha2 from ref.countries c where c.id = p.country_id),
    'subdivision_code', (select s.code from ref.subdivisions s where s.id = p.subdivision_id),
    'city', p.primary_city, 'postcode', p.postcode, 'phone', p.phone, 'email', p.email,
    'campus_count', (select count(*) from catalogue.campuses k where k.provider_id = p.id and coalesce(k.status, 'active') = 'active'),
    'contact_count', (select count(*) from pipeline.provider_contact_points cp where cp.provider_id = p.id and cp.is_current)
                     + (select count(*) from pipeline.provider_contacts pc where pc.provider_id = p.id and pc.lifecycle_status = 'active' and pc.deleted_at is null),
    'updated_at', p.updated_at);
end $function$
;

