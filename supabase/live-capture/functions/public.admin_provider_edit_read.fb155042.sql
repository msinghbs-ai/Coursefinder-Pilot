CREATE OR REPLACE FUNCTION public.admin_provider_edit_read(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  if not exists (select 1 from catalogue.providers where id = p_provider_id) then raise exception 'provider not found'; end if;
  return (select jsonb_build_object(
    'provider', jsonb_build_object('id', p.id, 'canonical_name', p.canonical_name, 'display_name', p.display_name, 'short_name', p.short_name,
               'website', p.website, 'phone', p.phone, 'email', p.email, 'description', p.description, 'primary_city', p.primary_city,
               'address_line1', p.address_line1, 'postcode', p.postcode, 'lifecycle_status', p.lifecycle_status, 'country', k.name, 'state', s.name,
               'manual_provider', p.stable_key like 'manual:%',
               'active_courses', (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')),
    'course_finder', (select jsonb_build_object('address', d.website, 'status', d.status, 'pages_found', d.kept_count, 'mapped_at', d.mapped_at)
                        from pipeline.coverage_provider_discovery d where d.provider_id = p.id),
    'link_recipe', (select jsonb_build_object('search_domain', r.search_domain, 'patterns', r.patterns, 'active', r.active)
                      from pipeline.course_link_recipes r where r.provider_id = p.id),
    'locks', (select coalesce(jsonb_object_agg(l.field, jsonb_build_object('mode', l.mode, 'at', l.set_at)), '{}'::jsonb)
               from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('at', h.at, 'field', h.field, 'action', h.action, 'before', h.before, 'after', h.after,
               'reason', h.reason, 'by', u.email) order by h.at desc), '[]'::jsonb)
               from (select * from pipeline.manual_edit_log where entity = 'provider' and entity_id = p.id order by at desc limit 20) h left join auth.users u on u.id = h.actor),
    'can_edit', v_rank >= 3, 'can_manage', v_rank >= 5)
   from catalogue.providers p left join ref.countries k on k.id = p.country_id left join ref.subdivisions s on s.id = p.subdivision_id where p.id = p_provider_id);
end $function$
