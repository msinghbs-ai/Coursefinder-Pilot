CREATE OR REPLACE FUNCTION security.coverage_apply_course_v1(p_course_id uuid, p_source_id uuid, p_evidence_id uuid, p_url text, p_hash text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c record; r jsonb; v_test uuid; v_key text; v_links int := 0; v_intakes int := 0; v_english int := 0; v_fees int := 0; v_cur text; v_floor numeric; v_ident text; v_ident_url text; v_cc text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select co.id, co.provider_id, lower(coalesce(nullif(btrim(co.course_code), ''), co.id::text)) code, a.currency_code
    into c from catalogue.courses co join catalogue.providers p on p.id = co.provider_id
    join pipeline.coverage_admission_countries a on a.country_id = p.country_id and a.active
   where co.id = p_course_id;
  if c.id is null then raise exception 'course not found or its country has no admission rule'; end if;
  if security.layer4_entity_or_parent_blocked('course', p_course_id, 'operational') then raise exception 'course operationally blocked by Layer 4' using errcode = '42501'; end if;
  if p_source_id is null or p_evidence_id is null or coalesce(btrim(p_url), '') = '' or coalesce(btrim(p_hash), '') = '' then raise exception 'source, evidence, page and hash required'; end if;

  if nullif(btrim(p_payload->>'course_url'), '') is not null then
    insert into catalogue.course_links(course_id, link_type, url, audience, label, is_primary, status, source_id, evidence_id, confidence, last_verified_at, updated_at)
    values (p_course_id, 'official_course', btrim(p_payload->>'course_url'), 'international', 'Official provider course page', false, 'active', p_source_id, p_evidence_id, 1, now(), now())
    on conflict (course_id, link_type, url) do update set status = 'active', source_id = excluded.source_id, evidence_id = excluded.evidence_id,
           confidence = 1, last_verified_at = now(), updated_at = now();
    v_links := 1;
  end if;
  for r in select value from jsonb_array_elements(coalesce(p_payload->'intakes', '[]'::jsonb)) loop
    if nullif(btrim(r->>'intake_label'), '') is null then raise exception 'intake_label required'; end if;
    v_key := coalesce(nullif(r->>'source_intake_key', ''), c.code || ':' || coalesce(r->>'intake_year', 'current') || ':' || lower(r->>'intake_label'));
    insert into catalogue.course_intakes as ci(course_id, intake_year, intake_label, start_date, status, source_id, evidence_id, confidence, source_intake_key)
    values (p_course_id, nullif(r->>'intake_year', '')::int, r->>'intake_label', nullif(r->>'start_date', '')::date, 'active', p_source_id, p_evidence_id, 1, v_key)
    on conflict (course_id, source_id, source_intake_key) where source_id is not null and source_intake_key is not null
    -- 2 Nov 2026 (intake dates): a write without a year keeps the held year, start date and deadline; an older year never replaces a later one
    do update set intake_year = case when excluded.intake_year is null or excluded.intake_year < ci.intake_year then ci.intake_year else excluded.intake_year end,
                  intake_label = excluded.intake_label,
                  start_date = case when excluded.intake_year > ci.intake_year then excluded.start_date when excluded.intake_year < ci.intake_year then ci.start_date
                                    else coalesce(excluded.start_date, ci.start_date) end,
                  application_deadline = case when excluded.intake_year > ci.intake_year then null else ci.application_deadline end,
                  status = 'active',
                  evidence_id = excluded.evidence_id, confidence = 1;
    v_intakes := v_intakes + 1;
  end loop;
  for r in select value from jsonb_array_elements(coalesce(p_payload->'english_requirements', '[]'::jsonb)) loop
    select id into v_test from ref.english_tests where code = upper(btrim(r->>'test_code')) limit 1;
    if v_test is null then raise exception 'english test not seeded: %', r->>'test_code'; end if;
    insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, notes, source_id, evidence_id, confidence,
                                                      source_requirement_key, status, last_verified_at)
    values (p_course_id, v_test, nullif(r->>'overall_score', '')::numeric, coalesce(r->'component_scores', '{}'::jsonb), r->>'notes', p_source_id, p_evidence_id, 1,
            coalesce(nullif(r->>'source_requirement_key', ''), c.code || ':' || upper(btrim(r->>'test_code'))), 'active', now())
    on conflict (course_id, english_test_id) do update set overall_score = excluded.overall_score, component_scores = excluded.component_scores,
           notes = excluded.notes, source_id = excluded.source_id, evidence_id = excluded.evidence_id, confidence = 1,
           source_requirement_key = excluded.source_requirement_key, status = 'active', last_verified_at = now();
    v_english := v_english + 1;
  end loop;
  if p_payload ? 'fee_amount' then
    v_cur := coalesce(nullif(btrim(p_payload->>'currency_code'), ''), c.currency_code);
    if v_cur is distinct from c.currency_code then raise exception 'fee currency % does not match the country currency %', v_cur, c.currency_code; end if;
    if nullif(p_payload->>'fee_amount', '')::numeric is null or (p_payload->>'fee_amount')::numeric <= 0 then raise exception 'positive fee amount required'; end if;
    -- 23 Oct 2026 (NZ brief C3): below the country floor the fee is quarantined (status review, Layer 4 item), never admitted silently
    v_floor := security.fee_below_floor_v1(p_course_id, (p_payload->>'fee_amount')::numeric, nullif(btrim(p_payload->>'fee_basis'), ''));
    -- 24 Oct 2026 (R1, apply-time identity check): a fee for a course whose bound page carries a proof the country's tuition policy does not
    -- accept is never admitted live, whatever the caller checked: written unverified with one Layer 4 row (source identity_basis_reverify).
    -- Manual bindings are exempt. A page re-bound under the country's rule re-admits the fee through this same path.
    select p.identity_basis, p.url, k.iso_alpha2 into v_ident, v_ident_url, v_cc
      from pipeline.coverage_course_pages p join catalogue.providers pr on pr.id = p.provider_id join ref.countries k on k.id = pr.country_id
     where p.course_id = p_course_id and p.status = 'bound' and coalesce(p.basis, '') <> 'manual' and p.identity_basis is not null
       and p.identity_basis <> 'manual' and not security.coverage_identity_allowed(c.provider_id, p.identity_basis, 'tuition') limit 1;
    if v_ident is not null then
      if not exists (select 1 from pipeline.layer4_review_items l where l.entity_type = 'course' and l.entity_id = p_course_id and l.field_code = 'provider_current_tuition' and l.status = 'pending') then
        insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
        values ('course', p_course_id, 'provider_current_tuition', p_evidence_id, null,
                jsonb_build_object('amount', (p_payload->>'fee_amount')::numeric, 'currency', v_cur, 'basis', nullif(btrim(p_payload->>'fee_basis'), ''), 'page', p_url),
                jsonb_build_object('source', 'identity_basis_reverify', 'state', 'quarantined', 'country', v_cc, 'identity_basis', v_ident, 'page', v_ident_url), '{}'::jsonb, 'pending',
                'quarantined at the write: the course page was bound with a ' || v_ident || ' proof, which the ' || v_cc || ' tuition policy does not accept; re-binding the page under the country''s rule re-admits the fee',
                'CF-CHG-20260915-247 R1 apply-time identity check');
      end if;
      v_floor := coalesce(v_floor, -1);  /* fixed: a sentinel that keeps the fee unverified through the same write below; never shown */
    end if;
    insert into catalogue.course_fees(course_id, fee_year, audience, fee_type, amount, currency_code, basis, notes, source_id, evidence_id, confidence,
                                      source_fee_key, status, last_verified_at, source_snapshot_at, updated_at)
    values (p_course_id, nullif(p_payload->>'fee_year', '')::int, 'international', 'provider_current_tuition', (p_payload->>'fee_amount')::numeric, v_cur,
            nullif(btrim(p_payload->>'fee_basis'), ''), p_payload->>'fee_notes', p_source_id, p_evidence_id, 1,
            c.code || ':international:' || coalesce(p_payload->>'fee_year', 'current') || ':' || coalesce(nullif(btrim(p_payload->>'fee_basis'), ''), 'tuition'),
            case when v_floor is not null then 'unverified' else 'active' end, now(), now(), now())
    on conflict (course_id, source_id, source_fee_key) where source_id is not null and source_fee_key is not null
    do update set amount = excluded.amount, currency_code = excluded.currency_code, basis = excluded.basis, fee_year = excluded.fee_year,
                  evidence_id = excluded.evidence_id, confidence = 1, status = case when v_floor is not null then 'unverified' else 'active' end, last_verified_at = now(), source_snapshot_at = now(), updated_at = now();
    if v_floor is not null then
      if v_floor <> -1 and not exists (select 1 from pipeline.layer4_review_items l where l.entity_type = 'course' and l.entity_id = p_course_id and l.field_code = 'provider_current_tuition' and l.status = 'pending') then
        insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
        values ('course', p_course_id, 'provider_current_tuition', p_evidence_id, null,
                jsonb_build_object('amount', (p_payload->>'fee_amount')::numeric, 'currency', v_cur, 'basis', nullif(btrim(p_payload->>'fee_basis'), ''), 'page', p_url),
                jsonb_build_object('page', p_url, 'source', 'fee floor', 'state', 'quarantined'), '{}'::jsonb, 'pending',
                'international fee below the country floor (' || v_cur || ' ' || to_char(v_floor, 'FM999,999,999') || ' a year): ' || v_cur || ' ' || to_char((p_payload->>'fee_amount')::numeric, 'FM999,999,999.00'),
                'CF-CHG-20260915-247 NZ brief C3');
      end if;
      v_fees := 0;
    else
      v_fees := 1;
    end if;
  end if;
  return jsonb_build_object('course_id', p_course_id, 'links_applied', v_links, 'intakes_applied', v_intakes, 'english_applied', v_english, 'fees_applied', v_fees, 'fee_quarantined', v_floor is not null and v_floor <> -1, 'fee_quarantined_identity', v_ident is not null);
end $function$
