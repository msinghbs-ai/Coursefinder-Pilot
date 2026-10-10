CREATE OR REPLACE FUNCTION public.admin_link_refresh_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'can_edit', v_rank >= 4,
    'policies', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'country', k.iso_alpha2, 'country_name', k.name, 'provider_id', r.provider_id,
                   'provider', coalesce(p.display_name, p.canonical_name), 'link_type', r.link_type, 'type_label', t.label, 'every_days', r.every_days,
                   'active', r.active, 'notes', r.notes, 'last_run_at', r.last_run_at, 'last_result', r.last_result)
                   order by t.sort, k.iso_alpha2 nulls first, p.canonical_name nulls first), '[]'::jsonb)
                   from pipeline.link_refresh_policies r join ref.course_link_types t on t.code = r.link_type
                   left join ref.countries k on k.id = r.country_id left join catalogue.providers p on p.id = r.provider_id),
    'portals', (select coalesce(jsonb_agg(jsonb_build_object('code', lp.code, 'label', lp.label, 'country', k.iso_alpha2, 'kind', lp.kind,
                   'link_type', lp.link_type, 'base_url', lp.base_url, 'applicant', lp.applicant, 'active', lp.active, 'every_days', lp.every_days,
                   'last_run_at', lp.last_run_at, 'last_result', lp.last_result, 'notes', lp.notes) order by k.iso_alpha2, lp.code), '[]'::jsonb)
                  from pipeline.link_portals lp left join ref.countries k on k.id = lp.country_id),
    'types', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'label', label) order by sort), '[]'::jsonb) from ref.course_link_types where status = 'active'),
    'countries', (select coalesce(jsonb_agg(distinct k.iso_alpha2), '[]'::jsonb) from catalogue.providers p join ref.countries k on k.id = p.country_id));
end $function$
