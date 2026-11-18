-- CF-247 Layer 1 induction: the API v3 fields and baseline records for a new country source (S2-Build, Platform Admin 18 Nov 2026 10:31: "Ensure the
-- Layer 1 induction backend (layer1-ai-induction-mapper and induction RPCs) supports all newly added API v3 fields (study_load, empty_reason_code,
-- provider_accreditations, campuses.is_primary, grade_scale_conversions) and allows creating/seeding new baseline records when onboarding a new
-- country source").
--
-- What it changes
--   * security.layer1_parser_targets_v1 (md5-guarded; the live expression is kept and extended): course_register gains study_load and
--     empty_reason_code; three new record types: provider_accreditations (catalogue.provider_accreditations), campuses (catalogue.campuses, with
--     is_primary) and grade_scale_conversions (ref.grade_scale_conversions). The AI induction mapper reads its targets from here
--     (svc_layer1_parser_spec_validate_v1), so it maps the new fields with no change of its own.
--   * security.layer1_record_types_v1 (md5-guarded, extended): the three record types with labels for the wizard's step 3.
--   * public.svc_layer1_apply_baseline_records_v1: the apply step of the three new record types and of the two new course fields, called by
--     layer1-declarative-runner v1.1.0 in an apply run (source activated by the Platform Admin, not paused, terms approved; unchanged gates).
--     A new country's providers and courses are already created by public.svc_layer1_apply_register_records (country seed in ref.countries:
--     249 rows); this adds, beside them:
--       - study_load (full_time, part_time, both) and empty_reason_code on a course only where the course holds none (a person's value or a
--         provider-page reading is never overwritten), study_load_source 'register', with the run's evidence;
--       - a campus of a registered provider where the provider has no campus of that name (stable key campus:<scheme>:<provider>:<name>); it is
--         the primary campus only when the record says so and the provider has no primary campus yet;
--       - an accreditation (AACSB, EQUIS, AMBA) of a registered provider where the provider has none from that body; an existing row is not changed;
--       - a grade scale conversion of the source's country as INACTIVE (is_active false) until a person reviews it.
--     Nothing is published, overwritten, dropped or deleted. A record whose provider is not registered for the scheme is counted, not invented.
-- G3 untouched (no consumer API object changes). G2: no operational value is added.
-- Replaces: nothing (the three record types and two course fields had no Layer 1 path).
-- Retires: nothing.

-- 1. parser targets
do $e$
declare
  v_sig constant regprocedure := 'security.layer1_parser_targets_v1()'::regprocedure;
  v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.layer1_parser_targets_v1()'::regprocedure);
  v_expr text;
begin
  if position('grade_scale_conversions' in v_src) > 0 then raise notice 'security.layer1_parser_targets_v1: already applied'; return; end if;
  if md5(v_src) <> '1460dc3b35db43c51d77b1d6d912c215' then raise exception 'live security.layer1_parser_targets_v1 differs from the definition this change extends (body md5 %)', md5(v_src); end if;
  v_expr := regexp_replace(v_src, '^\s*select\s+', '', 'i');
  if v_expr = v_src then raise exception 'security.layer1_parser_targets_v1: expected a single select expression'; end if;
  execute format($f$create or replace function security.layer1_parser_targets_v1() returns jsonb language sql immutable set search_path to '' as $b$
  select jsonb_set(jsonb_set(base, '{course_register,fields,study_load}', jsonb_build_object('type', 'text')),
                   '{course_register,fields,empty_reason_code}', jsonb_build_object('type', 'code'))
    || jsonb_build_object(
    'provider_accreditations', jsonb_build_object('target_table', 'catalogue.provider_accreditations', 'apply', 'public.svc_layer1_apply_baseline_records_v1',
      'key', jsonb_build_array('provider_code', 'body_code'),
      'fields', jsonb_build_object(
        'provider_code', jsonb_build_object('type', 'code', 'required', true), 'provider_name', jsonb_build_object('type', 'text'),
        'body_code', jsonb_build_object('type', 'code', 'required', true), 'accredited_unit_name', jsonb_build_object('type', 'text'),
        'status', jsonb_build_object('type', 'text'), 'accredited_since', jsonb_build_object('type', 'date'), 'expires_at', jsonb_build_object('type', 'date'),
        'source_url', jsonb_build_object('type', 'url', 'required', true))),
    'campuses', jsonb_build_object('target_table', 'catalogue.campuses', 'apply', 'public.svc_layer1_apply_baseline_records_v1',
      'key', jsonb_build_array('provider_code', 'campus_name'),
      'fields', jsonb_build_object(
        'provider_code', jsonb_build_object('type', 'code', 'required', true), 'provider_name', jsonb_build_object('type', 'text'),
        'campus_name', jsonb_build_object('type', 'text', 'required', true), 'campus_code', jsonb_build_object('type', 'code'),
        'address_line1', jsonb_build_object('type', 'text'), 'address_line2', jsonb_build_object('type', 'text'), 'city', jsonb_build_object('type', 'text'),
        'state', jsonb_build_object('type', 'text'), 'postcode', jsonb_build_object('type', 'code'), 'website', jsonb_build_object('type', 'url'),
        'is_primary', jsonb_build_object('type', 'boolean'))),
    'grade_scale_conversions', jsonb_build_object('target_table', 'ref.grade_scale_conversions', 'apply', 'public.svc_layer1_apply_baseline_records_v1',
      'key', jsonb_build_array('qualification_code', 'scale_code', 'raw_grade_label', 'raw_min_value'),
      'fields', jsonb_build_object(
        'qualification_code', jsonb_build_object('type', 'code', 'required', true), 'qualification_name', jsonb_build_object('type', 'text'),
        'board_or_stream', jsonb_build_object('type', 'text'), 'scale_code', jsonb_build_object('type', 'code', 'required', true),
        'raw_min_value', jsonb_build_object('type', 'numeric'), 'raw_max_value', jsonb_build_object('type', 'numeric'),
        'raw_grade_label', jsonb_build_object('type', 'text'), 'normalized_0_100', jsonb_build_object('type', 'numeric', 'required', true),
        'source_url', jsonb_build_object('type', 'url', 'required', true))))
    from (select %s as base) b
$b$$f$, v_expr);
end $e$;

-- 2. record types for the wizard
do $e$
declare
  v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.layer1_record_types_v1()'::regprocedure);
  v_expr text;
begin
  if position('grade_scale_conversions' in v_src) > 0 then raise notice 'security.layer1_record_types_v1: already applied'; return; end if;
  if md5(v_src) <> 'ea669f7005430039e17316c7111c5697' then raise exception 'live security.layer1_record_types_v1 differs from the definition this change extends (body md5 %)', md5(v_src); end if;
  v_expr := regexp_replace(v_src, '^\s*select\s+', '', 'i');
  if v_expr = v_src then raise exception 'security.layer1_record_types_v1: expected a single select expression'; end if;
  execute format($f$create or replace function security.layer1_record_types_v1() returns jsonb language sql immutable set search_path to '' as $b$
  select (%s) || jsonb_build_array(
    jsonb_build_object('key', 'provider_accreditations', 'label', 'Provider accreditations', 'help', 'Business school accreditations (AACSB, EQUIS, AMBA) of registered providers.'),
    jsonb_build_object('key', 'campuses', 'label', 'Campuses', 'help', 'Campuses of registered providers, with the primary campus where the source names it.'),
    jsonb_build_object('key', 'grade_scale_conversions', 'label', 'Grade scale conversions', 'help', 'How a country''s school or university grades convert to a 0 to 100 scale; loaded inactive for review.'))
$b$$f$, v_expr);
end $e$;

-- 3. the apply step of the new record types and course fields
create or replace function public.svc_layer1_apply_baseline_records_v1(p_record_type text, p_country_code text, p_source_id uuid, p_evidence_id uuid,
                                                                      p_registration_scheme text, p_records jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare r jsonb; v_country uuid; v_scheme text := lower(nullif(btrim(coalesce(p_registration_scheme, '')), '')); v_provider uuid; v_course uuid;
        v_pcode text; v_ccode text; v_name text; v_val text; v_body text; v_status text; v_primary boolean; v_sub uuid;
        c_written int := 0; c_existing int := 0; c_no_provider int := 0; c_no_course int := 0; c_invalid int := 0; c_primary int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_record_type not in ('course_register', 'provider_accreditations', 'campuses', 'grade_scale_conversions') then
    raise exception 'record type % has no baseline apply step', p_record_type using errcode = '22023';
  end if;
  select id into v_country from ref.countries where upper(iso_alpha2::text) = upper(btrim(coalesce(p_country_code, '')));
  if v_country is null then raise exception 'country seed missing: %', p_country_code; end if;
  if p_record_type <> 'grade_scale_conversions' and v_scheme is null then raise exception 'registration scheme required'; end if;
  for r in select value from jsonb_array_elements(coalesce(p_records, '[]'::jsonb)) loop
    v_provider := null; v_course := null;
    if p_record_type <> 'grade_scale_conversions' then
      v_pcode := upper(nullif(btrim(r->>'provider_code'), ''));
      select pr.provider_id into v_provider from catalogue.provider_registrations pr join catalogue.providers p on p.id = pr.provider_id
       where p.country_id = v_country and lower(pr.registration_scheme) = v_scheme and upper(pr.registration_code) = v_pcode
       order by pr.checked_at desc nulls last, pr.id limit 1;
      if v_provider is null then c_no_provider := c_no_provider + 1; continue; end if;
    end if;

    if p_record_type = 'course_register' then
      v_ccode := upper(nullif(btrim(r->>'course_code'), ''));
      select cr.course_id into v_course from catalogue.course_registrations cr join catalogue.courses c on c.id = cr.course_id
       where c.provider_id = v_provider and lower(cr.scheme) = v_scheme and upper(cr.registration_code) = v_ccode order by cr.id limit 1;
      if v_course is null then c_no_course := c_no_course + 1; continue; end if;
      v_val := case regexp_replace(lower(coalesce(r->>'study_load', '')), '[^a-z]+', '', 'g')
                 when 'fulltime' then 'full_time' when 'ft' then 'full_time' when 'parttime' then 'part_time' when 'pt' then 'part_time'
                 when 'both' then 'both' when 'fulltimeorparttime' then 'both' when 'fulltimeandparttime' then 'both' when 'fulltimeparttime' then 'both' end;
      if v_val is not null then
        update catalogue.courses set study_load = v_val, study_load_source = 'register', study_load_evidence_id = p_evidence_id, updated_at = now()
         where id = v_course and study_load is null;
        if found then c_written := c_written + 1; else c_existing := c_existing + 1; end if;
      elsif nullif(btrim(coalesce(r->>'study_load', '')), '') is not null then c_invalid := c_invalid + 1;
      end if;
      v_val := lower(nullif(btrim(coalesce(r->>'empty_reason_code', '')), ''));
      if v_val is not null then
        if v_val in ('not_published_by_provider', 'not_listed_on_register', 'online_only_no_campus', 'pending_extraction', 'source_unavailable') then
          update catalogue.courses set empty_reason_code = v_val, updated_at = now() where id = v_course and empty_reason_code is null;
          if found then c_written := c_written + 1; else c_existing := c_existing + 1; end if;
        else c_invalid := c_invalid + 1; end if;
      end if;

    elsif p_record_type = 'campuses' then
      v_name := nullif(btrim(coalesce(r->>'campus_name', '')), '');
      if v_name is null then c_invalid := c_invalid + 1; continue; end if;
      if exists (select 1 from catalogue.campuses c where c.provider_id = v_provider and lower(btrim(c.name)) = lower(v_name)) then c_existing := c_existing + 1; continue; end if;
      v_primary := lower(coalesce(r->>'is_primary', '')) in ('true', 'yes', 'y', '1')
                   and not exists (select 1 from catalogue.campuses c where c.provider_id = v_provider and c.is_primary);
      v_sub := case when nullif(btrim(coalesce(r->>'state', '')), '') is not null then ref.resolve_subdivision_exact(v_country, btrim(r->>'state')) end;
      insert into catalogue.campuses(stable_key, provider_id, name, campus_code, country_id, subdivision_id, city, address_line1, address_line2, postcode, website,
                                     status, publication_status, source_id, evidence_id, last_verified_at, is_primary, primary_basis)
      values ('campus:' || v_scheme || ':' || lower(regexp_replace(v_pcode, '[^a-zA-Z0-9]+', '-', 'g')) || ':' || lower(regexp_replace(v_name, '[^a-zA-Z0-9]+', '-', 'g')),
              v_provider, v_name, nullif(btrim(coalesce(r->>'campus_code', '')), ''), v_country, v_sub, nullif(btrim(coalesce(r->>'city', '')), ''),
              nullif(btrim(coalesce(r->>'address_line1', '')), ''), nullif(btrim(coalesce(r->>'address_line2', '')), ''), nullif(btrim(coalesce(r->>'postcode', '')), ''),
              nullif(btrim(coalesce(r->>'website', '')), ''), 'active', 'unpublished', p_source_id, p_evidence_id, now(), v_primary,
              case when v_primary then case when v_scheme = 'cricos' then 'cricos_head_office' else 'provider_stated' end end)
      on conflict (stable_key) do nothing;
      if found then c_written := c_written + 1; if v_primary then c_primary := c_primary + 1; end if; else c_existing := c_existing + 1; end if;

    elsif p_record_type = 'provider_accreditations' then
      v_body := upper(nullif(btrim(coalesce(r->>'body_code', '')), ''));
      v_status := coalesce(lower(nullif(btrim(coalesce(r->>'status', '')), '')), 'active');
      if v_body not in ('AACSB', 'EQUIS', 'AMBA') or v_status not in ('active', 'expired', 'revoked', 'under_review') or coalesce(r->>'source_url', '') !~* '^https?://' then
        c_invalid := c_invalid + 1; continue;
      end if;
      if exists (select 1 from catalogue.provider_accreditations a where a.provider_id = v_provider and a.body_code = v_body) then c_existing := c_existing + 1; continue; end if;
      insert into catalogue.provider_accreditations(provider_id, body_code, accredited_unit_name, status, accredited_since, expires_at, source_url, evidence_id, verified_at)
      values (v_provider, v_body, nullif(btrim(coalesce(r->>'accredited_unit_name', '')), ''), v_status,
              case when (r->>'accredited_since') ~ '^\d{4}-\d{2}-\d{2}$' then (r->>'accredited_since')::date end,
              case when (r->>'expires_at') ~ '^\d{4}-\d{2}-\d{2}$' then (r->>'expires_at')::date end, r->>'source_url', p_evidence_id, now());
      c_written := c_written + 1;

    else -- grade_scale_conversions: loaded inactive until a person reviews them
      if nullif(btrim(coalesce(r->>'qualification_code', '')), '') is null or nullif(btrim(coalesce(r->>'scale_code', '')), '') is null
         or coalesce(r->>'normalized_0_100', '') !~ '^-?[0-9]+(\.[0-9]+)?$' or (r->>'normalized_0_100')::numeric not between 0 and 100 -- fixed: the scale is 0 to 100 by definition
         or coalesce(r->>'source_url', '') !~* '^https?://' then
        c_invalid := c_invalid + 1; continue;
      end if;
      if exists (select 1 from ref.grade_scale_conversions g where g.country_id = v_country and g.qualification_code = btrim(r->>'qualification_code')
                   and g.scale_code = btrim(r->>'scale_code') and coalesce(g.raw_grade_label, '') = coalesce(btrim(r->>'raw_grade_label'), '')
                   and g.raw_min_value is not distinct from case when (r->>'raw_min_value') ~ '^-?[0-9]+(\.[0-9]+)?$' then (r->>'raw_min_value')::numeric end) then
        c_existing := c_existing + 1; continue;
      end if;
      insert into ref.grade_scale_conversions(country_id, qualification_code, qualification_name, board_or_stream, scale_code, raw_min_value, raw_max_value,
                                              raw_grade_label, normalized_0_100, is_active, source_url, notes)
      values (v_country, btrim(r->>'qualification_code'), nullif(btrim(coalesce(r->>'qualification_name', '')), ''), nullif(btrim(coalesce(r->>'board_or_stream', '')), ''),
              btrim(r->>'scale_code'), case when (r->>'raw_min_value') ~ '^-?[0-9]+(\.[0-9]+)?$' then (r->>'raw_min_value')::numeric end,
              case when (r->>'raw_max_value') ~ '^-?[0-9]+(\.[0-9]+)?$' then (r->>'raw_max_value')::numeric end, nullif(btrim(coalesce(r->>'raw_grade_label', '')), ''),
              (r->>'normalized_0_100')::numeric, false, r->>'source_url', 'Layer 1 source ' || coalesce(p_source_id::text, '-') || '; inactive until reviewed');
      c_written := c_written + 1;
    end if;
  end loop;
  return jsonb_build_object('record_type', p_record_type, 'records', jsonb_array_length(coalesce(p_records, '[]'::jsonb)), 'written', c_written, 'existing', c_existing,
                            'provider_not_registered', c_no_provider, 'course_not_registered', c_no_course, 'invalid', c_invalid, 'primary_campus_set', c_primary);
end $function$;
comment on function public.svc_layer1_apply_baseline_records_v1(text, text, uuid, uuid, text, jsonb) is 'CF-247 (18 Nov 2026): apply step of Layer 1 record types campuses, provider_accreditations and grade_scale_conversions, and of course_register study_load and empty_reason_code. Fills only what is not held; never overwrites, publishes or deletes; grade scales load inactive. Called by layer1-declarative-runner in an apply run.';
revoke all on function public.svc_layer1_apply_baseline_records_v1(text, text, uuid, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_layer1_apply_baseline_records_v1(text, text, uuid, uuid, text, jsonb) to service_role;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, introduced_in)
select 'function', 'public.svc_layer1_apply_baseline_records_v1', 'Layer 1', 'Layer 1 register',
       'Apply step of the campuses, provider_accreditations and grade_scale_conversions record types and of course study_load and empty_reason_code', 'active', '20261118124000'
 where not exists (select 1 from pipeline.component_register r where r.kind = 'function' and r.name = 'public.svc_layer1_apply_baseline_records_v1');

-- 4. post-checks
do $$
declare t jsonb := security.layer1_parser_targets_v1(); k text;
begin
  foreach k in array array['course_register', 'provider_register', 'tuition_fees', 'study_rules', 'destination_metrics', 'career_outcomes', 'scholarships',
                           'provider_accreditations', 'campuses', 'grade_scale_conversions'] loop
    if not (t ? k) then raise exception 'post-check: parser target % missing', k; end if;
  end loop;
  if t->'course_register'->'fields'->'study_load'->>'type' <> 'text' or t->'course_register'->'fields'->'empty_reason_code'->>'type' <> 'code' then raise exception 'post-check: course fields'; end if;
  if t->'course_register'->>'apply' <> 'public.svc_layer1_apply_register_records' then raise exception 'post-check: the register apply step is unchanged'; end if;
  if t->'campuses'->'fields'->'is_primary'->>'type' <> 'boolean' then raise exception 'post-check: campuses.is_primary'; end if;
  if jsonb_array_length(security.layer1_record_types_v1()) <> 10 then raise exception 'post-check: record types'; end if; -- fixed: seven before plus three
  if not ((public.svc_layer1_parser_spec_validate_v1('{}'::jsonb, 'campuses', null))->'targets' ? 'fields') then raise exception 'post-check: the validator reads the new targets'; end if;
  if exists (select 1 from jsonb_object_keys(security.layer1_gap_routes_v1()) g where not (t ? g)) then raise exception 'post-check: a gap route names a record type with no parser target'; end if;
end $$;
