-- CF-247 (Platform Admin, 1 Oct 2026 16:54 AEST): course and handbook pages from Firecrawl and third-party or regulatory
-- portals must land in the course links, be maintainable by hand, and be refreshed on a schedule; the target applicant
-- is the international student, and courses open only to domestic students must be identifiable so that a missing
-- English requirement makes sense.
--
-- 1. Link types. ref.course_link_types lists the kinds of course link the catalogue keeps: official course page,
--    handbook entry, international students page, admission centre listing (UAC, VTAC, QTAC, SATAC, TISC), regulator
--    listing (CRICOS, NZQA) and how-to-apply page. catalogue.course_links.link_type must be one of them.
-- 2. Manual edits win for every link type. security.manual_fact_guard already kept automation away from an official
--    page set by hand ('official_url'); every other link type now has its own lock field 'link:<type>'.
-- 3. Who can apply. catalogue.courses gains open_to_international and open_to_domestic (true, false, or null for not
--    known) with the basis; catalogue.providers gains enrols_international with its basis. Australian CRICOS-registered
--    courses are open to international students (the register exists for that purpose); CRICOS providers enrol them.
--    Domestic availability is left unknown until a source states it. NZ and Canada are left unknown until set.
-- 4. NZQA regulator listing: every NZ course with an NZQA code gets its NZQA qualification page (provider programme
--    codes such as AK3717 and national NZQF qualification numbers such as 1714 are both NZQA page keys; the NZ loader
--    takes each code from NZQA's own viewQualification.do?selectedItemKey= link).
-- 5. Maintenance by hand: public.admin_course_links_read / admin_course_link_edit (add, change, remove, release any link
--    type; the official page keeps using admin_course_edit so its page search and reader stay in step),
--    public.admin_course_applicants_edit and public.admin_provider_applicants_edit. All role-checked, locked and logged.
-- 6. Courses list filter "International students": open, not open (domestic only), open to both, not yet known.
-- Functions are edited in place from their live definitions, each only if its live body is the one checked on
-- 1 Oct 2026 (md5 guard).

-- 1. Link types ---------------------------------------------------------------------------------------------------------
create table if not exists ref.course_link_types (
  code text primary key,
  label text not null,
  description text,
  applicant text not null default 'any' check (applicant in ('any','international','domestic')),
  sort int not null default 100,
  status text not null default 'active' check (status in ('active','retired'))
);
insert into ref.course_link_types(code, label, description, applicant, sort) values
  ('official_course',   'Official course page',          'The provider''s own page for the course.', 'any', 10),
  ('handbook',          'Handbook entry',                'The provider''s handbook or course rules page.', 'any', 20),
  ('international_page','International students page',   'The provider''s page for international applicants to this course.', 'international', 30),
  ('application',       'How to apply',                  'The provider''s application page for this course.', 'any', 40),
  ('admission_centre',  'Admission centre listing',      'The course on a tertiary admission centre (UAC, VTAC, QTAC, SATAC, TISC); mostly domestic undergraduate entry.', 'domestic', 50),
  ('regulator_listing', 'Regulator listing',             'The course on the national register (CRICOS, NZQA).', 'any', 60)
on conflict (code) do update set label = excluded.label, description = excluded.description, applicant = excluded.applicant, sort = excluded.sort;
alter table ref.course_link_types enable row level security;
drop policy if exists course_link_types_read on ref.course_link_types;
create policy course_link_types_read on ref.course_link_types for select to authenticated using (true);
grant select on ref.course_link_types to authenticated;

do $fk$
begin
  if not exists (select 1 from pg_constraint where conname = 'course_links_link_type_fkey' and conrelid = 'catalogue.course_links'::regclass) then
    alter table catalogue.course_links add constraint course_links_link_type_fkey foreign key (link_type) references ref.course_link_types(code);
  end if;
end $fk$;

-- 2. Manual lock for every link type ---------------------------------------------------------------------------------
do $guard$
declare s text; d text; v text;
  o text := $o$case when r->>'link_type' = 'official_course' then 'official_url' end$o$;
  n text := $n$case when r->>'link_type' = 'official_course' then 'official_url' else 'link:' || (r->>'link_type') end$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'manual_fact_guard';
  v := md5(s);
  if v is distinct from '8c7fe38930baf6eb8e666ccdabf472bb' then raise exception 'manual_fact_guard changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'manual_fact_guard: link clause not found once'; end if;
  execute replace(d, o, n);
end $guard$;

-- 3. Who can apply ---------------------------------------------------------------------------------------------------
alter table catalogue.courses add column if not exists open_to_international boolean;
alter table catalogue.courses add column if not exists open_to_domestic boolean;
alter table catalogue.courses add column if not exists applicant_basis text;
alter table catalogue.providers add column if not exists enrols_international boolean;
alter table catalogue.providers add column if not exists enrols_international_basis text;

update catalogue.providers p
   set enrols_international = true, enrols_international_basis = 'CRICOS provider registration'
  from ref.countries k
 where k.id = p.country_id and k.iso_alpha2 = 'AU' and p.enrols_international is null
   and exists (select 1 from catalogue.provider_registrations r where r.provider_id = p.id and lower(r.registration_scheme) = 'cricos'
                 and coalesce(r.status, 'active') not in ('inactive','cancelled','archived'));

update catalogue.courses c
   set open_to_international = true, applicant_basis = 'CRICOS course registration'
 where c.open_to_international is null
   and exists (select 1 from catalogue.course_registrations r where r.course_id = c.id and lower(r.scheme) = 'cricos'
                 and coalesce(r.status, 'active') not in ('inactive','cancelled','archived'));

create index if not exists courses_open_to_international_idx on catalogue.courses(open_to_international);

-- 4. NZQA regulator listing ------------------------------------------------------------------------------------------
insert into catalogue.course_links(course_id, link_type, url, label, is_primary, status, source_id, confidence)
select r.course_id, 'regulator_listing',
       'https://www.nzqa.govt.nz/nzqf/search/viewQualification.do?selectedItemKey=' || upper(btrim(r.registration_code)),
       'NZQA qualification listing', false, 'active',
       (select s.id from pipeline.sources s where s.url ilike 'https://www.nzqa.govt.nz/providers/%' order by s.created_at limit 1), 0.95
  from catalogue.course_registrations r join catalogue.courses c on c.id = r.course_id and c.lifecycle_status = 'active'
 where lower(r.scheme) = 'nzqa' and coalesce(r.status, 'active') = 'active' and btrim(r.registration_code) ~* '^[A-Z0-9]{3,12}$'
on conflict (course_id, link_type, url) do nothing;

-- 5. Maintenance by hand ---------------------------------------------------------------------------------------------
create or replace function public.admin_course_links_read(p_course_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $fn$
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
end $fn$;
revoke all on function public.admin_course_links_read(uuid) from public, anon;
grant execute on function public.admin_course_links_read(uuid) to authenticated;

create or replace function public.admin_course_link_edit(p_course_id uuid, p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare v_rank int := security.current_role_rank(); v_src uuid; v_type text := nullif(btrim(coalesce(p_args->>'link_type', '')), '');
        v_url text := nullif(btrim(coalesce(p_args->>'url', '')), ''); v_label text := nullif(btrim(coalesce(p_args->>'label', '')), '');
        v_reason text := nullif(btrim(coalesce(p_args->>'reason', '')), ''); l catalogue.course_links%rowtype; v_before jsonb; v_after jsonb; v_left int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if not exists (select 1 from catalogue.courses where id = p_course_id) then raise exception 'course not found'; end if;
  if p_action in ('change','remove') then
    select * into l from catalogue.course_links where id = nullif(p_args->>'link_id', '')::uuid and course_id = p_course_id;
    if l.id is null then raise exception 'link not found on this course'; end if;
    v_type := l.link_type;
  end if;
  if v_type is null or not exists (select 1 from ref.course_link_types where code = v_type and status = 'active') then raise exception 'choose a link type'; end if;
  if p_action in ('add','change') and (v_url is null or v_url !~* '^https?://[^\s/]+\.[^\s]+$') then raise exception 'enter a full web address starting with https://'; end if;

  -- The official page keeps its own edit path (page search, reader and Layer 4 stay in step).
  if v_type = 'official_course' then
    if p_action in ('add','change') then
      perform public.admin_course_edit(p_course_id, 'set_official_url', jsonb_build_object('url', v_url, 'reason', v_reason));
    elsif p_action = 'remove' then
      select count(*) into v_left from catalogue.course_links where course_id = p_course_id and link_type = 'official_course' and status = 'active' and id <> l.id;
      if v_left = 0 then
        perform public.admin_course_edit(p_course_id, 'remove_official_url', jsonb_build_object('reason', v_reason));
      else
        perform set_config('cf.manual_edit', 'on', true);
        update catalogue.course_links set status = 'inactive', is_primary = false, updated_at = now() where id = l.id;
        perform security.manual_lock_set('course', p_course_id, 'official_url', 'value');
        insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
        values ('course', p_course_id, 'official_url', 'remove_link', to_jsonb(l.url), null, v_reason, auth.uid());
      end if;
    elsif p_action = 'release' then
      perform public.admin_course_edit(p_course_id, 'release', jsonb_build_object('field', 'official_url'));
    else raise exception 'unknown action %', p_action; end if;
    return public.admin_course_links_read(p_course_id);
  end if;

  perform set_config('cf.manual_edit', 'on', true);
  select id into v_src from pipeline.sources where source_type = 'manual_entry' limit 1;
  if p_action = 'add' then
    insert into catalogue.course_links(course_id, link_type, url, label, audience, is_primary, status, source_id, confidence, last_verified_at)
    values (p_course_id, v_type, v_url, coalesce(v_label, (select label from ref.course_link_types where code = v_type)), nullif(p_args->>'audience', ''),
            not exists (select 1 from catalogue.course_links x where x.course_id = p_course_id and x.link_type = v_type and x.status = 'active'),
            'active', v_src, 1, now())
    on conflict (course_id, link_type, url) do update set status = 'active', label = coalesce(v_label, catalogue.course_links.label),
           source_id = v_src, confidence = 1, last_verified_at = now(), updated_at = now();
    perform security.manual_lock_set('course', p_course_id, 'link:' || v_type, 'value');
    v_after := jsonb_build_object('url', v_url, 'label', v_label);
  elsif p_action = 'change' then
    v_before := jsonb_build_object('url', l.url, 'label', l.label, 'status', l.status);
    update catalogue.course_links set url = v_url, label = coalesce(v_label, label), audience = coalesce(nullif(p_args->>'audience', ''), audience),
           status = 'active', source_id = v_src, confidence = 1, last_verified_at = now(), updated_at = now()
     where id = l.id;
    perform security.manual_lock_set('course', p_course_id, 'link:' || v_type, 'value');
    v_after := jsonb_build_object('url', v_url, 'label', v_label);
  elsif p_action = 'remove' then
    v_before := jsonb_build_object('url', l.url, 'label', l.label);
    update catalogue.course_links set status = 'inactive', is_primary = false, updated_at = now() where id = l.id;
    select count(*) into v_left from catalogue.course_links where course_id = p_course_id and link_type = v_type and status = 'active';
    perform security.manual_lock_set('course', p_course_id, 'link:' || v_type, case when v_left = 0 then 'removed' else 'value' end);
  elsif p_action = 'release' then
    select to_jsonb(k) into v_before from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = p_course_id and k.field = 'link:' || v_type;
    if v_before is null then raise exception 'nothing to release'; end if;
    delete from pipeline.manual_locks where entity = 'course' and entity_id = p_course_id and field = 'link:' || v_type;
  else raise exception 'unknown action %', p_action; end if;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('course', p_course_id, 'link:' || v_type, p_action || '_link', v_before, v_after, v_reason, auth.uid());
  perform search.refresh_course_enrichment_scoped_v1(array[p_course_id], true);
  return public.admin_course_links_read(p_course_id);
end $fn$;
revoke all on function public.admin_course_link_edit(uuid, text, jsonb) from public, anon;
grant execute on function public.admin_course_link_edit(uuid, text, jsonb) to authenticated;

create or replace function public.admin_course_applicants_edit(p_course_id uuid, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare v_rank int := security.current_role_rank(); c catalogue.courses%rowtype; f text; v_reason text := nullif(btrim(coalesce(p_args->>'reason', '')), '');
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into c from catalogue.courses where id = p_course_id;
  if c.id is null then raise exception 'course not found'; end if;
  perform set_config('cf.manual_edit', 'on', true);
  if coalesce(p_args->>'action', 'set') = 'release' then
    delete from pipeline.manual_locks where entity = 'course' and entity_id = p_course_id and field in ('open_to_international','open_to_domestic');
    insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
    values ('course', p_course_id, 'applicants', 'release', jsonb_build_object('international', c.open_to_international, 'domestic', c.open_to_domestic), null, v_reason, auth.uid());
    return public.admin_course_links_read(p_course_id);
  end if;
  foreach f in array array['open_to_international','open_to_domestic'] loop
    if p_args ? f and jsonb_typeof(p_args->f) not in ('boolean','null') then raise exception 'choose yes, no or not known'; end if;
  end loop;
  update catalogue.courses set
    open_to_international = case when p_args ? 'open_to_international' then (p_args->>'open_to_international')::boolean else open_to_international end,
    open_to_domestic = case when p_args ? 'open_to_domestic' then (p_args->>'open_to_domestic')::boolean else open_to_domestic end,
    applicant_basis = 'Set by hand', updated_at = now()
   where id = p_course_id;
  foreach f in array array['open_to_international','open_to_domestic'] loop
    if p_args ? f then perform security.manual_lock_set('course', p_course_id, f, 'value'); end if;
  end loop;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('course', p_course_id, 'applicants', 'set_applicants', jsonb_build_object('international', c.open_to_international, 'domestic', c.open_to_domestic),
          p_args - 'reason', v_reason, auth.uid());
  perform search.refresh_course_enrichment_scoped_v1(array[p_course_id], true);
  return public.admin_course_links_read(p_course_id);
end $fn$;
revoke all on function public.admin_course_applicants_edit(uuid, jsonb) from public, anon;
grant execute on function public.admin_course_applicants_edit(uuid, jsonb) to authenticated;

-- A provider setting applies to its courses that nobody has set by hand.
create or replace function public.admin_provider_applicants_edit(p_provider_id uuid, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare v_rank int := security.current_role_rank(); p catalogue.providers%rowtype; v_val boolean; v_n int := 0;
        v_reason text := nullif(btrim(coalesce(p_args->>'reason', '')), '');
begin
  if auth.uid() is null or v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
  select * into p from catalogue.providers where id = p_provider_id;
  if p.id is null then raise exception 'provider not found'; end if;
  if not (p_args ? 'enrols_international') or jsonb_typeof(p_args->'enrols_international') not in ('boolean','null') then raise exception 'choose yes, no or not known'; end if;
  v_val := (p_args->>'enrols_international')::boolean;
  perform set_config('cf.manual_edit', 'on', true);
  update catalogue.providers set enrols_international = v_val, enrols_international_basis = 'Set by hand', updated_at = now() where id = p_provider_id;
  perform security.manual_lock_set('provider', p_provider_id, 'enrols_international', 'value');
  if coalesce((p_args->>'apply_to_courses')::boolean, true) then
    update catalogue.courses c set open_to_international = v_val, applicant_basis = 'Provider setting', updated_at = now()
     where c.provider_id = p_provider_id and c.open_to_international is distinct from v_val
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field = 'open_to_international');
    get diagnostics v_n = row_count;
  end if;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('provider', p_provider_id, 'enrols_international', 'set', to_jsonb(p.enrols_international),
          jsonb_build_object('value', v_val, 'courses_changed', v_n), v_reason, auth.uid());
  return jsonb_build_object('provider_id', p_provider_id, 'enrols_international', v_val, 'courses_changed', v_n);
end $fn$;
revoke all on function public.admin_provider_applicants_edit(uuid, jsonb) from public, anon;
grant execute on function public.admin_provider_applicants_edit(uuid, jsonb) to authenticated;

-- 6. Courses list filter ---------------------------------------------------------------------------------------------
do $page$
declare s text; d text; v text; o text; n text;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'admin_course_page_fast';
  v := md5(s);
  if v is distinct from '174c74dedad15bbfbfc92a8f9c2b2d4a' then raise exception 'admin_course_page_fast changed (md5 %); not replacing', v; end if;
  o := E'    and nullif(p_args->>''university_group'','''') is null\n';
  n := o || E'    and nullif(p_args->>''applicant'','''') is null\n';
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'admin_course_page_fast: anchor not found once'; end if;
  execute replace(d, o, n);

  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'admin_course_page_fast_base';
  v := md5(s);
  if v is distinct from 'c42b91769e4d7e8f2130bda8712880ff' then raise exception 'admin_course_page_fast_base changed (md5 %); not replacing', v; end if;
  o := E'      and (v_has_link is null or exists(\n        select 1 from catalogue.course_links l where l.course_id=c.id and l.status=''active'')=v_has_link)\n';
  n := o || E'      and (nullif(p_args->>''applicant'','''') is null\n'
          || E'        or (p_args->>''applicant''=''international'' and c.open_to_international is true)\n'
          || E'        or (p_args->>''applicant''=''domestic_only'' and c.open_to_international is false)\n'
          || E'        or (p_args->>''applicant''=''both'' and c.open_to_international is true and c.open_to_domestic is true)\n'
          || E'        or (p_args->>''applicant''=''unknown'' and c.open_to_international is null))\n';
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'admin_course_page_fast_base: filter anchor not found once'; end if;
  d := replace(d, o, n);
  o := 'c.duration_value,c.description,c.delivery_mode canonical_delivery_mode,';
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'admin_course_page_fast_base: base anchor not found once'; end if;
  d := replace(d, o, o || 'c.open_to_international,c.open_to_domestic,');
  o := 'pg.provider_name,pg.country_code,';
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'admin_course_page_fast_base: enriched anchor not found once'; end if;
  d := replace(d, o, 'pg.open_to_international,pg.open_to_domestic,' || o);
  execute d;
end $page$;
