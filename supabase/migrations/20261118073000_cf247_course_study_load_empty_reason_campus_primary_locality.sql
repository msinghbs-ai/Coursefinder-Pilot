-- CF-247 UI audit of the new API v3 fields, slices A and B (Platform Admin 18 Nov 2026 07:03, chat S1-RM-Design):
--   * Catalogue > Courses: Study load and Empty reason as columns and filters.
--   * Catalogue > Providers > Campuses: Primary as a column and filter; Locality (looked up from the campus postcode) as a column and search.
--   * The ILEP induction draft is marked: kept now, to move to the TrustEd Ireland list when that replaces the ILEP.
--
-- Courses. Every Course catalogue page item now carries study_load and empty_reason_code (read in security.course_list_with_extras_v1 from the
-- course row it already reads, so no extra lookup). courses_page takes two new optional arguments: study_load (full_time, part_time, both, or none
-- for not held) and empty_reason (one of the five reasons, any, or none). security.admin_course_page_fast sends a page with either to the filtered
-- path; security.admin_course_page_fast_base applies them on the course row before any derived value is worked out, so a filtered page reads fewer
-- courses than an unfiltered one. Two partial indexes keep the two filters to the courses that hold a value. Nothing in catalogue.courses is
-- altered, renamed or retyped (G3): the two columns are read, and an index is added beside them.
--
-- Campuses. security.admin_campuses_page_v2 is the Campuses list: the same items, filters and sorts as before, plus is_primary, primary_basis,
-- postcode, locality_name and locality_status, and two new optional arguments: primary (true or false) and locality (text in the locality name).
-- The locality is the primary postcode match, newest boundary vintage first, whatever its review status; the status is returned so the screen
-- can say when a locality is still a draft (18 Nov 2026: every locality is a draft). The course count is worked out for the rows on the page
-- only (and for every row only when the list is sorted by it). public.admin_read sends campuses_page to it; security.admin_campus_page_fast and
-- the campuses_page branch of security.admin_catalogue_page are left in place, unused, and marked retiring.
--
-- Live definitions this change edits (pg_proc.prosrc md5, read 18 Nov 2026), before -> after (the migration stops, and applies nothing, if a live body is neither):
--   security.admin_course_page_fast(jsonb)  19d7dde7292e5707a7e1bc110c6106d8 -> a5cd4a729e6ee42fb256982fb151728b
--   security.admin_course_page_fast_base(jsonb)  3b6e10e4212aebc944abaac866e50f7a -> e0cddf8a334e13e1617709ea6ab25a53
--   security.course_list_with_extras_v1(jsonb)  2a0b931a4f8f3673f2dac447ee25dd2e -> db3b7ed0edb7a7ad268be448cde863d9
--   public.admin_read(text,jsonb)  f4df73816871c19c233d0708f9d44ef6 -> b6570ab86cecb6c4d2f843538c56bd1f
-- Replaces: the four bodies above, in place (md5-guarded edits); security.admin_campus_page_fast(jsonb) as the Campuses list read
-- Retires: security.admin_campus_page_fast(jsonb) (marked retiring; dropped by a paste file after hygiene.retire_after_days, once nothing used it)

do $pre$ begin
  if to_regprocedure('security.admin_course_page_fast(jsonb)') is null or to_regprocedure('security.admin_course_page_fast_base(jsonb)') is null
     or to_regprocedure('security.course_list_with_extras_v1(jsonb)') is null or to_regprocedure('public.admin_read(text,jsonb)') is null
     or to_regclass('pipeline.admin_table_columns') is null or to_regclass('pipeline.component_register') is null
     or to_regclass('destination.locality_postcodes') is null or to_regclass('destination.localities') is null
     or to_regclass('pipeline.layer1_source_inductions') is null then
    raise exception 'an object this change builds on is missing';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'catalogue'
       and (table_name, column_name) in (('courses', 'study_load'), ('courses', 'empty_reason_code'), ('campuses', 'is_primary'), ('campuses', 'primary_basis'), ('campuses', 'postcode'))) <> 5 then
    raise exception 'a column this change reads is missing (courses.study_load, courses.empty_reason_code, campuses.is_primary, campuses.primary_basis, campuses.postcode)';
  end if;
end $pre$;

-- the two course filters read only the courses that hold a value
create index if not exists courses_study_load_idx on catalogue.courses (study_load) where study_load is not null;
create index if not exists courses_empty_reason_code_idx on catalogue.courses (empty_reason_code) where empty_reason_code is not null;

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change replaces (body md5 %)', p_sig, md5(v_src); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;


select pg_temp.edit_all('security.admin_course_page_fast(jsonb)', '19d7dde7292e5707a7e1bc110c6106d8', 'a5cd4a729e6ee42fb256982fb151728b',
  array[$o0$    and nullif(p_args->>'description','') is null
$o0$],
  array[$n0$    and nullif(p_args->>'description','') is null
    and nullif(p_args->>'study_load','') is null
    and nullif(p_args->>'empty_reason','') is null
$n0$]);

select pg_temp.edit_all('security.admin_course_page_fast_base(jsonb)', '3b6e10e4212aebc944abaac866e50f7a', 'e0cddf8a334e13e1617709ea6ab25a53',
  array[$o0$  if v_sort in ('fee','completeness') and nullif(p_args->>'description','') is null then$o0$,
        $o1$ end)))  -- fixed: the filter's own windows, as the Freshness filter's
$o1$],
  array[$n0$  -- 18 Nov 2026 (Platform Admin, Course catalogue): the Study load and Empty reason filters are applied in the bounded path below only
  if v_sort in ('fee','completeness') and nullif(p_args->>'description','') is null and nullif(p_args->>'study_load','') is null and nullif(p_args->>'empty_reason','') is null then$n0$,
        $n1$ end)))  -- fixed: the filter's own windows, as the Freshness filter's
      -- 18 Nov 2026 (Platform Admin, Course catalogue): Study load filter (none: not held) and Empty reason filter (any: a reason is recorded; none: no reason)
      and (nullif(p_args->>'study_load','') is null
        or (p_args->>'study_load'='none' and c.study_load is null)
        or c.study_load=p_args->>'study_load')
      and (nullif(p_args->>'empty_reason','') is null
        or (p_args->>'empty_reason'='any' and c.empty_reason_code is not null)
        or (p_args->>'empty_reason'='none' and c.empty_reason_code is null)
        or c.empty_reason_code=p_args->>'empty_reason')
$n1$]);

select pg_temp.edit_all('security.course_list_with_extras_v1(jsonb)', '2a0b931a4f8f3673f2dac447ee25dd2e', 'db3b7ed0edb7a7ad268be448cde863d9',
  array[$o0$left join lateral (select jsonb_build_object('description_text', c.description,$o0$],
  array[$n0$left join lateral (select jsonb_build_object('study_load', c.study_load, 'empty_reason_code', c.empty_reason_code, 'description_text', c.description,$n0$]);

-- the Course catalogue's column registry: two more columns, off until a person shows them
insert into pipeline.admin_table_columns(screen, key, grp, label, sort, sort_key, default_visible, default_width, min_width, always_visible) values
 ('courses', 'study_load', 'Course information', 'Study load', 115, null, false, 130, 90, false),
 ('courses', 'empty_reason_code', 'Course information', 'Empty reason', 215, null, false, 210, 120, false)
on conflict (screen, key) do nothing;

-- the Campuses list
create or replace function security.admin_campuses_page_v2(p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  a jsonb := coalesce(p_args, '{}'::jsonb);
  v_limit int := least(greatest(coalesce(nullif(a->>'limit', '')::int, 50), 1), 200); -- fixed: the page bounds the Campuses list has always had (request safety)
  v_offset int := greatest(coalesce(nullif(a->>'offset', '')::int, 0), 0);
  v_sort text := lower(coalesce(nullif(a->>'sort', ''), 'name'));
  v_dir text := case when lower(coalesce(nullif(a->>'direction', ''), 'asc')) = 'desc' then 'desc' else 'asc' end;
  v_q text := nullif(btrim(coalesce(a->>'query', '')), '');
  v_country text := upper(nullif(a->>'country_code', '')); v_sub text := upper(nullif(a->>'subdivision_code', ''));
  v_provider uuid := nullif(a->>'provider_id', '')::uuid; v_status text := nullif(a->>'status', ''); v_pub text := nullif(a->>'publication_status', '');
  v_primary boolean := case when nullif(a->>'primary', '') is null then null else (a->>'primary')::boolean end;
  v_loc text := nullif(btrim(coalesce(a->>'locality', '')), ''); v_loc_like text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if; -- fixed: who reads the catalogue
  -- the locality search is matched as typed text: % and _ are not wildcards
  v_loc_like := '%' || replace(replace(replace(v_loc, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return (
    with base as (
      select ca.id, ca.stable_key, ca.name, ca.campus_code, ca.provider_id, coalesce(p.display_name, p.canonical_name) provider_name, co.iso_alpha2::text country_code, co.name country_name,
             sd.code subdivision_code, sd.name subdivision_name, ca.city, ca.status, ca.publication_status, ca.last_verified_at, ca.created_at, ca.updated_at,
             coalesce(ca.is_primary, false) is_primary, ca.primary_basis, nullif(btrim(ca.postcode), '') postcode
        from catalogue.campuses ca join catalogue.providers p on p.id = ca.provider_id join ref.countries co on co.id = p.country_id left join ref.subdivisions sd on sd.id = ca.subdivision_id
       where (v_q is null or ca.name ilike '%' || v_q || '%' or coalesce(ca.campus_code, '') ilike '%' || v_q || '%' or coalesce(ca.stable_key, '') ilike '%' || v_q || '%'
              or coalesce(ca.city, '') ilike '%' || v_q || '%' or coalesce(p.display_name, p.canonical_name, '') ilike '%' || v_q || '%')
         and (v_country is null or co.iso_alpha2::text = v_country) and (v_sub is null or sd.code = v_sub) and (v_provider is null or ca.provider_id = v_provider)
         and (v_status is null or ca.status = v_status) and (v_pub is null or ca.publication_status = v_pub)
         and (v_primary is null or coalesce(ca.is_primary, false) = v_primary)
         and (v_loc is null or exists (select 1 from destination.locality_postcodes lp join destination.localities l on l.id = lp.locality_id
                                        where lp.country_code = co.iso_alpha2::character(2) and lp.postcode = nullif(btrim(ca.postcode), '') and lp.is_primary_match and l.name ilike v_loc_like))
    ), numbered as (select b.*, count(*) over () total_count from base b), ordered as (
      select n.*, row_number() over () ord from (
        select * from numbered order by
          case when v_sort in ('name', 'campus') and v_dir = 'asc' then lower(name) end asc,
          case when v_sort in ('name', 'campus') and v_dir = 'desc' then lower(name) end desc,
          case when v_sort = 'provider' and v_dir = 'asc' then lower(provider_name) end asc,
          case when v_sort = 'provider' and v_dir = 'desc' then lower(provider_name) end desc,
          case when v_sort = 'city' and v_dir = 'asc' then lower(coalesce(city, '')) end asc,
          case when v_sort = 'city' and v_dir = 'desc' then lower(coalesce(city, '')) end desc,
          -- the course count is worked out for every row only when the list is sorted by it
          case when v_sort = 'courses' and v_dir = 'asc' then (select count(*) from catalogue.course_campuses cc where cc.campus_id = numbered.id) end asc,
          case when v_sort = 'courses' and v_dir = 'desc' then (select count(*) from catalogue.course_campuses cc where cc.campus_id = numbered.id) end desc,
          case when v_sort = 'modified' and v_dir = 'asc' then updated_at end asc,
          case when v_sort = 'modified' and v_dir = 'desc' then updated_at end desc,
          lower(name), id
        limit v_limit offset v_offset) n)
    select jsonb_build_object(
      'items', coalesce(jsonb_agg((to_jsonb(o) - 'total_count' - 'ord') || jsonb_build_object(
                 'course_count', (select count(*)::int from catalogue.course_campuses cc where cc.campus_id = o.id),
                 'locality_name', loc.name, 'locality_status', loc.status) order by o.ord), '[]'::jsonb),
      'total', coalesce(max(o.total_count), (select count(*) from base)), 'limit', v_limit, 'offset', v_offset, 'sort', v_sort, 'direction', v_dir, 'execution_profile', 'campuses_page_v2')
      from ordered o
      -- the locality of the campus postcode: the primary match, newest boundary vintage first, whatever its review status
      left join lateral (select l.name, l.status from destination.locality_postcodes lp join destination.localities l on l.id = lp.locality_id
                          where lp.country_code = o.country_code::character(2) and lp.postcode = o.postcode and lp.is_primary_match
                          order by lp.boundary_vintage desc limit 1) loc on true);
end $$;
comment on function security.admin_campuses_page_v2(jsonb) is 'CF-247 Campuses list (20261118073000): the page with Primary and the Locality of the campus postcode, and the primary and locality filters. Read-only.';
revoke all on function security.admin_campuses_page_v2(jsonb) from public, anon;
grant execute on function security.admin_campuses_page_v2(jsonb) to authenticated, service_role;

select pg_temp.edit_all('public.admin_read(text,jsonb)', 'f4df73816871c19c233d0708f9d44ef6', 'b6570ab86cecb6c4d2f843538c56bd1f',
  array[$o0$ if p_operation='campuses_page' then return security.admin_campus_page_fast(p_args); end if;$o0$],
  array[$n0$ if p_operation='campuses_page' then return security.admin_campuses_page_v2(p_args); end if; -- 18 Nov 2026: Primary and Locality on the Campuses list$n0$]);

-- the read it replaces is left in place, unused, and marked retiring (the register's own dates drive its removal by paste file)
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, replaced_by, introduced_in, retire_after, note)
values ('function', 'security.admin_campus_page_fast(jsonb)', 'Platform', 'Catalogue', 'Campuses list read (before Primary and Locality)', 'retiring', '{}',
        'security.admin_campuses_page_v2(jsonb)', '20261118073000 (marked retiring)', current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int,
        'public.admin_read was its only caller; the campuses_page branch of security.admin_catalogue_page is unused too')
on conflict (kind, name) do update set status = 'retiring', replaced_by = excluded.replaced_by, retire_after = excluded.retire_after, note = excluded.note, updated_at = now()
  where pipeline.component_register.status = 'active';

-- Decision 18 Nov 2026 07:03: the ILEP draft is kept and marked, to move to the TrustEd Ireland list when that replaces the ILEP
update pipeline.layer1_source_inductions i
   set payload = i.payload || jsonb_build_object('notes', 'Wave 2 draft, pre-staged 17 Nov 2026. DEPRECATING SOURCE (Platform Admin 18 Nov 2026): inducted now so current eligible Irish programmes are covered; move this source to the TrustEd Ireland list of eligible programmes when it replaces the ILEP (expected about the end of 2026). The ILEP is closed to new programmes (final update 20 June 2025). Field names are not known yet: upload the Excel list before AI Auto-Map. Scheme ie_ilep is to be registered in ref.registration_schemes (with S2-Build) before step 1 can finish.'),
       updated_at = now()
 where i.country_code = 'IE' and i.status = 'draft' and i.payload->>'source_label' = 'Interim List of Eligible Programmes (ILEP)'
   and i.payload->>'notes' like 'Wave 2 draft, pre-staged 17 Nov 2026. Programmes a non-EEA student may enrol in.%';

do $post$ begin
  if (select count(*) from pipeline.admin_table_columns where screen = 'courses' and key in ('study_load', 'empty_reason_code')) <> 2 then raise exception 'post-check: the two course columns are not registered'; end if;
  if has_function_privilege('anon', 'security.admin_campuses_page_v2(jsonb)', 'execute') then raise exception 'post-check: anon can run the Campuses list'; end if;
  if position('admin_campuses_page_v2' in (select prosrc from pg_proc where oid = 'public.admin_read(text,jsonb)'::regprocedure)) = 0 then raise exception 'post-check: admin_read does not send campuses_page to the new read'; end if;
end $post$;
