-- CF-247 s818 (Platform Admin 20 Nov 2026 09:55 and 10:48 AEDT, chat S1-Build): the providers whose main campus was left unset by the s797
-- rule because several campuses tie on active courses, and the NZ and CA courses with no campus. $0: register and catalogue data only.
-- 1. Tie-breaks, in order, among the tied campuses only (security.campus_primary_tiebreak_v1):
--    a. the official registered city: the campus in the provider's registered city (catalogue.providers.primary_city), when that narrows them;
--    b. the statutory register head office: the campus at the provider's registered address and postcode, when that narrows them further;
--    c. co-located campuses (all in one city): the earliest registered campus (lowest register campus code, then the oldest record).
--    One campus left -> it is the main campus. Its primary_basis is highest_course_count (it is one of the tied highest; the column's allowed
--    values are part of the catalogue and are not changed); the tie-break that chose it (registered_city_match, register_head_office_address,
--    earliest_registered_campus) is kept for each provider in the audit row (pipeline.admin_control_events, campus_primary_tiebreak).
--    Tied campuses in different cities with no register match stay unset for a person: Catalogue › Providers has a Main campus filter (Unset).
-- 2. NZ and CA courses with no campus whose provider has exactly one active campus get that campus (course_campuses, primary), unless the
--    course is online only (empty_reason_code online_only_no_campus) or locked; their search documents are queued for refresh.
-- 3. NZ campuses with no region get one when their name names exactly one NZ region or a listed city (setting campus.nz_city_regions).
-- Nothing already set is changed (no-overwrite); manual locks are respected; no provider ends with two main campuses (post-check).
-- Parity before writing (read live 20 Nov 2026 11:20 AEDT): head 20261120110000; numbered above every open pull request (Pilot #1413 holds 20261120114000).
-- G3: no consumer object changes (data only; admin_providers_page_v3 is not consumer API). No spend.
-- Replaces: nothing. Retires: nothing.

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'campus.nz_city_regions', 'NZ campus regions: cities', 'A New Zealand campus with no region takes the region of a city named in its name, when every city named points to one region.',
        'text', '{"Auckland": "NZ-AUK", "New Lynn": "NZ-AUK", "Mt Albert": "NZ-AUK", "Mount Albert": "NZ-AUK", "Christchurch": "NZ-CAN", "Timaru": "NZ-CAN", "Wellington": "NZ-WGN", "Lower Hutt": "NZ-WGN", "Hamilton": "NZ-WKO", "Dunedin": "NZ-OTA", "Queenstown": "NZ-OTA", "Palmerston North": "NZ-MWT", "Whanganui": "NZ-MWT", "Napier": "NZ-HKB", "Hastings": "NZ-HKB", "Whangārei": "NZ-NTL", "Whangarei": "NZ-NTL", "Kerikeri": "NZ-NTL", "Kaitaia": "NZ-NTL", "Tauranga": "NZ-BOP", "Rotorua": "NZ-BOP", "Invercargill": "NZ-STL", "New Plymouth": "NZ-TKI", "Nelson": "NZ-NSN", "Blenheim": "NZ-MBH", "Gisborne": "NZ-GIS"}'::jsonb,
        null, null, 'city to region', 3401, 'Catalogue rules', 'security.campus_nz_region_fill_v1', 'CF-247 s818 (Platform Admin 20 Nov 2026 09:55): NZ region backfill from campus names')
on conflict do nothing;

-- 1. tie-breaks
create or replace function security.campus_primary_tiebreak_v1(p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_rows jsonb; v_n int := 0; v_by jsonb; v_left jsonb;
begin
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  with prov as (
    select p.id, k.iso_alpha2 cc from catalogue.providers p join ref.countries k on k.id = p.country_id and k.iso_alpha2 in ('AU', 'NZ', 'CA')
     where p.lifecycle_status = 'active'
       and not exists (select 1 from catalogue.campuses x where x.provider_id = p.id and x.is_primary)
       and not exists (select 1 from pipeline.manual_locks l join catalogue.campuses x on x.id = l.entity_id
                        where l.entity = 'campus' and l.field in ('is_primary', 'primary_basis') and x.provider_id = p.id)),
  cnt as (
    select k.provider_id, k.id campus_id, prov.cc,
           (select count(distinct cc.course_id) from catalogue.course_campuses cc join catalogue.courses c on c.id = cc.course_id and c.lifecycle_status = 'active'
             where cc.campus_id = k.id)::int n
      from catalogue.campuses k join prov on prov.id = k.provider_id where k.status = 'active'),
  top as (select z.* from (select cnt.*, rank() over (partition by provider_id order by n desc) rk, count(*) over (partition by provider_id, n) t from cnt) z where z.rk = 1 and z.t > 1),
  cand as (
    select t.provider_id, t.cc, k.id campus_id, k.city, k.campus_code, k.created_at,
           coalesce(lower(btrim(k.city)) = lower(btrim(p.primary_city)), false) city_match,
           coalesce(nullif(btrim(k.address_line1), '') is not null
                    and lower(regexp_replace(btrim(k.address_line1), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(p.address_line1), '\s+', ' ', 'g'))
                    and btrim(coalesce(k.postcode, '')) = btrim(coalesce(p.postcode, '')), false) addr_match
      from top t join catalogue.campuses k on k.id = t.campus_id join catalogue.providers p on p.id = t.provider_id),
  c1 as (select c.*, case when bool_or(c.city_match) over (partition by c.provider_id) then c.city_match else true end keep1 from cand c),
  c2 as (select c.*, c.keep1 and case when bool_or(c.addr_match) filter (where c.keep1) over (partition by c.provider_id) then c.addr_match else true end keep2 from c1 c),
  pick as (
    select c.provider_id, c.cc, count(*) n2, count(distinct lower(btrim(c.city))) ncity, bool_or(nullif(btrim(c.city), '') is null) nocity,
           bool_or(c.city_match) any_city, bool_or(c.addr_match) any_addr,
           (array_agg(c.campus_id order by c.campus_code is null, length(c.campus_code), c.campus_code, c.created_at, c.campus_id))[1] earliest
      from c2 c where c.keep2 group by c.provider_id, c.cc),
  dec as (
    select pick.*, case when n2 = 1 then earliest when ncity = 1 and not nocity then earliest end campus_id,
           case when n2 = 1 and any_addr then 'register_head_office_address' when n2 = 1 and any_city then 'registered_city_match'
                when n2 = 1 then null when ncity = 1 and not nocity then 'earliest_registered_campus' end basis
      from pick)
  select coalesce(jsonb_agg(to_jsonb(dec)), '[]'::jsonb) into v_rows from dec;
  select coalesce(jsonb_object_agg(b, n), '{}'::jsonb) into v_by from (select coalesce(x.basis, 'left_unset') b, count(*) n from jsonb_to_recordset(v_rows) x(basis text, campus_id uuid) group by 1) z;
  select coalesce(jsonb_object_agg(cc, n), '{}'::jsonb) into v_left from (select x.cc, count(*) n from jsonb_to_recordset(v_rows) x(cc text, basis text) where x.basis is null group by 1) z;
  if p_apply then
    update catalogue.campuses k set is_primary = true, primary_basis = 'highest_course_count', updated_at = now()
      from jsonb_to_recordset(v_rows) x(provider_id uuid, campus_id uuid, basis text)
     where x.basis is not null and k.id = x.campus_id and k.is_primary is distinct from true
       and not exists (select 1 from catalogue.campuses y where y.provider_id = x.provider_id and y.is_primary);
    get diagnostics v_n = row_count;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('api_v3', 'campus_primary_tiebreak', 'catalogue.campuses.is_primary',
            jsonb_build_object('rule', 's818: tied campuses: registered city, then register head office address, then the earliest registered of co-located campuses',
                               'marked', v_n, 'by_basis', v_by, 'left_unset_by_country', v_left, 'approved', 'Platform Admin 20 Nov 2026 09:55 and 10:48 AEDT',
                               'decisions', (select coalesce(jsonb_agg(jsonb_build_object('provider_id', x.provider_id, 'campus_id', x.campus_id, 'tiebreak', x.basis)), '[]'::jsonb)
                                               from jsonb_to_recordset(v_rows) x(provider_id uuid, campus_id uuid, basis text) where x.basis is not null)), auth.uid());
  end if;
  return jsonb_build_object('applied', p_apply, 'tied_providers', jsonb_array_length(v_rows), 'marked', v_n, 'by_basis', v_by, 'left_unset_by_country', v_left);
end $f$;
revoke all on function security.campus_primary_tiebreak_v1(boolean) from public, anon, authenticated;
comment on function security.campus_primary_tiebreak_v1(boolean) is 'CF-247 s818: main campus for providers whose campuses tie on active courses: registered city, register head office address, then the earliest registered of co-located campuses; the rest stay unset.';

-- 2. NZ and CA courses with no campus, at a provider with exactly one active campus
create or replace function security.course_campus_sole_projection_v1(p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_rows jsonb; v_n int := 0; v_by jsonb;
begin
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('course_id', z.course_id, 'campus_id', z.campus_id, 'cc', z.cc)), '[]'::jsonb) into v_rows from (
    select c.id course_id, (select x.id from catalogue.campuses x where x.provider_id = p.id and x.status = 'active') campus_id, k.iso_alpha2 cc
      from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id and k.iso_alpha2 in ('NZ', 'CA')
     where c.lifecycle_status = 'active' and c.empty_reason_code is distinct from 'online_only_no_campus'
       and not exists (select 1 from catalogue.course_campuses y where y.course_id = c.id)
       and (select count(*) from catalogue.campuses x where x.provider_id = p.id and x.status = 'active') = 1
       and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field in ('campus', 'campuses', 'course_campuses', 'all'))) z;
  select coalesce(jsonb_object_agg(cc, n), '{}'::jsonb) into v_by from (select x.cc, count(*) n from jsonb_to_recordset(v_rows) x(cc text) group by 1) z;
  if p_apply then
    insert into catalogue.course_campuses (course_id, campus_id, is_primary)
    select x.course_id, x.campus_id, true from jsonb_to_recordset(v_rows) x(course_id uuid, campus_id uuid)
     where not exists (select 1 from catalogue.course_campuses y where y.course_id = x.course_id);
    get diagnostics v_n = row_count;
    insert into search.course_refresh_requests (course_id, requested_at, requested_by)
    select x.course_id, now(), 'campus_projection' from jsonb_to_recordset(v_rows) x(course_id uuid);
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('api_v3', 'course_campus_sole_projection', 'catalogue.course_campuses',
            jsonb_build_object('rule', 's818: an NZ or CA course with no campus takes its provider''s only active campus (not online only, not locked)',
                               'linked', v_n, 'by_country', v_by, 'approved', 'Platform Admin 20 Nov 2026 09:55 and 10:48 AEDT'), auth.uid());
  end if;
  return jsonb_build_object('applied', p_apply, 'courses', jsonb_array_length(v_rows), 'linked', v_n, 'by_country', v_by);
end $f$;
revoke all on function security.course_campus_sole_projection_v1(boolean) from public, anon, authenticated;
comment on function security.course_campus_sole_projection_v1(boolean) is 'CF-247 s818: links NZ and CA courses with no campus to their provider''s only active campus (not online only, not locked) and queues their search refresh.';

-- 3. NZ campuses with no region
create or replace function security.campus_nz_region_fill_v1(p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_rows jsonb; v_n int := 0; v_map jsonb := coalesce(security.toolset_setting('pipeline', 'campus.nz_city_regions'), '{}'::jsonb);
begin
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('campus_id', z.id, 'subdivision_id', z.sid, 'code', z.code, 'name', z.name)), '[]'::jsonb) into v_rows from (
    select k.id, k.name, min(s.id::text)::uuid sid, min(s.code) code
      from catalogue.campuses k join ref.countries n on n.id = k.country_id and n.iso_alpha2 = 'NZ'
      cross join lateral (
        select s.id, s.code from ref.subdivisions s where s.country_id = n.id and s.status = 'active' and coalesce(k.name, '') || ' ' || coalesce(k.city, '') ~* ('\m' || s.name || '\M')
        union
        select s.id, s.code from jsonb_each_text(v_map) m(city, code) join ref.subdivisions s on s.code = m.code and s.country_id = n.id
         where coalesce(k.name, '') || ' ' || coalesce(k.city, '') ~* ('\m' || m.city || '\M')) s
     where k.subdivision_id is null
       and not exists (select 1 from pipeline.manual_locks l where l.entity = 'campus' and l.entity_id = k.id and l.field in ('subdivision_id', 'region', 'all'))
     group by k.id, k.name having count(distinct s.id) = 1) z;
  if p_apply then
    update catalogue.campuses k set subdivision_id = x.subdivision_id, updated_at = now()
      from jsonb_to_recordset(v_rows) x(campus_id uuid, subdivision_id uuid) where k.id = x.campus_id and k.subdivision_id is null;
    get diagnostics v_n = row_count;
    insert into search.course_refresh_requests (course_id, requested_at, requested_by)
    select distinct cc.course_id, now(), 'campus_region' from catalogue.course_campuses cc join jsonb_to_recordset(v_rows) x(campus_id uuid) on x.campus_id = cc.campus_id;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('api_v3', 'campus_nz_region_fill', 'catalogue.campuses.subdivision_id', jsonb_build_object('filled', v_n, 'campuses', v_rows), auth.uid());
  end if;
  return jsonb_build_object('applied', p_apply, 'campuses', jsonb_array_length(v_rows), 'filled', v_n);
end $f$;
revoke all on function security.campus_nz_region_fill_v1(boolean) from public, anon, authenticated;
comment on function security.campus_nz_region_fill_v1(boolean) is 'CF-247 s818: NZ campuses with no region take the one region their name names (a region name or a city in campus.nz_city_regions).';

-- Catalogue › Providers: the Main campus filter (set, unset: has active campuses and none is the main one, none: no active campus)
create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;
select pg_temp.cf_edit_def('security.admin_providers_page_v3(jsonb)'::regprocedure, '2f525d0c17ce5505b92f0e34fd4a2d4e',
  array[$o$  v_type text:=nullif(trim(coalesce(p_args->>'provider_type','')),'');$o$,
        $o$  if v_type is not null and v_type<>'unclassified' and not exists (select 1 from ref.provider_types pt where pt.code=v_type) then raise exception 'unsupported provider type filter: %',v_type using errcode='22023'; end if;$o$,
        $o$        and (v_type is null or (v_type='unclassified' and p.provider_type_id is null) or p.provider_type_id=(select pt.id from ref.provider_types pt where pt.code=v_type))$o$],
  array[$n$  v_type text:=nullif(trim(coalesce(p_args->>'provider_type','')),'');
  v_primary text:=nullif(lower(trim(coalesce(p_args->>'primary_campus',''))),'');  -- s818: Main campus filter$n$,
        $n$  if v_type is not null and v_type<>'unclassified' and not exists (select 1 from ref.provider_types pt where pt.code=v_type) then raise exception 'unsupported provider type filter: %',v_type using errcode='22023'; end if;
  if v_primary is not null and v_primary not in ('set','unset','none') then raise exception 'unsupported main campus filter: %',v_primary using errcode='22023'; end if;$n$,
        $n$        and (v_type is null or (v_type='unclassified' and p.provider_type_id is null) or p.provider_type_id=(select pt.id from ref.provider_types pt where pt.code=v_type))
        and (v_primary is null
             or (v_primary='set' and exists (select 1 from catalogue.campuses cp where cp.provider_id=p.id and cp.is_primary))
             or (v_primary='unset' and exists (select 1 from catalogue.campuses cp where cp.provider_id=p.id and cp.status='active')
                 and not exists (select 1 from catalogue.campuses cp where cp.provider_id=p.id and cp.is_primary))
             or (v_primary='none' and not exists (select 1 from catalogue.campuses cp where cp.provider_id=p.id and cp.status='active')))$n$]);

-- apply, and check
do $$
declare t jsonb; pj jsonb; nz jsonb; v_multi int; v_before int; v_after int; v_admin uuid; v_set int; v_unset int; v_none int;
begin
  select count(*) into v_before from catalogue.campuses where is_primary;
  t := security.campus_primary_tiebreak_v1(true);
  select count(*) into v_after from catalogue.campuses where is_primary;
  if v_after - v_before <> (t->>'marked')::int then raise exception 'post-check: main campuses moved by % but the tie-break marked %', v_after - v_before, t->>'marked'; end if;
  select count(*) into v_multi from (select provider_id from catalogue.campuses where is_primary group by 1 having count(*) > 1) z;
  if v_multi > 0 then raise exception 'post-check: % providers have more than one main campus', v_multi; end if;
  pj := security.course_campus_sole_projection_v1(true);
  if (pj->>'linked')::int <> (pj->>'courses')::int then raise exception 'post-check: projection linked % of % courses', pj->>'linked', pj->>'courses'; end if;
  if exists (select 1 from catalogue.course_campuses cc join catalogue.courses c on c.id = cc.course_id where c.empty_reason_code = 'online_only_no_campus'
              and exists (select 1 from pipeline.admin_control_events e where e.action = 'course_campus_sole_projection' and e.created_at = now())) then null; end if;
  nz := security.campus_nz_region_fill_v1(true);
  -- the filter, as a signed-in Platform Admin
  select ur.user_id into v_admin from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ro.status = 'active' and ro.rank >= 6 and (ur.expires_at is null or ur.expires_at > now()) order by ur.user_id limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  v_set := (security.admin_providers_page_v3(jsonb_build_object('primary_campus', 'set', 'limit', 1))->>'total')::int;
  v_unset := (security.admin_providers_page_v3(jsonb_build_object('primary_campus', 'unset', 'limit', 1))->>'total')::int;
  v_none := (security.admin_providers_page_v3(jsonb_build_object('primary_campus', 'none', 'limit', 1))->>'total')::int;
  perform set_config('request.jwt.claims', '', true);
  if v_set is null or v_unset is null then raise exception 'post-check: the Main campus filter returned no total'; end if;
  perform set_config('cf.diag', 'tie-break ' || t::text || ' | sole campus ' || pj::text || ' | NZ regions ' || nz::text
    || ' | filter: set ' || v_set || ', unset ' || v_unset || ', none ' || v_none
    || ' | NZ docs with no region (before refresh) ' || (select count(*) from search.course_documents d join catalogue.courses c on c.id = d.course_id join catalogue.providers p on p.id = c.provider_id
           join ref.countries k on k.id = p.country_id where k.iso_alpha2 = 'NZ' and c.lifecycle_status = 'active' and coalesce(cardinality(d.subdivision_codes), 0) = 0), true);
end $$;
