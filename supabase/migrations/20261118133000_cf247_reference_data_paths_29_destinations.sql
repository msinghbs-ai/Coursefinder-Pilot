-- CF-247 29-destination readiness (S2-Build, Platform Admin 18 Nov 2026 11:28: "after Thursday's canonical migration squash, onboarding all 29
-- destinations requires only data/seed ingestion and Layer 1 source configuration, never new schema migrations").
--
-- Read-only cross-check, live 18 Nov 2026 11:40 AEDT (recorded in admin docs/CURRENT-STATE.md):
--   * All 28 country codes named (AU, CA, GB for "UK", NZ, IE, US, DE, SE, FI, DK, ES, MT, NL, FR, AT, CH, HU, LV, AE, SG, PL, IT, GR, CY, TH, MY,
--     KR, JP) are in ref.countries; destination.localities, locality_metrics, study_rules, rule_applicability, career_outcomes and editions take
--     any country (upper-case code or a ref.countries key); catalogue.provider_accreditations and the ranking tables are country-agnostic.
--   * Two gaps need a data path, not a schema change, and are closed here:
--       - ref.registration_schemes: 22 of the 28 countries have no scheme, and the induction wizard refuses a source whose scheme is not
--         registered ("register it in ref.registration_schemes first"); no function wrote that table, so a new country needed a migration.
--       - ref.subdivisions: 25 of the 28 countries have none (state names on register rows stay unmapped); no function wrote that table.
--   * Three CHECK constraints reject valid values for other destinations (career_outcomes.occupation_scheme, career_outcomes.state_code,
--     study_rules.rule_category). Relaxing a CHECK drops and re-adds it, so it goes to the Platform Admin as a paste file
--     (admin docs/paste/PASTE-20261118-29-destination-check-constraints.sql), to be run before Thursday's 01:15 AEDT freeze.
--
-- What it adds
--   * public.admin_registration_scheme_register_v1(p_args): a Platform Admin registers a country's scheme as data, with a reason; it is added as
--     planned and an existing scheme is never changed. Layer 1 › Register › + Add source, step 1, offers it.
--   * public.admin_subdivisions_register_v1(p_country_code, p_rows, p_reason): a Platform Admin loads a country's ISO 3166-2 subdivisions as data;
--     an existing code is never changed.
-- Nothing is dropped, deleted or overwritten. G3 untouched.
-- Replaces: nothing (registration schemes and subdivisions had no data path).
-- Retires: nothing.

create or replace function public.admin_registration_scheme_register_v1(p_args jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare a jsonb := coalesce(p_args, '{}'::jsonb); v_scheme text := lower(btrim(coalesce(a->>'scheme', ''))); v_kind text := btrim(coalesce(a->>'kind', ''));
        v_cc text := upper(btrim(coalesce(a->>'country_code', ''))); v_label text := btrim(coalesce(a->>'label', '')); v_auth text := btrim(coalesce(a->>'authority', ''));
        v_reason text := btrim(coalesce(a->>'reason', '')); v_never text[]; v_created boolean := false;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) registers a scheme' using errcode = '42501'; end if; -- fixed: reference data is the Platform Admin's
  if length(v_reason) < 4 then raise exception 'a reason is required' using errcode = '22023'; end if;
  if v_scheme !~ '^[a-z][a-z0-9_]{1,39}$' then raise exception 'scheme code: lower-case letters, digits and _ (2 to 40), starting with a letter' using errcode = '22023'; end if; -- fixed: input-safety bound
  if v_kind not in ('course_registration', 'provider_registration', 'field_of_study', 'work_eligibility') then raise exception 'kind % is not a scheme kind', v_kind using errcode = '22023'; end if;
  if not exists (select 1 from ref.countries c where c.iso_alpha2 = v_cc) then raise exception 'country % is not in ref.countries', v_cc using errcode = '22023'; end if;
  if length(v_label) < 2 or length(v_label) > 120 or length(v_auth) < 2 or length(v_auth) > 160 then raise exception 'a label and an authority are required' using errcode = '22023'; end if; -- fixed: input-safety bound
  v_never := coalesce(array(select lower(btrim(x)) from jsonb_array_elements_text(case when jsonb_typeof(a->'never_mixed_with') = 'array' then a->'never_mixed_with' else '[]'::jsonb end) x where btrim(x) <> ''), '{}');
  insert into ref.registration_schemes(scheme, kind, country_code, authority, label, never_mixed_with, status)
  values (v_scheme, v_kind, v_cc, v_auth, v_label, v_never, 'planned')
  on conflict (scheme, kind, country_code) do nothing;
  v_created := found;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer1', 'scheme_register', v_cc || ':' || v_scheme || ':' || v_kind,
          jsonb_build_object('created', v_created, 'label', v_label, 'authority', v_auth, 'reason', left(v_reason, 300)), auth.uid());
  return jsonb_build_object('ok', true, 'created', v_created, 'scheme', v_scheme, 'kind', v_kind, 'country_code', v_cc,
                            'status', (select s.status from ref.registration_schemes s where s.scheme = v_scheme and s.kind = v_kind and s.country_code = v_cc));
end $function$;
comment on function public.admin_registration_scheme_register_v1(jsonb) is 'CF-247 (18 Nov 2026): a Platform Admin registers a country''s registration scheme as data (added as planned; an existing scheme is never changed; logged). Layer 1 induction wizard step 1.';
revoke all on function public.admin_registration_scheme_register_v1(jsonb) from public, anon;
grant execute on function public.admin_registration_scheme_register_v1(jsonb) to authenticated;

create or replace function public.admin_subdivisions_register_v1(p_country_code text, p_rows jsonb, p_reason text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_cc text := upper(btrim(coalesce(p_country_code, ''))); v_country uuid; r jsonb; v_code text; v_name text; v_added int := 0; v_existing int := 0; v_invalid int := 0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) loads subdivisions' using errcode = '42501'; end if; -- fixed: reference data is the Platform Admin's
  if length(btrim(coalesce(p_reason, ''))) < 4 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select id into v_country from ref.countries where iso_alpha2 = v_cc;
  if v_country is null then raise exception 'country % is not in ref.countries', v_cc using errcode = '22023'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 500 then raise exception 'rows: an array of at most 500 subdivisions' using errcode = '22023'; end if; -- fixed: input-safety bound
  for r in select value from jsonb_array_elements(p_rows) loop
    v_code := upper(btrim(coalesce(r->>'code', ''))); v_name := btrim(coalesce(r->>'name', ''));
    if v_code !~ ('^' || v_cc || '-[A-Z0-9]{1,3}$') or length(v_name) < 1 or length(v_name) > 120 then v_invalid := v_invalid + 1; continue; end if; -- fixed: ISO 3166-2 shape
    insert into ref.subdivisions(country_id, code, name, subdivision_type, status)
    values (v_country, v_code, v_name, nullif(btrim(coalesce(r->>'subdivision_type', '')), ''), 'active')
    on conflict (code) do nothing;
    if found then v_added := v_added + 1; else v_existing := v_existing + 1; end if;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('reference', 'subdivisions_register', v_cc, jsonb_build_object('added', v_added, 'existing', v_existing, 'invalid', v_invalid, 'reason', left(btrim(p_reason), 300)), auth.uid());
  return jsonb_build_object('ok', true, 'country_code', v_cc, 'added', v_added, 'existing', v_existing, 'invalid', v_invalid);
end $function$;
comment on function public.admin_subdivisions_register_v1(text, jsonb, text) is 'CF-247 (18 Nov 2026): a Platform Admin loads a country''s ISO 3166-2 subdivisions as data (an existing code is never changed; logged).';
revoke all on function public.admin_subdivisions_register_v1(text, jsonb, text) from public, anon;
grant execute on function public.admin_subdivisions_register_v1(text, jsonb, text) to authenticated;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, introduced_in)
select v.kind, v.name, 'Reference', 'Layer 1 register', v.purpose, 'active', '20261118133000'
  from (values
    ('function', 'public.admin_registration_scheme_register_v1', 'Platform Admin registers a country''s registration scheme as data (planned; never changes an existing one)'),
    ('function', 'public.admin_subdivisions_register_v1', 'Platform Admin loads a country''s ISO 3166-2 subdivisions as data')) v(kind, name, purpose)
 where not exists (select 1 from pipeline.component_register r where r.kind = v.kind and r.name = v.name);

do $$
begin
  if (select count(*) from ref.countries where iso_alpha2 in ('AU','CA','GB','NZ','IE','US','DE','SE','FI','DK','ES','MT','NL','FR','AT','CH','HU','LV','AE','SG','PL','IT','GR','CY','TH','MY','KR','JP')) <> 28 then -- fixed: the named destinations
    raise exception 'post-check: a named destination is missing from ref.countries';
  end if;
  if to_regprocedure('public.admin_registration_scheme_register_v1(jsonb)') is null or to_regprocedure('public.admin_subdivisions_register_v1(text,jsonb,text)') is null then
    raise exception 'post-check: data paths';
  end if;
end $$;
