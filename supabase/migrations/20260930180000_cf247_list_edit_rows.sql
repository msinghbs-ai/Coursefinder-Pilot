-- CF-247 Edit in the list (Platform Admin, 1 Oct 2026: "For UI crud, can this be modernise and have inline edit on
-- existing fields? Or better edit in list view on visible columns?").
-- Courses and Providers lists get an "Edit in list" mode: the editable fields become columns and are changed in place.
-- This read returns, for the rows on the current page, the current value of each editable field and whether it was
-- entered by hand (manual lock). Saving uses the existing per-field edits (admin_course_edit / admin_provider_edit),
-- so every change is role-checked, logged in manual_edit_log and locked against automation exactly as in the drawer.

create or replace function public.admin_catalogue_edit_rows(p_type text, p_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  if coalesce(array_length(p_ids, 1), 0) > 100 then raise exception 'at most 100 rows at a time'; end if;
  if p_type = 'course' then
    return jsonb_build_object('can_edit', v_rank >= 3, 'rows', (select coalesce(jsonb_object_agg(c.id, jsonb_build_object(
        'display_title', coalesce(c.display_title, c.canonical_title),
        'duration_value', c.duration_value, 'duration_unit', c.duration_unit, 'delivery_mode', c.delivery_mode,
        'official_url', coalesce((select l.url from catalogue.course_links l where l.course_id = c.id and l.link_type = 'official_course'
                                    and l.status = 'active' order by l.is_primary desc, l.updated_at desc limit 1), c.course_url),
        'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id))), '{}'::jsonb)
      from catalogue.courses c where c.id = any(p_ids)));
  elsif p_type = 'provider' then
    return jsonb_build_object('can_edit', v_rank >= 3, 'rows', (select coalesce(jsonb_object_agg(p.id, jsonb_build_object(
        'display_name', coalesce(p.display_name, p.canonical_name), 'primary_city', p.primary_city, 'website', p.website,
        'phone', p.phone, 'email', p.email,
        'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'provider' and k.entity_id = p.id))), '{}'::jsonb)
      from catalogue.providers p where p.id = any(p_ids)));
  end if;
  raise exception 'unknown list %', p_type;
end $$;
revoke all on function public.admin_catalogue_edit_rows(text, uuid[]) from public, anon;
grant execute on function public.admin_catalogue_edit_rows(text, uuid[]) to authenticated;