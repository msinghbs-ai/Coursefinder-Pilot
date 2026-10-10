CREATE OR REPLACE FUNCTION public.admin_provider_applicants_read(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); p record;
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  select pr.id, pr.enrols_international, pr.enrols_international_basis, k.iso_alpha2::text country into p
    from catalogue.providers pr left join ref.countries k on k.id = pr.country_id where pr.id = p_provider_id;
  if p.id is null then raise exception 'provider not found'; end if;
  return jsonb_build_object(
    'can_edit', v_rank >= 4,
    'enrols_international', p.enrols_international,
    'basis', p.enrols_international_basis,
    'country', p.country,
    'locked', exists (select 1 from pipeline.manual_locks k where k.entity = 'provider' and k.entity_id = p_provider_id and k.field = 'enrols_international'),
    'courses', (select jsonb_build_object(
                  'open_to_international', count(*) filter (where c.open_to_international is true),
                  'domestic_only', count(*) filter (where c.open_to_international is false),
                  'not_known', count(*) filter (where c.open_to_international is null),
                  'set_by_hand', count(*) filter (where exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field = 'open_to_international')))
                  from catalogue.courses c where c.provider_id = p_provider_id and c.lifecycle_status = 'active'));
end $function$
