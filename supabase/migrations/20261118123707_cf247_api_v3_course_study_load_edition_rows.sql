-- CF-247 S1-RM-Design (Platform Admin 18 Nov 2026 10:33 and 10:34): API v3 course and search actions return study_load, empty_reason_code,
-- campuses[].locality and provider.accreditations; the provider action returns accreditations; Publish edition counts a city profiles edition's
-- localities (ref G7QN3W).
--
--   * security.course_v3_fields_v1(item, course) (new) adds to a v3 course item, read from catalogue.courses: study_load (full_time, part_time, both;
--     null until read, REQ-52) and empty_reason_code (why sparse fields are null, REQ-53); on each campus the approved locality its postcode maps to
--     (security.destination_locality_for_postcode_v1, the provider action's G-5 reading, REQ-67); on the provider object the active accreditations
--     (REQ-57). public.website_v3_course_item_r28 calls it, so every v3 course item carries the fields: Website v3 course and search, Zoho v3 course,
--     courses and search, and the v3 sync. Additive only: no field is removed, renamed or retyped.
--   * security.provider_accreditations_v3_v1(provider) (new): active accreditations whose expiry has not passed (AACSB, EQUIS, AMBA); [] when none.
--     public.website_v3_provider_item adds them as item.accreditations.
--   * security.destination_edition_rows_v1(edition) (new): the rows of an edition. A city profiles edition holds its city profile rows plus the
--     localities its load wrote (destination.localities matched by country and dataset_edition = edition label), with their figures counted beside.
--     The ABS population load writes localities and figures, never city_profiles, so the edition showed 0 rows and Publish edition refused it.
--     security.destination_edition_publish_v1 now needs one approved locality (or profile) for a city profiles edition; other domains are unchanged.
--     public.admin_destination_overview shows the same rows, rows approved and figures.
--   The website and Zoho v2 surfaces and every frozen consumer function are untouched (G3): website_v3_* and zoho_v3_* are not in the frozen
--   surface until v3 go-live (Decision 277). G1: no job. G2: no setting (the counts and lookups take no limit).
--
-- Live definitions this change edits (pg_proc.prosrc md5, read 18 Nov 2026 10:40 AEDT), before -> after (the migration stops, and applies nothing, if a live body is neither):
--   public.website_v3_course_item_r28(jsonb)  9ab945d33bc151a1938f829ba5115a10 -> f6ab5e7ad36d85397ae4c62632fc675d
--   public.website_v3_provider_item(jsonb)  c9b229a12069c3e1fc4382813e51cb25 -> 9fa6d618d17b0d182495efc050943f79
--   security.destination_edition_publish_v1(uuid,uuid)  bf92970cafb4fab36383ec399ef530a9 -> 79cad4f1d0fcdf086020be381dd25961
--   public.admin_destination_overview()  4d450f28bc9ac7c61961a337225ff486 -> 67d73e7ac1e849e40edb715d27dcd484
-- Replaces: the four bodies above, in place (md5-guarded edits)
-- Retires: nothing

set local lock_timeout = '5s'; -- fixed: lock wait guard for the function replacements below

do $pre$ begin
  if to_regprocedure('security.destination_locality_for_postcode_v1(text,text)') is null then raise exception 'security.destination_locality_for_postcode_v1 is missing'; end if;
  if to_regclass('catalogue.provider_accreditations') is null then raise exception 'catalogue.provider_accreditations is missing'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'catalogue' and table_name = 'courses' and column_name = 'study_load')
     or not exists (select 1 from information_schema.columns where table_schema = 'catalogue' and table_name = 'courses' and column_name = 'empty_reason_code') then
    raise exception 'catalogue.courses.study_load or empty_reason_code is missing';
  end if;
end $pre$;

create or replace function security.provider_accreditations_v3_v1(p_provider uuid) returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('body_code', a.body_code, 'accredited_unit_name', a.accredited_unit_name, 'accredited_since', a.accredited_since,
                                                'expires_at', a.expires_at, 'source_url', a.source_url, 'verified_at', a.verified_at)
                            order by a.body_code, a.accredited_unit_name nulls first, a.id), '[]'::jsonb)
    from catalogue.provider_accreditations a
   where a.provider_id = p_provider and a.status = 'active' and (a.expires_at is null or a.expires_at >= current_date)
$f$;
comment on function security.provider_accreditations_v3_v1(uuid) is 'CF-247 API v3 (REQ-57, 18 Nov 2026): a provider''s active business school accreditations, as the v3 course and provider actions return them; [] when none';
revoke all on function security.provider_accreditations_v3_v1(uuid) from public, anon, authenticated;

create or replace function security.course_v3_fields_v1(p_item jsonb, p_course uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_load text; v_reason text; v_provider uuid; v_cc text;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' then return p_item; end if;
  select c.study_load, c.empty_reason_code, c.provider_id into v_load, v_reason, v_provider from catalogue.courses c where c.id = p_course;
  v_cc := upper(nullif(btrim(coalesce(p_item->>'country_code', '')), ''));
  if jsonb_typeof(p_item->'campuses') = 'array' then
    p_item := jsonb_set(p_item, '{campuses}', (select coalesce(jsonb_agg(case when jsonb_typeof(k) = 'object' then k || jsonb_build_object('locality',
                  case when v_cc is not null and nullif(btrim(coalesce(k->>'postcode', '')), '') is not null then security.destination_locality_for_postcode_v1(v_cc, k->>'postcode') end)
                  else k end order by o), '[]'::jsonb) from jsonb_array_elements(p_item->'campuses') with ordinality t(k, o)));
  end if;
  if jsonb_typeof(p_item->'provider') = 'object' then
    p_item := jsonb_set(p_item, '{provider,accreditations}', security.provider_accreditations_v3_v1(v_provider));
  end if;
  return p_item || jsonb_build_object('study_load', v_load, 'empty_reason_code', v_reason);
end $f$;
comment on function security.course_v3_fields_v1(jsonb, uuid) is 'CF-247 API v3 (18 Nov 2026): adds study_load (REQ-52), empty_reason_code (REQ-53), campuses[].locality (REQ-67) and provider.accreditations (REQ-57) to a v3 course item; called by public.website_v3_course_item_r28';
revoke all on function security.course_v3_fields_v1(jsonb, uuid) from public, anon, authenticated;

create or replace function security.destination_edition_rows_v1(p_edition uuid) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare e destination.editions%rowtype; v_cc text; v_prof int := 0; v_loc int := 0; v_loc_ok int := 0; v_fig int := 0; v_fig_ok int := 0; v_rows int; v_ok int;
begin
  select * into e from destination.editions x where x.id = p_edition;
  if not found then return null; end if;
  select c.iso_alpha2 into v_cc from ref.countries c where c.id = e.country_id;
  if e.domain = 'study_rules' then
    select count(*), count(*) filter (where r.approval_status = 'approved') into v_rows, v_ok from destination.study_rules r where r.edition_id = e.id;
  elsif e.domain = 'career_outcomes' then
    select count(*), count(*) filter (where o.status in ('approved', 'published')) into v_rows, v_ok from destination.career_outcomes o where o.edition_id = e.id;
  else
    select count(*) into v_prof from destination.city_profiles p where p.edition_id = e.id;
    select count(*), count(*) filter (where l.status in ('approved', 'published')) into v_loc, v_loc_ok
      from destination.localities l where l.country_code = v_cc and l.dataset_edition = e.edition_label;
    -- a figure is returned by the API only when it and its locality are approved or published
    select count(*), count(*) filter (where m.status in ('approved', 'published') and l.status in ('approved', 'published')) into v_fig, v_fig_ok
      from destination.locality_metrics m join destination.localities l on l.id = m.locality_id
     where l.country_code = v_cc and m.dataset_edition = e.edition_label;
    v_rows := v_prof + v_loc; v_ok := v_prof + v_loc_ok;
  end if;
  return jsonb_build_object('edition_id', e.id, 'domain', e.domain, 'rows', v_rows, 'rows_approved', v_ok,
           'city_profiles', case when e.domain = 'city_profiles' then v_prof end,
           'localities', case when e.domain = 'city_profiles' then jsonb_build_object('held', v_loc, 'approved', v_loc_ok) end,
           'figures', case when e.domain = 'city_profiles' then jsonb_build_object('held', v_fig, 'approved', v_fig_ok) end);
end $f$;
comment on function security.destination_edition_rows_v1(uuid) is 'CF-247 Destination data (ref G7QN3W, 18 Nov 2026): an edition''s rows and approved rows; a city profiles edition counts its city profiles plus the localities its load wrote (country and dataset_edition = edition label), with their figures beside';
revoke all on function security.destination_edition_rows_v1(uuid) from public, anon, authenticated;

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

select pg_temp.edit_all('public.website_v3_course_item_r28(jsonb)', '9ab945d33bc151a1938f829ba5115a10', 'f6ab5e7ad36d85397ae4c62632fc675d',
  array[$o0$  if p_item is null or jsonb_typeof(p_item) <> 'object' or jsonb_typeof(p_item->'intakes') is distinct from 'array' then return p_item; end if;
  select d.course_id into v_course from search.course_documents d
   where lower(d.course_stable_key) = lower(p_item->>'course_id') and d.course_stable_key is not null limit 1;
$o0$,
        $o1$  return jsonb_set(p_item, '{intakes}', v_out);$o1$],
  array[$n0$  if p_item is null or jsonb_typeof(p_item) <> 'object' then return p_item; end if;
  select d.course_id into v_course from search.course_documents d
   where lower(d.course_stable_key) = lower(p_item->>'course_id') and d.course_stable_key is not null limit 1;
  -- 18 Nov 2026 (S1-RM-Design): study_load, empty_reason_code, campuses[].locality and provider.accreditations on every v3 course item
  if jsonb_typeof(p_item->'intakes') is distinct from 'array' then return security.course_v3_fields_v1(p_item, v_course); end if;
$n0$,
        $n1$  return security.course_v3_fields_v1(jsonb_set(p_item, '{intakes}', v_out), v_course);$n1$]);

select pg_temp.edit_all('public.website_v3_provider_item(jsonb)', 'c9b229a12069c3e1fc4382813e51cb25', '9fa6d618d17b0d182495efc050943f79',
  array[$o0$'scholarships_last_reviewed_at', v_page.read_at);$o0$],
  array[$n0$'scholarships_last_reviewed_at', v_page.read_at,
                               'accreditations', security.provider_accreditations_v3_v1(v_provider));  -- 18 Nov 2026 (REQ-57)$n0$]);

select pg_temp.edit_all('security.destination_edition_publish_v1(uuid,uuid)', 'bf92970cafb4fab36383ec399ef530a9', '79cad4f1d0fcdf086020be381dd25961',
  array[$o0$  v_rows := case v.domain
    when 'study_rules' then (select count(*) from destination.study_rules r where r.edition_id = v.id)
    when 'city_profiles' then (select count(*) from destination.city_profiles r where r.edition_id = v.id)
    else (select count(*) from destination.career_outcomes r where r.edition_id = v.id) end;
  if v_rows = 0 then raise exception using errcode = '22023', message = 'INVALID_INPUT: an edition with no rows cannot be published'; end if;$o0$],
  array[$n0$  -- 18 Nov 2026 (ref G7QN3W): a city profiles edition also counts the localities its load wrote (matched by country and edition name); it needs an approved one
  v_rows := case v.domain when 'city_profiles' then (security.destination_edition_rows_v1(v.id)->>'rows_approved')::int
    when 'study_rules' then (select count(*) from destination.study_rules r where r.edition_id = v.id)
    else (select count(*) from destination.career_outcomes r where r.edition_id = v.id) end;
  if v_rows = 0 and v.domain = 'city_profiles' then raise exception using errcode = '22023', message = 'INVALID_INPUT: an edition with no approved rows cannot be published. Approve its localities first'; end if;
  if v_rows = 0 then raise exception using errcode = '22023', message = 'INVALID_INPUT: an edition with no rows cannot be published'; end if;$n0$]);

select pg_temp.edit_all('public.admin_destination_overview()', '4d450f28bc9ac7c61961a337225ff486', '67d73e7ac1e849e40edb715d27dcd484',
  array[$o0$                                               else (select count(*) from destination.city_profiles p where p.edition_id = e.id) end,$o0$,
        $o1$                                               when 'career_outcomes' then (select count(*) from destination.career_outcomes o where o.edition_id = e.id and o.status in ('approved', 'published')) end)$o1$],
  array[$n0$                                               else (security.destination_edition_rows_v1(e.id)->>'rows')::int end,$n0$,
        $n1$                                               when 'career_outcomes' then (select count(*) from destination.career_outcomes o where o.edition_id = e.id and o.status in ('approved', 'published'))
                                               else (security.destination_edition_rows_v1(e.id)->>'rows_approved')::int end,
                         'figures', case when e.domain = 'city_profiles' then security.destination_edition_rows_v1(e.id)->'figures' end)$n1$]);

do $post$ declare v jsonb; begin
  if md5((select prosrc from pg_proc where oid = 'public.website_v3_course_item_r28(jsonb)'::regprocedure)) <> 'f6ab5e7ad36d85397ae4c62632fc675d' then raise exception 'post-check: r28 body'; end if;
  if (select prosrc from pg_proc where oid = 'security.destination_edition_publish_v1(uuid,uuid)'::regprocedure) !~ 'destination_edition_rows_v1' then raise exception 'post-check: publish'; end if;
  v := security.course_v3_fields_v1('{"course_id":"x","country_code":"AU","campuses":[{"city":"A","postcode":null}],"provider":{"provider_id":"p"}}'::jsonb, null);
  if not (v ? 'study_load' and v ? 'empty_reason_code' and v->'campuses'->0 ? 'locality' and jsonb_typeof(v->'provider'->'accreditations') = 'array') then
    raise exception 'post-check: course_v3_fields_v1 gave %', v;
  end if;
end $post$;
