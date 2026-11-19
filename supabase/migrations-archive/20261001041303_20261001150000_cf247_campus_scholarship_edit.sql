-- CF-247 package 6 (screen review cmp-readonly, sch-no-edit, cc-inline-edit; 1 Oct 2026): campuses and scholarships
-- can be corrected by hand, in the record and in the list, under the same rule as courses and providers (Decision 181):
-- a person's entry always wins.
-- 1. pipeline.manual_locks also accepts 'campus' and 'scholarship'.
-- 2. security.manual_column_guard() keeps a person's value on update for every writer at once (Layer 1 sync,
--    scholarship readers and publishers), exactly like security.manual_field_guard() does for courses and providers.
--    Only the edit functions below set cf.manual_edit, which lets a change through. New rows are not affected.
-- 3. public.admin_campus_edit / admin_scholarship_edit (Curator and above) set or release a field; every change is
--    written to pipeline.manual_edit_log. public.admin_campus_create (PIM Operator and above) adds a campus for a provider.
-- 4. public.admin_catalogue_edit_rows also serves the campus and scholarship lists (guarded on the body applied by
--    20261001140000).

do $guard$
declare v text;
begin
  select md5(p.prosrc) into v from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_catalogue_edit_rows';
  if v is distinct from '116a2708a1d1c91465a8c0a22fcfeafa' then
    raise exception 'admin_catalogue_edit_rows changed since 20261001140000 (md5 %); not replacing', v;
  end if;
end $guard$;

alter table pipeline.manual_locks drop constraint manual_locks_entity_check;
alter table pipeline.manual_locks add constraint manual_locks_entity_check check (entity in ('course','provider','campus','scholarship'));

create or replace function security.manual_column_guard() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_new jsonb; v_old jsonb; f text; v_entity text := TG_ARGV[0];
begin
  if coalesce(current_setting('cf.manual_edit', true), '') = 'on' then return NEW; end if;
  if not exists (select 1 from pipeline.manual_locks l where l.entity = v_entity and l.entity_id = OLD.id) then return NEW; end if;
  v_new := to_jsonb(NEW); v_old := to_jsonb(OLD);
  for f in select l.field from pipeline.manual_locks l where l.entity = v_entity and l.entity_id = OLD.id loop
    if v_old ? f then v_new := jsonb_set(v_new, array[f], v_old->f); end if;
  end loop;
  NEW := jsonb_populate_record(NEW, v_new);
  return NEW;
end $$;
revoke all on function security.manual_column_guard() from public, anon, authenticated;

drop trigger if exists manual_lock_guard on catalogue.campuses;
create trigger manual_lock_guard before update on catalogue.campuses for each row execute function security.manual_column_guard('campus');
drop trigger if exists manual_lock_guard on scholarship.scholarships;
create trigger manual_lock_guard before update on scholarship.scholarships for each row execute function security.manual_column_guard('scholarship');

-- Campus
create or replace function public.admin_campus_edit(p_campus_id uuid, p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_rank int := security.current_role_rank(); v_c catalogue.campuses%rowtype; v_field text := p_args->>'field';
        v_val jsonb := p_args->'value'; v_before jsonb; v_after jsonb; v_src uuid;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into v_c from catalogue.campuses where id = p_campus_id;
  if v_c.id is null then raise exception 'campus not found'; end if;
  perform set_config('cf.manual_edit', 'on', true);
  if p_action = 'set_core' then
    if v_field is null or v_field not in ('name','address_line1','address_line2','city','postcode','phone','website') then raise exception 'this field cannot be edited here'; end if;
    if jsonb_typeof(v_val) = 'string' then v_val := to_jsonb(nullif(btrim(v_val #>> '{}'), '')); end if;
    if v_field = 'name' and (v_val is null or v_val = 'null'::jsonb) then raise exception 'a campus needs a name'; end if;
    if v_field = 'website' and v_val is not null and v_val <> 'null'::jsonb and (v_val #>> '{}') !~* '^https?://[^[:space:]]+\.[^[:space:]]+$' then raise exception 'enter the full address, starting with https://'; end if;
    v_before := to_jsonb(v_c)->v_field;
    select id into v_src from pipeline.sources where source_type = 'manual_entry' limit 1;
    update catalogue.campuses c set name = r.name, address_line1 = r.address_line1, address_line2 = r.address_line2, city = r.city,
           postcode = r.postcode, phone = r.phone, website = r.website, updated_at = now()
      from (select (jsonb_populate_record(x0, jsonb_build_object(v_field, v_val))).* from catalogue.campuses x0 where x0.id = p_campus_id) r
     where c.id = p_campus_id;
    perform security.manual_lock_set('campus', p_campus_id, v_field, 'value');
    v_after := v_val;
  elsif p_action = 'release' then
    select to_jsonb(l) into v_before from pipeline.manual_locks l where entity = 'campus' and entity_id = p_campus_id and field = v_field;
    if v_before is null then raise exception 'nothing to release'; end if;
    delete from pipeline.manual_locks where entity = 'campus' and entity_id = p_campus_id and field = v_field;
  else
    raise exception 'unknown action %', p_action;
  end if;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('campus', p_campus_id, v_field, p_action, v_before, v_after, nullif(btrim(coalesce(p_args->>'reason','')),''), auth.uid());
  return (select to_jsonb(c) - 'latitude' - 'longitude' || jsonb_build_object('locks',
            (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'campus' and k.entity_id = c.id))
            from catalogue.campuses c where c.id = p_campus_id);
end $$;
revoke all on function public.admin_campus_edit(uuid, text, jsonb) from public, anon;
grant execute on function public.admin_campus_edit(uuid, text, jsonb) to authenticated;

create or replace function public.admin_campus_create(p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_rank int := security.current_role_rank(); v_p catalogue.providers%rowtype; v_id uuid; v_src uuid;
        v_name text := nullif(btrim(coalesce(p_args->>'name','')),'');
begin
  if auth.uid() is null or v_rank < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  select * into v_p from catalogue.providers where id = nullif(p_args->>'provider_id','')::uuid;
  if v_p.id is null then raise exception 'choose the university this campus belongs to'; end if;
  if v_name is null then raise exception 'a campus needs a name'; end if;
  if exists (select 1 from catalogue.campuses where provider_id = v_p.id and lower(name) = lower(v_name) and status = 'active') then raise exception 'this university already has a campus with that name'; end if;
  perform set_config('cf.manual_edit', 'on', true);
  select id into v_src from pipeline.sources where source_type = 'manual_entry' limit 1;
  insert into catalogue.campuses(stable_key, provider_id, name, country_id, subdivision_id, city, address_line1, postcode, status, source_id)
  values ('manual:campus:' || extensions.gen_random_uuid(), v_p.id, v_name, v_p.country_id, v_p.subdivision_id,
          nullif(btrim(coalesce(p_args->>'city','')),''), nullif(btrim(coalesce(p_args->>'address_line1','')),''),
          nullif(btrim(coalesce(p_args->>'postcode','')),''), 'active', v_src)
  returning id into v_id;
  perform security.manual_lock_set('campus', v_id, 'name', 'value');
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('campus', v_id, null, 'create', null, p_args, nullif(btrim(coalesce(p_args->>'reason','')),''), auth.uid());
  return jsonb_build_object('id', v_id);
end $$;
revoke all on function public.admin_campus_create(jsonb) from public, anon;
grant execute on function public.admin_campus_create(jsonb) to authenticated;

-- Scholarship
create or replace function public.admin_scholarship_edit(p_scholarship_id uuid, p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_rank int := security.current_role_rank(); v_s scholarship.scholarships%rowtype; v_field text := p_args->>'field';
        v_val jsonb := p_args->'value'; v_txt text; v_before jsonb; v_after jsonb; v_locks text[];
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into v_s from scholarship.scholarships where id = p_scholarship_id;
  if v_s.id is null then raise exception 'scholarship not found'; end if;
  perform set_config('cf.manual_edit', 'on', true);
  if p_action = 'set_core' then
    if v_field is null or v_field not in ('name','description','award_value_text','award_amount','award_percentage','application_open_date','application_close_date','source_url') then
      raise exception 'this field cannot be edited here'; end if;
    if jsonb_typeof(v_val) = 'string' then v_val := to_jsonb(nullif(btrim(v_val #>> '{}'), '')); end if;
    v_txt := case when v_val is null or v_val = 'null'::jsonb then null else v_val #>> '{}' end;
    if v_field = 'name' and v_txt is null then raise exception 'a scholarship needs a name'; end if;
    if v_field = 'award_amount' and v_txt is not null and (v_txt !~ '^[0-9]+(\.[0-9]+)?$' or v_txt::numeric <= 0) then raise exception 'enter the award as a number, for example 5000'; end if;
    if v_field = 'award_percentage' and v_txt is not null and (v_txt !~ '^[0-9]+(\.[0-9]+)?$' or v_txt::numeric <= 0 or v_txt::numeric > 100) then raise exception 'enter a percentage between 1 and 100'; end if;
    if v_field in ('application_open_date','application_close_date') and v_txt is not null and v_txt !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'enter the date as dd/mm/yyyy'; end if;
    if v_field = 'source_url' and v_txt is not null and v_txt !~* '^https?://[^[:space:]]+\.[^[:space:]]+$' then raise exception 'enter the full address, starting with https://'; end if;
    v_before := to_jsonb(v_s)->v_field;
    if v_field = 'award_amount' then
      update scholarship.scholarships set award_amount = v_txt::numeric,
             award_value_type = case when v_txt is not null then 'fixed_amount' when award_percentage is not null then 'percentage' else award_value_type end,
             award_percentage = case when v_txt is not null then null else award_percentage end,
             award_currency_code = case when v_txt is not null then coalesce(award_currency_code, 'AUD') else award_currency_code end, updated_at = now()
       where id = p_scholarship_id;
      v_locks := array['award_amount','award_percentage','award_value_type','award_currency_code'];
    elsif v_field = 'award_percentage' then
      update scholarship.scholarships set award_percentage = v_txt::numeric,
             award_value_type = case when v_txt is not null then 'percentage' when award_amount is not null then 'fixed_amount' else award_value_type end,
             award_amount = case when v_txt is not null then null else award_amount end, updated_at = now()
       where id = p_scholarship_id;
      v_locks := array['award_amount','award_percentage','award_value_type'];
    else
      update scholarship.scholarships s set name = r.name, description = r.description, award_value_text = r.award_value_text,
             application_open_date = r.application_open_date, application_close_date = r.application_close_date, source_url = r.source_url, updated_at = now()
        from (select (jsonb_populate_record(x0, jsonb_build_object(v_field, v_val))).* from scholarship.scholarships x0 where x0.id = p_scholarship_id) r
       where s.id = p_scholarship_id;
      v_locks := array[v_field];
    end if;
    perform security.manual_lock_set('scholarship', p_scholarship_id, f, 'value') from unnest(v_locks) f;
    v_after := v_val;
  elsif p_action = 'release' then
    select to_jsonb(l) into v_before from pipeline.manual_locks l where entity = 'scholarship' and entity_id = p_scholarship_id and field = v_field;
    if v_before is null then raise exception 'nothing to release'; end if;
    delete from pipeline.manual_locks where entity = 'scholarship' and entity_id = p_scholarship_id
       and (field = v_field or (v_field in ('award_amount','award_percentage') and field in ('award_amount','award_percentage','award_value_type','award_currency_code')));
  else
    raise exception 'unknown action %', p_action;
  end if;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('scholarship', p_scholarship_id, v_field, p_action, v_before, v_after, nullif(btrim(coalesce(p_args->>'reason','')),''), auth.uid());
  return (select jsonb_build_object('id', s.id, 'name', s.name, 'award_value_text', s.award_value_text, 'award_amount', s.award_amount,
            'award_percentage', s.award_percentage, 'application_open_date', s.application_open_date, 'application_close_date', s.application_close_date,
            'source_url', s.source_url, 'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id))
            from scholarship.scholarships s where s.id = p_scholarship_id);
end $$;
revoke all on function public.admin_scholarship_edit(uuid, text, jsonb) from public, anon;
grant execute on function public.admin_scholarship_edit(uuid, text, jsonb) to authenticated;

-- List read: courses and providers unchanged from 20261001140000; campuses and scholarships added.
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
  elsif p_type = 'campus' then
    return jsonb_build_object('can_edit', v_rank >= 3, 'rows', (select coalesce(jsonb_object_agg(c.id, jsonb_build_object(
        'name', c.name, 'address_line1', c.address_line1, 'city', c.city, 'postcode', c.postcode, 'phone', c.phone, 'website', c.website,
        'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'campus' and k.entity_id = c.id))), '{}'::jsonb)
      from catalogue.campuses c where c.id = any(p_ids)));
  elsif p_type = 'scholarship' then
    return jsonb_build_object('can_edit', v_rank >= 3, 'rows', (select coalesce(jsonb_object_agg(s.id, jsonb_build_object(
        'name', s.name, 'award_value_text', s.award_value_text, 'award_amount', s.award_amount, 'award_percentage', s.award_percentage,
        'application_open_date', s.application_open_date, 'application_close_date', s.application_close_date, 'source_url', s.source_url,
        'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id))), '{}'::jsonb)
      from scholarship.scholarships s where s.id = any(p_ids)));
  end if;
  raise exception 'unknown list %', p_type;
end $$;
revoke all on function public.admin_catalogue_edit_rows(text, uuid[]) from public, anon;
grant execute on function public.admin_catalogue_edit_rows(text, uuid[]) to authenticated;
