-- CF-247 CRUD, manual data first (Decision 179, build step 1; Platform Admin 30 Sep 2026: "Crud functionality required at
-- each level ... majority of data will or foundational data will be handled manually").
--
-- 1. A person's entry always wins. pipeline.manual_locks records, per course or provider field, that a person set the
--    value ('value') or removed it ('removed'). Two guard triggers enforce it for every writer at once (the 13 functions
--    that write course facts, Layer 1 sync, provider rules, Layer 3 and Layer 4), without editing each writer:
--      - course facts (official page, intakes, English, current provider tuition): automated inserts, updates and
--        deletes for a locked course field are skipped;
--      - course and provider columns (title, description, duration, delivery, lifecycle, official address, website,
--        contact details): automated updates keep the person's value.
--    Only the admin edit functions below set cf.manual_edit, which lets a change through. "Release to automation" removes
--    the lock. Layer 4 approvals do not lock (they confirm automated values and stay open to yearly refresh).
-- 2. Manual values are stored with source "Manual entry (platform operators)", confidence 1, and every change is
--    written to pipeline.manual_edit_log (who, when, field, before, after, reason).
-- 3. Admin functions (Curator and above edit facts; PIM Operator and above add, archive and restore courses and
--    providers):
--      public.admin_course_edit_read(course), public.admin_course_edit(course, action, args), public.admin_course_create(args)
--      public.admin_provider_edit_read(provider), public.admin_provider_edit(provider, action, args), public.admin_provider_create(args)
--    Setting or removing a value closes that course's open Layer 4 items for the same field as superseded.
-- 4. A hand-entered official page is read by the page reader like any other, and is trusted as the course's page (no
--    CRICOS/title check); the site-map matcher and the link search leave it alone. Changing a provider's course finder
--    address sends the provider back to page discovery.

insert into pipeline.sources(source_type, system_id, label, trust_rank, status, metadata)
select 'manual_entry', s.system_id, 'Manual entry (platform operators)', 100, 'active',
       jsonb_build_object('decision','Decision 179','note','Values typed in by a person on the course or provider page; automation does not overwrite them')
  from (select system_id from pipeline.sources where source_type='layer4_human_review' limit 1) s
 where not exists (select 1 from pipeline.sources where source_type='manual_entry');

create table if not exists pipeline.manual_locks (
  entity text not null check (entity in ('course','provider')),
  entity_id uuid not null,
  field text not null,
  mode text not null check (mode in ('value','removed')),
  set_by uuid, set_at timestamptz not null default now(),
  primary key (entity, entity_id, field));
alter table pipeline.manual_locks enable row level security;
revoke all on pipeline.manual_locks from public, anon, authenticated;

create table if not exists pipeline.manual_edit_log (
  id bigint generated always as identity primary key,
  entity text not null, entity_id uuid not null, field text, action text not null,
  before jsonb, after jsonb, reason text, actor uuid, at timestamptz not null default now());
create index if not exists manual_edit_log_entity_idx on pipeline.manual_edit_log(entity, entity_id, at desc);
alter table pipeline.manual_edit_log enable row level security;
revoke all on pipeline.manual_edit_log from public, anon, authenticated;

-- Guard: course facts
create or replace function security.manual_fact_guard() returns trigger language plpgsql security definer set search_path = '' as $$
declare r jsonb; v_field text;
begin
  if coalesce(current_setting('cf.manual_edit', true), '') = 'on' then
    if TG_OP = 'DELETE' then return OLD; end if; return NEW;
  end if;
  if TG_OP = 'DELETE' then r := to_jsonb(OLD); else r := to_jsonb(NEW); end if;
  v_field := case TG_TABLE_NAME
               when 'course_links' then case when r->>'link_type' = 'official_course' then 'official_url' end
               when 'course_intakes' then 'intakes'
               when 'course_english_requirements' then 'english'
               when 'course_fees' then case when r->>'fee_type' = 'provider_current_tuition' then 'tuition' end end;
  if v_field is not null and exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = (r->>'course_id')::uuid and l.field = v_field) then
    return null;
  end if;
  if TG_OP = 'DELETE' then return OLD; end if;
  return NEW;
end $$;
revoke all on function security.manual_fact_guard() from public, anon, authenticated;

drop trigger if exists manual_lock_guard on catalogue.course_links;
create trigger manual_lock_guard before insert or update or delete on catalogue.course_links for each row execute function security.manual_fact_guard();
drop trigger if exists manual_lock_guard on catalogue.course_intakes;
create trigger manual_lock_guard before insert or update or delete on catalogue.course_intakes for each row execute function security.manual_fact_guard();
drop trigger if exists manual_lock_guard on catalogue.course_english_requirements;
create trigger manual_lock_guard before insert or update or delete on catalogue.course_english_requirements for each row execute function security.manual_fact_guard();
drop trigger if exists manual_lock_guard on catalogue.course_fees;
create trigger manual_lock_guard before insert or update or delete on catalogue.course_fees for each row execute function security.manual_fact_guard();

-- Guard: course and provider columns
create or replace function security.manual_field_guard() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_new jsonb; v_old jsonb; f text; v_entity text := case TG_TABLE_NAME when 'courses' then 'course' else 'provider' end;
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
revoke all on function security.manual_field_guard() from public, anon, authenticated;

drop trigger if exists manual_lock_guard on catalogue.courses;
create trigger manual_lock_guard before update on catalogue.courses for each row execute function security.manual_field_guard();
drop trigger if exists manual_lock_guard on catalogue.providers;
create trigger manual_lock_guard before update on catalogue.providers for each row execute function security.manual_field_guard();

-- Helpers
create or replace function security.manual_lock_set(p_entity text, p_id uuid, p_field text, p_mode text) returns void
language sql security definer set search_path = '' as $$
  insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by) values (p_entity, p_id, p_field, p_mode, auth.uid())
  on conflict (entity, entity_id, field) do update set mode = excluded.mode, set_by = excluded.set_by, set_at = now();
$$;
revoke all on function security.manual_lock_set(text, uuid, text, text) from public, anon, authenticated;

create or replace function security.manual_close_layer4(p_course_id uuid, p_field text) returns int
language plpgsql security definer set search_path = '' as $$
declare v int;
begin
  update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
         escalation_reason = 'Superseded: value entered by hand on the course page'
   where entity_type = 'course' and entity_id = p_course_id and status in ('pending','returned_layer3')
     and field_code = case p_field when 'official_url' then 'official_course_url' when 'intakes' then 'course_intake'
                                   when 'english' then 'course_english' when 'tuition' then 'provider_current_tuition_validation' end;
  get diagnostics v = row_count;
  return v;
end $$;
revoke all on function security.manual_close_layer4(uuid, text) from public, anon, authenticated;

-- Read
create or replace function public.admin_course_edit_read(p_course_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  if not exists (select 1 from catalogue.courses where id = p_course_id) then raise exception 'course not found'; end if;
  return (select jsonb_build_object(
    'course', jsonb_build_object('id', c.id, 'provider_id', c.provider_id, 'provider', coalesce(p.display_name, p.canonical_name), 'course_code', c.course_code,
               'canonical_title', c.canonical_title, 'display_title', c.display_title, 'description', c.description, 'duration_value', c.duration_value,
               'duration_unit', c.duration_unit, 'delivery_mode', c.delivery_mode, 'lifecycle_status', c.lifecycle_status, 'course_url', c.course_url,
               'manual_course', c.stable_key like 'manual:%'),
    'official_links', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'url', l.url, 'is_primary', l.is_primary, 'source', s.label,
               'manual', s.source_type = 'manual_entry', 'updated_at', l.updated_at) order by l.is_primary desc, l.updated_at desc), '[]'::jsonb)
               from catalogue.course_links l left join pipeline.sources s on s.id = l.source_id
              where l.course_id = c.id and l.link_type = 'official_course' and l.status = 'active'),
    'intakes', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'label', i.intake_label, 'year', i.intake_year, 'start_date', i.start_date,
               'source', s.label, 'manual', s.source_type = 'manual_entry') order by i.start_date nulls last, i.intake_label), '[]'::jsonb)
               from catalogue.course_intakes i left join pipeline.sources s on s.id = i.source_id where i.course_id = c.id and i.status = 'active'),
    'english', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'test', t.code, 'test_name', t.name, 'overall', e.overall_score,
               'components', e.component_scores, 'source', s.label, 'manual', s.source_type = 'manual_entry') order by t.name), '[]'::jsonb)
               from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id left join pipeline.sources s on s.id = e.source_id
              where e.course_id = c.id and e.status = 'active'),
    'tuition', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'amount', f.amount, 'currency', f.currency_code, 'fee_year', f.fee_year,
               'basis', f.basis, 'source', s.label, 'manual', s.source_type = 'manual_entry') order by f.updated_at desc), '[]'::jsonb)
               from catalogue.course_fees f left join pipeline.sources s on s.id = f.source_id
              where f.course_id = c.id and f.fee_type = 'provider_current_tuition' and f.status = 'active'),
    'locks', (select coalesce(jsonb_object_agg(l.field, jsonb_build_object('mode', l.mode, 'at', l.set_at)), '{}'::jsonb)
               from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('at', h.at, 'field', h.field, 'action', h.action, 'before', h.before, 'after', h.after,
               'reason', h.reason, 'by', u.email) order by h.at desc), '[]'::jsonb)
               from (select * from pipeline.manual_edit_log where entity = 'course' and entity_id = c.id order by at desc limit 20) h left join auth.users u on u.id = h.actor),
    'english_tests', (select jsonb_agg(jsonb_build_object('code', code, 'name', name) order by name) from ref.english_tests),
    'can_edit', v_rank >= 3, 'can_manage', v_rank >= 5)
   from catalogue.courses c left join catalogue.providers p on p.id = c.provider_id where c.id = p_course_id);
end $$;
revoke all on function public.admin_course_edit_read(uuid) from public, anon;
grant execute on function public.admin_course_edit_read(uuid) to authenticated;

-- Edit
create or replace function public.admin_course_edit(p_course_id uuid, p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_rank int := security.current_role_rank(); v_src uuid; v_c catalogue.courses%rowtype; v_field text; v_before jsonb; v_after jsonb;
        v_reason text := nullif(btrim(coalesce(p_args->>'reason', '')), ''); v_url text; x jsonb; v_test uuid; v_amount numeric; v_val jsonb;
        v_keep uuid[] := '{}'; v_n int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into v_c from catalogue.courses where id = p_course_id;
  if v_c.id is null then raise exception 'course not found'; end if;
  if p_action in ('archive','restore') and v_rank < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  perform set_config('cf.manual_edit', 'on', true);
  select id into v_src from pipeline.sources where source_type = 'manual_entry' limit 1;

  if p_action = 'set_core' then
    v_field := p_args->>'field';
    if v_field is null or v_field not in ('display_title','description','duration_value','duration_unit','delivery_mode') then raise exception 'this field cannot be edited here'; end if;
    v_val := p_args->'value';
    if jsonb_typeof(v_val) = 'string' then v_val := to_jsonb(nullif(btrim(v_val #>> '{}'), '')); end if;
    if v_field = 'duration_value' and v_val is not null and v_val <> 'null'::jsonb and not ((v_val #>> '{}') ~ '^[0-9]+(\.[0-9]+)?$') then raise exception 'duration must be a number'; end if;
    v_before := to_jsonb(v_c)->v_field;
    update catalogue.courses c set display_title = r.display_title, description = r.description, duration_value = r.duration_value,
           duration_unit = r.duration_unit, delivery_mode = r.delivery_mode, updated_at = now()
      from (select (jsonb_populate_record(x0, jsonb_build_object(v_field, v_val))).* from catalogue.courses x0 where x0.id = p_course_id) r
     where c.id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, v_field, 'value');
    v_after := v_val;

  elsif p_action = 'set_official_url' then
    v_field := 'official_url'; v_url := btrim(coalesce(p_args->>'url', ''));
    if v_url !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    select jsonb_agg(url) into v_before from catalogue.course_links where course_id = p_course_id and link_type = 'official_course' and status = 'active';
    update catalogue.course_links set status = 'inactive', is_primary = false, updated_at = now()
     where course_id = p_course_id and link_type = 'official_course' and status = 'active' and url <> v_url;
    insert into catalogue.course_links(course_id, link_type, url, label, is_primary, status, source_id, confidence, last_verified_at)
    values (p_course_id, 'official_course', v_url, 'Official course page', true, 'active', v_src, 1, now())
    on conflict (course_id, link_type, url) do update set status = 'active', is_primary = true, source_id = v_src, confidence = 1,
           last_verified_at = now(), updated_at = now(), evidence_id = null;
    update catalogue.courses set course_url = v_url, updated_at = now() where id = p_course_id;
    insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, bound_at, next_read_at, read_attempts)
    values (p_course_id, v_c.provider_id, v_url, 'manual', 'bound', now(), now(), 0)
    on conflict (course_id) do update set url = excluded.url, basis = 'manual', status = 'bound', bound_at = now(), score = null, runner_up = null,
           read_status = null, read_at = null, http_status = null, fetched_via = null, identity_basis = null, evidence_id = null, candidates = null,
           leased_until = null, read_attempts = 0, next_read_at = now();
    update pipeline.course_link_search set state = 'verified', bound_url = v_url, done_at = now() where course_id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, 'official_url', 'value');
    perform security.manual_lock_set('course', p_course_id, 'course_url', 'value');
    v_after := to_jsonb(v_url);

  elsif p_action = 'remove_official_url' then
    v_field := 'official_url';
    select jsonb_agg(url) into v_before from catalogue.course_links where course_id = p_course_id and link_type = 'official_course' and status = 'active';
    update catalogue.course_links set status = 'inactive', is_primary = false, updated_at = now()
     where course_id = p_course_id and link_type = 'official_course' and status = 'active';
    update catalogue.courses set course_url = null, updated_at = now() where id = p_course_id;
    update pipeline.coverage_course_pages set status = 'mismatch', basis = 'manual', leased_until = null where course_id = p_course_id;
    delete from pipeline.course_link_search where course_id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, 'official_url', 'removed');
    perform security.manual_lock_set('course', p_course_id, 'course_url', 'removed');

  elsif p_action = 'set_intakes' then
    v_field := 'intakes';
    if jsonb_typeof(p_args->'intakes') <> 'array' or jsonb_array_length(p_args->'intakes') = 0 then raise exception 'add at least one intake'; end if;
    select jsonb_agg(jsonb_build_object('label', intake_label, 'year', intake_year, 'start_date', start_date)) into v_before
      from catalogue.course_intakes where course_id = p_course_id and status = 'active';
    update catalogue.course_intakes set status = 'inactive' where course_id = p_course_id and status = 'active';
    for x in select * from jsonb_array_elements(p_args->'intakes') loop
      if nullif(btrim(coalesce(x->>'label', '')), '') is null then raise exception 'each intake needs a name, for example February'; end if;
      insert into catalogue.course_intakes(course_id, intake_year, intake_label, start_date, status, source_id, confidence, source_intake_key)
      values (p_course_id, nullif(x->>'year', '')::int, btrim(x->>'label'), nullif(x->>'start_date', '')::date, 'active', v_src, 1,
              'manual:' || lower(btrim(x->>'label')) || ':' || coalesce(nullif(x->>'year', ''), '') || ':' || coalesce(nullif(x->>'start_date', ''), ''))
      on conflict (course_id, source_id, source_intake_key) where source_id is not null and source_intake_key is not null
      do update set status = 'active', intake_year = excluded.intake_year, start_date = excluded.start_date, confidence = 1;
    end loop;
    perform security.manual_lock_set('course', p_course_id, 'intakes', 'value');
    v_after := p_args->'intakes';

  elsif p_action = 'remove_intakes' then
    v_field := 'intakes';
    select jsonb_agg(jsonb_build_object('label', intake_label, 'year', intake_year)) into v_before from catalogue.course_intakes where course_id = p_course_id and status = 'active';
    update catalogue.course_intakes set status = 'inactive' where course_id = p_course_id and status = 'active';
    perform security.manual_lock_set('course', p_course_id, 'intakes', 'removed');

  elsif p_action = 'set_english' then
    v_field := 'english';
    if jsonb_typeof(p_args->'tests') <> 'array' or jsonb_array_length(p_args->'tests') = 0 then raise exception 'add at least one English test score'; end if;
    select jsonb_agg(jsonb_build_object('test', t.code, 'overall', e.overall_score, 'components', e.component_scores)) into v_before
      from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id where e.course_id = p_course_id and e.status = 'active';
    for x in select * from jsonb_array_elements(p_args->'tests') loop
      select id into v_test from ref.english_tests where code = x->>'test';
      if v_test is null then raise exception 'unknown English test %', x->>'test'; end if;
      if (x->>'overall') is null or (x->>'overall') !~ '^[0-9]+(\.[0-9]+)?$' then raise exception 'enter an overall score for %', x->>'test'; end if;
      insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, notes, source_id, evidence_id, confidence, source_requirement_key, status, last_verified_at)
      values (p_course_id, v_test, (x->>'overall')::numeric, coalesce(x->'components', '{}'::jsonb), 'Manual entry', v_src, null, 1, 'manual:' || lower(x->>'test'), 'active', now())
      on conflict (course_id, english_test_id) do update set overall_score = excluded.overall_score, component_scores = excluded.component_scores,
             notes = 'Manual entry', source_id = v_src, evidence_id = null, confidence = 1, source_requirement_key = excluded.source_requirement_key,
             status = 'active', last_verified_at = now();
      v_keep := v_keep || v_test;
    end loop;
    update catalogue.course_english_requirements set status = 'inactive' where course_id = p_course_id and status = 'active' and not (english_test_id = any(v_keep));
    perform security.manual_lock_set('course', p_course_id, 'english', 'value');
    v_after := p_args->'tests';

  elsif p_action = 'remove_english' then
    v_field := 'english';
    select jsonb_agg(jsonb_build_object('test', t.code, 'overall', e.overall_score)) into v_before
      from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id where e.course_id = p_course_id and e.status = 'active';
    update catalogue.course_english_requirements set status = 'inactive' where course_id = p_course_id and status = 'active';
    perform security.manual_lock_set('course', p_course_id, 'english', 'removed');

  elsif p_action = 'set_tuition' then
    v_field := 'tuition';
    if coalesce(p_args->>'amount', '') !~ '^[0-9]+(\.[0-9]+)?$' or (p_args->>'amount')::numeric < 100 then raise exception 'enter the fee as a number, for example 45000'; end if;
    if coalesce(p_args->>'basis', 'annual') not in ('annual','total_indicative','per_semester','per_trimester') then raise exception 'choose per year, per semester, per trimester or whole course'; end if;
    v_amount := (p_args->>'amount')::numeric;
    select jsonb_agg(jsonb_build_object('amount', amount, 'year', fee_year, 'basis', basis)) into v_before
      from catalogue.course_fees where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    update catalogue.course_fees set status = 'superseded', updated_at = now(),
           notes = coalesce(notes, '') || ' | superseded by a manual entry ' || to_char(now(), 'YYYY-MM-DD')
     where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    insert into catalogue.course_fees(course_id, fee_year, audience, fee_type, amount, currency_code, basis, notes, source_id, confidence, source_fee_key, status, last_verified_at)
    values (p_course_id, nullif(p_args->>'fee_year', '')::int, 'international', 'provider_current_tuition', v_amount, coalesce(nullif(p_args->>'currency', ''), 'AUD'),
            coalesce(p_args->>'basis', 'annual'), 'Manual entry', v_src, 1, 'manual:' || extract(epoch from clock_timestamp())::bigint, 'active', now());
    perform security.manual_lock_set('course', p_course_id, 'tuition', 'value');
    v_after := jsonb_build_object('amount', v_amount, 'year', nullif(p_args->>'fee_year', ''), 'basis', coalesce(p_args->>'basis', 'annual'), 'currency', coalesce(nullif(p_args->>'currency', ''), 'AUD'));

  elsif p_action = 'remove_tuition' then
    v_field := 'tuition';
    select jsonb_agg(jsonb_build_object('amount', amount, 'year', fee_year, 'basis', basis)) into v_before
      from catalogue.course_fees where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    update catalogue.course_fees set status = 'inactive', updated_at = now(), notes = coalesce(notes, '') || ' | removed by hand ' || to_char(now(), 'YYYY-MM-DD')
     where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    perform security.manual_lock_set('course', p_course_id, 'tuition', 'removed');

  elsif p_action = 'release' then
    v_field := p_args->>'field';
    select to_jsonb(l) into v_before from pipeline.manual_locks l where entity = 'course' and entity_id = p_course_id and field = v_field;
    if v_before is null then raise exception 'nothing to release'; end if;
    delete from pipeline.manual_locks where entity = 'course' and entity_id = p_course_id and (field = v_field or (v_field = 'official_url' and field = 'course_url'));
    if v_field = 'official_url' then
      update pipeline.coverage_course_pages set basis = 'released' where course_id = p_course_id and basis = 'manual';
    end if;

  elsif p_action in ('archive','restore') then
    v_field := 'lifecycle_status'; v_before := to_jsonb(v_c.lifecycle_status);
    update catalogue.courses set lifecycle_status = case p_action when 'archive' then 'inactive' else 'active' end, updated_at = now() where id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, 'lifecycle_status', 'value');
    v_after := to_jsonb(case p_action when 'archive' then 'inactive' else 'active' end);

  else
    raise exception 'unknown action %', p_action;
  end if;

  if v_field in ('official_url','intakes','english','tuition') and p_action <> 'release' then
    perform security.manual_close_layer4(p_course_id, v_field);
  end if;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('course', p_course_id, v_field, p_action, v_before, v_after, v_reason, auth.uid());
  perform search.refresh_course_enrichment_scoped_v1(array[p_course_id], true);
  return public.admin_course_edit_read(p_course_id);
end $$;
revoke all on function public.admin_course_edit(uuid, text, jsonb) from public, anon;
grant execute on function public.admin_course_edit(uuid, text, jsonb) to authenticated;

-- Create a course (PIM Operator and above)
create or replace function public.admin_course_create(p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := gen_random_uuid(); v_title text := nullif(btrim(coalesce(p_args->>'title', '')), ''); v_code text := upper(nullif(btrim(coalesce(p_args->>'course_code', '')), ''));
        v_pid uuid := nullif(p_args->>'provider_id', '')::uuid;
begin
  if auth.uid() is null or security.current_role_rank() < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  if v_pid is null or not exists (select 1 from catalogue.providers where id = v_pid) then raise exception 'choose the provider'; end if;
  if v_title is null then raise exception 'enter the course title'; end if;
  if v_code is not null and exists (select 1 from catalogue.courses where provider_id = v_pid and course_code = v_code and lifecycle_status = 'active') then
    raise exception 'this provider already has an active course with code %', v_code;
  end if;
  perform set_config('cf.manual_edit', 'on', true);
  insert into catalogue.courses(id, stable_key, provider_id, canonical_title, display_title, course_code, description, duration_value, duration_unit, delivery_mode, lifecycle_status)
  values (v_id, 'manual:' || v_id, v_pid, v_title, v_title, v_code, nullif(btrim(coalesce(p_args->>'description', '')), ''),
          nullif(p_args->>'duration_value', '')::numeric, nullif(p_args->>'duration_unit', ''), nullif(p_args->>'delivery_mode', ''), 'active');
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, after, reason, actor)
  values ('course', v_id, null, 'create', p_args, nullif(btrim(coalesce(p_args->>'reason', '')), ''), auth.uid());
  perform search.refresh_course_enrichment_scoped_v1(array[v_id], true);
  return public.admin_course_edit_read(v_id);
end $$;
revoke all on function public.admin_course_create(jsonb) from public, anon;
grant execute on function public.admin_course_create(jsonb) to authenticated;

-- Provider read
create or replace function public.admin_provider_edit_read(p_provider_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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
end $$;
revoke all on function public.admin_provider_edit_read(uuid) from public, anon;
grant execute on function public.admin_provider_edit_read(uuid) to authenticated;

-- Provider edit
create or replace function public.admin_provider_edit(p_provider_id uuid, p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_rank int := security.current_role_rank(); v_p catalogue.providers%rowtype; v_field text; v_before jsonb; v_after jsonb; v_val jsonb; v_url text;
        v_reason text := nullif(btrim(coalesce(p_args->>'reason', '')), '');
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into v_p from catalogue.providers where id = p_provider_id;
  if v_p.id is null then raise exception 'provider not found'; end if;
  if p_action in ('archive','restore') and v_rank < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  perform set_config('cf.manual_edit', 'on', true);

  if p_action = 'set_core' then
    v_field := p_args->>'field';
    if v_field is null or v_field not in ('display_name','short_name','website','phone','email','description','primary_city','address_line1','postcode') then raise exception 'this field cannot be edited here'; end if;
    v_val := p_args->'value';
    if jsonb_typeof(v_val) = 'string' then v_val := to_jsonb(nullif(btrim(v_val #>> '{}'), '')); end if;
    if v_field = 'website' and v_val is not null and v_val <> 'null'::jsonb and (v_val #>> '{}') !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    if v_field = 'email' and v_val is not null and v_val <> 'null'::jsonb and (v_val #>> '{}') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'enter a valid email address'; end if;
    v_before := to_jsonb(v_p)->v_field;
    update catalogue.providers p set display_name = r.display_name, short_name = r.short_name, website = r.website, phone = r.phone, email = r.email,
           description = r.description, primary_city = r.primary_city, address_line1 = r.address_line1, postcode = r.postcode, updated_at = now()
      from (select (jsonb_populate_record(x0, jsonb_build_object(v_field, v_val))).* from catalogue.providers x0 where x0.id = p_provider_id) r
     where p.id = p_provider_id;
    perform security.manual_lock_set('provider', p_provider_id, v_field, 'value');
    v_after := v_val;

  elsif p_action = 'set_course_finder' then
    v_field := 'course_finder'; v_url := btrim(coalesce(p_args->>'url', ''));
    if v_url !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    select to_jsonb(d.website) into v_before from pipeline.coverage_provider_discovery d where d.provider_id = p_provider_id;
    insert into pipeline.coverage_provider_discovery(provider_id, website, status, attempts, next_due_at, updated_at)
    values (p_provider_id, v_url, 'pending', 0, now(), now())
    on conflict (provider_id) do update set website = excluded.website, status = 'pending', attempts = 0, next_due_at = now(), leased_until = null,
           last_error = null, updated_at = now();
    v_after := to_jsonb(v_url);

  elsif p_action = 'release' then
    v_field := p_args->>'field';
    select to_jsonb(l) into v_before from pipeline.manual_locks l where entity = 'provider' and entity_id = p_provider_id and field = v_field;
    if v_before is null then raise exception 'nothing to release'; end if;
    delete from pipeline.manual_locks where entity = 'provider' and entity_id = p_provider_id and field = v_field;

  elsif p_action in ('archive','restore') then
    v_field := 'lifecycle_status'; v_before := to_jsonb(v_p.lifecycle_status);
    update catalogue.providers set lifecycle_status = case p_action when 'archive' then 'inactive' else 'active' end, updated_at = now() where id = p_provider_id;
    perform security.manual_lock_set('provider', p_provider_id, 'lifecycle_status', 'value');
    v_after := to_jsonb(case p_action when 'archive' then 'inactive' else 'active' end);

  else
    raise exception 'unknown action %', p_action;
  end if;

  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('provider', p_provider_id, v_field, p_action, v_before, v_after, v_reason, auth.uid());
  return public.admin_provider_edit_read(p_provider_id);
end $$;
revoke all on function public.admin_provider_edit(uuid, text, jsonb) from public, anon;
grant execute on function public.admin_provider_edit(uuid, text, jsonb) to authenticated;

-- Create a provider (PIM Operator and above)
create or replace function public.admin_provider_create(p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := gen_random_uuid(); v_name text := nullif(btrim(coalesce(p_args->>'name', '')), ''); v_country uuid := nullif(p_args->>'country_id', '')::uuid;
        v_web text := nullif(btrim(coalesce(p_args->>'website', '')), '');
begin
  if auth.uid() is null or security.current_role_rank() < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  if v_name is null then raise exception 'enter the provider name'; end if;
  if v_country is null or not exists (select 1 from ref.countries where id = v_country) then raise exception 'choose the country'; end if;
  if v_web is not null and v_web !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
  if exists (select 1 from catalogue.providers where lower(canonical_name) = lower(v_name) and country_id = v_country) then raise exception 'a provider with this name already exists in that country'; end if;
  perform set_config('cf.manual_edit', 'on', true);
  insert into catalogue.providers(id, stable_key, canonical_name, display_name, country_id, subdivision_id, website, primary_city, lifecycle_status)
  values (v_id, 'manual:' || v_id, v_name, v_name, v_country, nullif(p_args->>'subdivision_id', '')::uuid, v_web, nullif(btrim(coalesce(p_args->>'city', '')), ''), 'active');
  if v_web is not null then
    insert into pipeline.coverage_provider_discovery(provider_id, website, status, attempts, next_due_at, updated_at) values (v_id, v_web, 'pending', 0, now(), now())
    on conflict (provider_id) do nothing;
  end if;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, after, reason, actor)
  values ('provider', v_id, null, 'create', p_args, nullif(btrim(coalesce(p_args->>'reason', '')), ''), auth.uid());
  return public.admin_provider_edit_read(v_id);
end $$;
revoke all on function public.admin_provider_create(jsonb) from public, anon;
grant execute on function public.admin_provider_create(jsonb) to authenticated;

-- Pages entered by hand: left alone by the site-map matcher and the link search; the reader trusts them (md5-guarded).
do $$
declare d text; n text;
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.coverage_bind_v2(uuid)'::regprocedure) <> '755335cd5cf4caa469e88482bb430ec6'
     or (select md5(prosrc) from pg_proc where oid = 'public.svc_coverage_read_next(integer)'::regprocedure) <> '99ce501d5e0379f08ffff370d3273145' then
    raise exception 'cf247_crud_manual_first: a function changed; review first';
  end if;
  d := pg_get_functiondef('security.coverage_bind_v2(uuid)'::regprocedure);
  n := replace(d, $x$not in ('cricos_search','title_search')$x$, $x$not in ('cricos_search','title_search','manual')$x$);
  if (length(n) - length(d)) <> 2 * length(',''manual''') then raise exception 'bind_v2 edit did not apply twice'; end if;
  execute n;
  d := pg_get_functiondef('public.svc_coverage_read_next(integer)'::regprocedure);
  n := replace(d, 'returning p.course_id, p.provider_id, p.url, p.status)', 'returning p.course_id, p.provider_id, p.url, p.status, p.basis)');
  n := replace(n, $x$'status',u.status,'priority'$x$, $x$'status',u.status,'manual',coalesce(u.basis='manual',false),'priority'$x$);
  if position('p.status, p.basis)' in n) = 0 or position($x$'manual',coalesce(u.basis='manual',false)$x$ in n) = 0 then raise exception 'read_next edit did not apply'; end if;
  execute n;
end $$;
