-- CF-247 package 6 (screen review crs-listedit-fields, 1 Oct 2026): Edit in list for Courses also covers the values
-- operators most often fix by hand: tuition (amount, year, basis), intakes and English test scores.
-- The list read returns them with their manual locks and the active English tests. Saving keeps using the existing
-- per-field edits in public.admin_course_edit (set_tuition / set_intakes / set_english and their remove_ actions), so
-- every change stays role-checked, logged and locked against automation exactly as in the course drawer.
-- Intakes carry start_date and English carries component scores so that a list edit can send them back unchanged.
-- Guard: replaces public.admin_catalogue_edit_rows only if its live body is the one from 20260930180000.

do $guard$
declare v text;
begin
  select md5(p.prosrc) into v from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_catalogue_edit_rows';
  if v is distinct from 'dca6b9564c88f13482ba11ed56a54952' then
    raise exception 'admin_catalogue_edit_rows changed since 20260930180000 (md5 %); not replacing', v;
  end if;
end $guard$;

create or replace function public.admin_catalogue_edit_rows(p_type text, p_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  if coalesce(array_length(p_ids, 1), 0) > 100 then raise exception 'at most 100 rows at a time'; end if;
  if p_type = 'course' then
    return jsonb_build_object('can_edit', v_rank >= 3,
      'english_tests', (select coalesce(jsonb_agg(jsonb_build_object('code', t.code, 'name', t.name) order by t.code), '[]'::jsonb)
                          from ref.english_tests t where t.status = 'active'),
      'rows', (select coalesce(jsonb_object_agg(c.id, jsonb_build_object(
        'display_title', coalesce(c.display_title, c.canonical_title),
        'duration_value', c.duration_value, 'duration_unit', c.duration_unit, 'delivery_mode', c.delivery_mode,
        'official_url', coalesce((select l.url from catalogue.course_links l where l.course_id = c.id and l.link_type = 'official_course'
                                    and l.status = 'active' order by l.is_primary desc, l.updated_at desc limit 1), c.course_url),
        'tuition', (select jsonb_build_object('amount', f.amount, 'fee_year', f.fee_year, 'basis', f.basis, 'currency', f.currency_code)
                      from catalogue.course_fees f where f.course_id = c.id and f.fee_type = 'provider_current_tuition' and f.status = 'active'
                     order by f.fee_year desc nulls last, f.updated_at desc limit 1),
        'intakes', (select coalesce(jsonb_agg(jsonb_build_object('label', i.intake_label, 'year', i.intake_year, 'start_date', i.start_date)
                                     order by i.intake_year nulls last, i.start_date nulls last, i.intake_label), '[]'::jsonb)
                      from catalogue.course_intakes i where i.course_id = c.id and i.status = 'active'),
        'english', (select coalesce(jsonb_agg(jsonb_build_object('test', t.code, 'overall', e.overall_score, 'components', e.component_scores)
                                     order by t.code), '[]'::jsonb)
                      from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id
                     where e.course_id = c.id and e.status = 'active'),
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
