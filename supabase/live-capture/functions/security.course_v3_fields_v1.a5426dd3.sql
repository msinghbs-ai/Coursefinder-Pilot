CREATE OR REPLACE FUNCTION security.course_v3_fields_v1(p_item jsonb, p_course uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_load text; v_reason text; v_provider uuid; v_cc text;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' then return p_item; end if;
  select c.study_load, c.empty_reason_code, c.provider_id into v_load, v_reason, v_provider from catalogue.courses c where c.id = p_course;
  v_cc := upper(nullif(btrim(coalesce(p_item->>'country_code', '')), ''));
  if jsonb_typeof(p_item->'campuses') = 'array' then
    p_item := jsonb_set(p_item, '{campuses}', (select coalesce(jsonb_agg(case when jsonb_typeof(k) = 'object' then k || jsonb_build_object('locality',
                  case when v_cc is not null and nullif(btrim(coalesce(k->>'postcode', '')), '') is not null then security.destination_locality_for_postcode_v1(v_cc, k->>'postcode') end,
                  -- 20261119042000 (PR D): why the campus is primary (the provider's primary campus at this postcode and city)
                  'primary_basis', case when coalesce((k->>'is_primary')::boolean, false) then
                    (select c.primary_basis from catalogue.campuses c where c.provider_id = v_provider and c.is_primary
                        and c.postcode is not distinct from nullif(btrim(coalesce(k->>'postcode', '')), '')
                        and lower(btrim(coalesce(c.city, ''))) = lower(btrim(coalesce(k->>'city', ''))) order by c.id limit 1) end)
                  else k end order by o), '[]'::jsonb) from jsonb_array_elements(p_item->'campuses') with ordinality t(k, o)));
  end if;
  if jsonb_typeof(p_item->'provider') = 'object' then
    p_item := jsonb_set(p_item, '{provider,accreditations}', security.provider_accreditations_v3_v1(v_provider));
  end if;
  return p_item || jsonb_build_object('study_load', v_load, 'empty_reason_code', v_reason);
end $function$
