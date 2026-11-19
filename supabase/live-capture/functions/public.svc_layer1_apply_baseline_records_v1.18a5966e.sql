CREATE OR REPLACE FUNCTION public.svc_layer1_apply_baseline_records_v1(p_record_type text, p_country_code text, p_source_id uuid, p_evidence_id uuid, p_registration_scheme text, p_records jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$
