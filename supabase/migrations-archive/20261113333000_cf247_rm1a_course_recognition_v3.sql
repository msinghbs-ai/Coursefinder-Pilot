-- CF-247 RM1A-1 (O29, Australia): course recognition on Website API v3 course detail. Admin destination data design v1.1, section
-- "S1-RM-Design" §4 M1 (docs/Roadmap/2026-01/DESTINATION-DATA-DESIGN.md); Platform Admin 13 Nov 2026 15:29 AEDT: "step 1 - maintain the
-- design and operational mechanisms". Decision 277: v3 only, v2 is only read.
-- Guards: G1 (no job), G2 (no operational value: the released scheme list is the contract, not a tunable), G3 (no website_v2_*, zoho_v2_*,
--   api.* or zoho_v3_* object is altered; Zoho v3 course gains the field in a separate change after the Zoho developer is told), G4
--   (tests/uat/cf-247-rm1a-course-recognition-v3-contract.spec.mjs), Decision 260.
-- What:
--   1. security.course_recognition_v1(course ids): set-based, read only. One row per id passed in: recognition[] (the course's active CRICOS
--      registrations with an active public source and no past end date; each item {scheme, code, status, authority, source_url,
--      evidence_date, checked_on}) and a held reason when a registration is not shown
--      (registration_dates_inconsistent: status active with valid_to on or before today; registration_source_missing). Withdrawn (inactive)
--      registrations give nothing. NZQA is not released: its stored evidence is a provider list, not course-grain (design §1).
--   2. security.course_recognition_item_v1(item): a v3 course item with "recognition" added ([] when nothing is admitted; [] never means
--      "not recognised"). The course is found from search.course_documents, as website_v3_course_item_r28 does, so only items v2 returned
--      are decorated and every visibility rule is inherited.
--   3. public.website_v3_course (both forms): their current answer plus item 2. Nothing else changes.
--   4. security.course_recognition_delivery_v1() and public.admin_course_recognition_delivery() (Curator and above): Data Delivery panel
--      counts (searchable courses, served with recognition, held by reason, NZ awaiting course-grain evidence).
--   5. public.admin_course_recognition_read(course id) (any StudySearch role): the course blade's Recognition card, every active and inactive
--      registration with its source, evidence, dates and whether Website v3 shows it, and why not.
-- Replaces: public.website_v3_course(text) and public.website_v3_course(text, text) (same names and signatures; md5-guarded against the
--   definitions from 20261113180000 and 20261113220000). Retires: nothing.
-- Reversal: re-create the two website_v3_course definitions from 20261113180000 (one argument) and 20261113220000 (two arguments); the new
--   functions are then unused and are retired by paste file. v2 and Zoho are unaffected either way.

do $guard$
declare v_want jsonb := jsonb_build_object(
  'public.website_v3_course(text)', 'b8d1b6999d19396137836aebda0b2a5b',
  'public.website_v3_course(text,text)', '0d3ea4ec3334777a609de5ee0c3063cf'); k text;
begin
  for k in select jsonb_object_keys(v_want) loop
    if md5(pg_get_functiondef(k::regprocedure)) <> v_want->>k then
      raise exception 'live % differs from the definition this change replaces (md5 %)', k, md5(pg_get_functiondef(k::regprocedure));
    end if;
  end loop;
  if to_regclass('catalogue.course_registrations') is null or to_regclass('search.course_documents') is null
     or to_regprocedure('public.website_v3_course_item_r28(jsonb)') is null or to_regprocedure('security.current_role_rank()') is null
  then raise exception 'an object this change reads is missing'; end if;
end $guard$;

-- 1 -------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.course_recognition_v1(p_course_ids uuid[])
returns table (course_id uuid, recognition jsonb, held_reason text)
language sql stable security definer set search_path = '' as $$
  select u.id,
         coalesce(jsonb_agg(jsonb_build_object(
             'scheme', 'CRICOS', 'code', r.registration_code, 'status', 'registered',
             'authority', 'Australian Government (CRICOS)', 'source_url', s.url,
             'evidence_date', to_char((e.captured_at at time zone 'Australia/Melbourne')::date, 'YYYY-MM-DD'),     -- the stored register file behind this row
             'checked_on', to_char((s.last_success_at at time zone 'Australia/Melbourne')::date, 'YYYY-MM-DD'))  -- the register's last successful check
           order by r.registration_code)
           filter (where r.id is not null and s.url is not null and (r.valid_to is null or r.valid_to > current_date)), '[]'::jsonb),
         case when bool_or(r.id is not null and r.valid_to is not null and r.valid_to <= current_date) then 'registration_dates_inconsistent'
              when bool_or(r.id is not null and s.url is null) then 'registration_source_missing' end
    from unnest(p_course_ids) u(id)
    left join catalogue.course_registrations r on r.course_id = u.id and r.scheme = 'cricos' and r.status = 'active'
    left join pipeline.sources s on s.id = r.source_id and s.status = 'active'
    left join pipeline.evidence_artifacts e on e.id = r.evidence_id
   where u.id is not null
   group by u.id
$$;
revoke all on function security.course_recognition_v1(uuid[]) from public, anon, authenticated;
comment on function security.course_recognition_v1(uuid[]) is
  'CF-247 RM1A-1 (O29): CRICOS course recognition for the given courses, with a held reason; read by Website API v3 course and the Admin Recognition views. Read only.';

-- 2 -------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.course_recognition_item_v1(p_item jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_course uuid; v_rec jsonb;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' then return p_item; end if;
  select d.course_id into v_course from search.course_documents d
   where lower(d.course_stable_key) = lower(p_item->>'course_id') and d.course_stable_key is not null limit 1;
  if v_course is not null then
    select x.recognition into v_rec from security.course_recognition_v1(array[v_course]) x;
  end if;
  return p_item || jsonb_build_object('recognition', coalesce(v_rec, '[]'::jsonb));
end $$;
revoke all on function security.course_recognition_item_v1(jsonb) from public, anon, authenticated;
comment on function security.course_recognition_item_v1(jsonb) is
  'CF-247 RM1A-1 (O29): a Website v3 course item with recognition[] added ([] when none is admitted); nothing else changed.';

-- 3 -------------------------------------------------------------------------------------------------------------------------------------
create or replace function public.website_v3_course(p_identifier text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_course(p_identifier);
begin
  if v ? 'item' then v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item')); end if;
  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', security.course_recognition_item_v1(v->'item')); end if;  -- RM1A-1 (O29)
  return v;
end $$;

create or replace function public.website_v3_course(p_identifier text, p_edu_country text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_course(p_identifier, p_edu_country); v_course uuid; v_provider uuid; v_cc text := upper(btrim(coalesce(p_edu_country, '')));
begin
  if v ? 'item' then v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item')); end if;
  if jsonb_typeof(v #> '{item,entry,resolution,rows}') = 'array' then
    select d.course_id, d.provider_id into v_course, v_provider from search.course_documents d
     where lower(d.course_stable_key) = lower(v->'item'->>'course_id') and d.course_stable_key is not null limit 1;
    v := jsonb_set(v, '{item,entry,resolution,rows}', (select coalesce(jsonb_agg(r || jsonb_build_object('source_url', coalesce(
             (select m.source_url from catalogue.provider_entry_matrix m
               where m.provider_id = v_provider and m.status = 'active' and m.country_code = v_cc and m.quote = r->>'quote' order by m.updated_at desc limit 1),
             (select x.source_url from catalogue.course_entry_requirements x
               where x.course_id = v_course and x.status = 'active' and x.quote = r->>'quote' order by x.updated_at desc limit 1))) order by o), '[]'::jsonb)
        from jsonb_array_elements(v #> '{item,entry,resolution,rows}') with ordinality t(r, o)));
  end if;
  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', security.course_recognition_item_v1(v->'item')); end if;  -- RM1A-1 (O29)
  return v;
end $$;
comment on function public.website_v3_course(text) is 'Website API v3 (Decision 277): website_v2_course with R28 and recognition[] (O29, RM1A-1).';
comment on function public.website_v3_course(text, text) is 'Website API v3 (Decision 277): website_v2_course with R28, entry.resolution.rows[] source_url (O20) and recognition[] (O29, RM1A-1).';

-- 4 -------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.course_recognition_delivery_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v jsonb;
begin
  with d as (select d.course_id, d.country_code from search.course_documents d where d.country_code in ('AU', 'NZ')),
  x as (select d.course_id, d.country_code,
               bool_or(r.scheme = 'cricos' and s.url is not null and (r.valid_to is null or r.valid_to > current_date)) served,
               bool_or(r.scheme = 'cricos' and r.valid_to is not null and r.valid_to <= current_date) dates_bad,
               bool_or(r.scheme = 'cricos' and s.url is null) no_source,
               bool_or(r.scheme = 'nzqa') nzqa
          from d left join catalogue.course_registrations r on r.course_id = d.course_id and r.status = 'active' and r.scheme in ('cricos', 'nzqa')
          left join pipeline.sources s on s.id = r.source_id and s.status = 'active'
         group by 1, 2)
  select jsonb_build_object(
    'au', jsonb_build_object('searchable', count(*) filter (where country_code = 'AU'),
            'served', count(*) filter (where country_code = 'AU' and served),
            'held_dates_inconsistent', count(*) filter (where country_code = 'AU' and not coalesce(served, false) and dates_bad),
            'held_source_missing', count(*) filter (where country_code = 'AU' and not coalesce(served, false) and not coalesce(dates_bad, false) and no_source),
            'no_registration', count(*) filter (where country_code = 'AU' and served is null)),
    'nz', jsonb_build_object('searchable', count(*) filter (where country_code = 'NZ'),
            'with_nzqa_code', count(*) filter (where country_code = 'NZ' and nzqa),
            'served', 0, 'held_reason', 'NZQA course listing not yet captured at course grain (RM4A)'),
    'next_action', 'F-DISC: reconcile active CRICOS registrations whose end date has passed; RM4A: capture a course-grain NZQF listing')
    into v from x;
  return v;
exception when others then
  return jsonb_build_object('known', false, 'reason', left(sqlerrm, 200));
end $f$;
revoke all on function security.course_recognition_delivery_v1() from public, anon, authenticated;
comment on function security.course_recognition_delivery_v1() is
  'CF-247 RM1A-1 (O29): course recognition coverage for the Data Delivery screen (public.admin_course_recognition_delivery). Read only, about 0.2 s.';

create or replace function public.admin_course_recognition_delivery()
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;  -- fixed: the Data Delivery screen's rank (admin_layer23 data_delivery)
  return security.course_recognition_delivery_v1() || jsonb_build_object('counted_at', now());
end $f$;
revoke all on function public.admin_course_recognition_delivery() from public, anon;
grant execute on function public.admin_course_recognition_delivery() to authenticated;
comment on function public.admin_course_recognition_delivery() is
  'CF-247 RM1A-1 (O29): Layer 2/3 › Operations, Data Delivery, Course recognition panel. Curator and above; read only; never part of the consumer API.';

-- 5 -------------------------------------------------------------------------------------------------------------------------------------
create or replace function public.admin_course_recognition_read(p_course_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_rec record;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  select * into v_rec from security.course_recognition_v1(array[p_course_id]);
  return jsonb_build_object(
    'course_id', p_course_id,
    'in_search', exists (select 1 from search.course_documents d where d.course_id = p_course_id),
    'served', coalesce(v_rec.recognition, '[]'::jsonb),
    'held_reason', v_rec.held_reason,
    'registrations', coalesce((select jsonb_agg(jsonb_build_object(
        'scheme', r.scheme, 'code', r.registration_code, 'status', r.status, 'valid_from', r.valid_from, 'valid_to', r.valid_to,
        'source_label', s.label, 'source_url', s.url, 'evidence_id', r.evidence_id, 'captured_at', e.captured_at,
        'on_website_v3', r.scheme = 'cricos' and r.status = 'active' and s.url is not null and (r.valid_to is null or r.valid_to > current_date)
                         and exists (select 1 from search.course_documents d where d.course_id = p_course_id))
        order by r.status, r.scheme, r.registration_code)
      from catalogue.course_registrations r
      left join pipeline.sources s on s.id = r.source_id and s.status = 'active'
      left join pipeline.evidence_artifacts e on e.id = r.evidence_id
     where r.course_id = p_course_id), '[]'::jsonb));
end $f$;
revoke all on function public.admin_course_recognition_read(uuid) from public, anon;
grant execute on function public.admin_course_recognition_read(uuid) to authenticated;
comment on function public.admin_course_recognition_read(uuid) is
  'CF-247 RM1A-1 (O29): Course detail Recognition card: registrations with source, evidence and dates, and what Website v3 shows and why not. Any StudySearch role; read only.';

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.course_recognition_v1', 'Platform', 'O29 CRICOS course recognition with held reason (Website v3 course, Admin)', 'active', '{}', '20261113333000'),
 ('function', 'security.course_recognition_item_v1', 'Platform', 'Website v3 course item with recognition[]', 'active', '{}', '20261113333000'),
 ('function', 'security.course_recognition_delivery_v1', 'Platform', 'Data Delivery: course recognition coverage and holds', 'active', '{}', '20261113333000'),
 ('function', 'public.admin_course_recognition_delivery', 'Platform', 'Data Delivery Course recognition panel read (Curator and above)', 'active', '{}', '20261113333000'),
 ('function', 'public.admin_course_recognition_read', 'Platform', 'Course detail Recognition card read', 'active', '{}', '20261113333000')
on conflict do nothing;
