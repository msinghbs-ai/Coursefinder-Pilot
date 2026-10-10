CREATE OR REPLACE FUNCTION public.admin_course_links_read(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); c record;
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  select co.id, co.open_to_international, co.open_to_domestic, co.applicant_basis, p.enrols_international, p.enrols_international_basis,
         coalesce(p.display_name, p.canonical_name) provider_name, k.iso_alpha2::text country_code
    into c from catalogue.courses co join catalogue.providers p on p.id = co.provider_id left join ref.countries k on k.id = p.country_id
   where co.id = p_course_id;
  if c.id is null then raise exception 'course not found'; end if;
  return jsonb_build_object(
    'can_edit', v_rank >= 3,
    'types', (select coalesce(jsonb_agg(jsonb_build_object('code', t.code, 'label', t.label, 'description', t.description, 'applicant', t.applicant) order by t.sort), '[]'::jsonb)
                from ref.course_link_types t where t.status = 'active'),
    'links', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', l.id, 'link_type', l.link_type, 'type_label', t.label, 'url', l.url, 'label', l.label, 'audience', l.audience,
                 'status', l.status, 'is_primary', l.is_primary, 'confidence', l.confidence, 'last_verified_at', l.last_verified_at,
                 'updated_at', l.updated_at, 'source', s.label, 'source_type', s.source_type,
                 'by_hand', s.source_type = 'manual_entry') order by t.sort, (l.status = 'active') desc, l.is_primary desc, l.updated_at desc), '[]'::jsonb)
                from catalogue.course_links l join ref.course_link_types t on t.code = l.link_type left join pipeline.sources s on s.id = l.source_id
               where l.course_id = p_course_id),
    'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k
               where k.entity = 'course' and k.entity_id = p_course_id and (k.field like 'link:%' or k.field in ('official_url','open_to_international','open_to_domestic'))),
    'applicants', jsonb_build_object('open_to_international', c.open_to_international, 'open_to_domestic', c.open_to_domestic, 'basis', c.applicant_basis,
                    'provider_enrols_international', c.enrols_international, 'provider_basis', c.enrols_international_basis,
                    'english_expected', c.open_to_international is true, 'provider', c.provider_name, 'country', c.country_code));
end $function$
