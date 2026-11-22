CREATE OR REPLACE FUNCTION public.website_v3_provider_item(p_item jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_provider uuid; v_campuses jsonb; v_page record; v_cc text;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' or not (p_item ? 'campuses') then return p_item; end if;
  select p.id, (select c.iso_alpha2 from ref.countries c where c.id = p.country_id) into v_provider, v_cc from catalogue.providers p where p.stable_key = p_item->>'provider_id';
  if v_provider is null then return p_item; end if;
  with k as (
    select k.id, k.stable_key, k.name, k.city, k.postcode, k.subdivision_id, k.country_id, k.is_primary, k.primary_basis
      from catalogue.campuses k
     where k.provider_id = v_provider and nullif(btrim(k.city), '') is not null and coalesce(k.status, 'active') <> 'inactive'),
  n as (
    -- one grouped read per provider, never one per campus
    select cc.campus_id, count(distinct cc.course_id) n
      from search.course_documents d
      join catalogue.course_campuses cc on cc.course_id = d.course_id
     where d.provider_id = v_provider
       -- checked per course: an anti-join builds the whole view on every call (measured 12 Nov 2026: 50 providers 2.3 s, per course 0.15 s)
       and (select count(*) from security.layer4_search_blocked_courses b where b.course_id = cc.course_id) = 0
     group by cc.campus_id)
  select coalesce(jsonb_agg(jsonb_build_object('city', security.place_presentable(k.city), 'postcode', k.postcode, 'subdivision_code', s.code,
           'metro_area', rc.metro_area, 'regional_category', rc.category, 'regional_category_name', rc.category_name,
           'campus_id', k.stable_key, 'campus_name', nullif(btrim(k.name), ''), 'course_count', coalesce(n.n, 0),
           'is_primary', coalesce(k.is_primary, false), 'primary_basis', k.primary_basis,  -- 20261119042000 (PR D)
           -- G-5 (17 Nov 2026): the approved locality the campus postcode maps to; null until it has a primary match
           'locality', security.destination_locality_for_postcode_v1(coalesce((select c.iso_alpha2 from ref.countries c where c.id = k.country_id), v_cc), k.postcode))
           order by lower(nullif(btrim(k.name), '')) nulls last, k.stable_key), '[]'::jsonb)
    into v_campuses
    from k
    left join ref.subdivisions s on s.id = k.subdivision_id
    left join pipeline.campus_regional_class rc on rc.campus_id = k.id
    left join n on n.campus_id = k.id;
  -- R31: the scholarships listing page the platform reads for this provider, and when it was last read
  select lp.url, lp.read_at into v_page
    from pipeline.scholarship_listing_pages lp
   where lp.provider_id = v_provider and lp.active and lp.status = 'read' and lp.read_at is not null
   order by lp.read_at desc, lp.id limit 1;
  return jsonb_set(p_item, '{campuses}', v_campuses)
         || jsonb_build_object('scholarships_page_url', v_page.url, 'scholarships_last_reviewed_at', v_page.read_at,
                               'accreditations', security.provider_accreditations_v3_v1(v_provider),  -- 18 Nov 2026 (REQ-57)
                               'accreditation_crown', security.provider_accreditation_crown_v1(v_provider));  -- s798 B1
end $function$
