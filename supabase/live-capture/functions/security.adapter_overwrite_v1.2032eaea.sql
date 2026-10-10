CREATE OR REPLACE FUNCTION security.adapter_overwrite_v1(p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_src uuid; v_ok int := 0; v_err int := 0; v_last text; v_courses uuid[] := '{}'; v_payload jsonb; v_itk text[]; v_ielts numeric; v_band numeric; v_fee numeric; v_fy int; v_cur text; v_mode_n int := 0;
begin
  for r in
    select pg.course_id, pg.provider_id, pg.url, pg.evidence_id, e.content_hash, pg.candidates c, pg.identity_basis ib, u.admit_fields af, u.reading rd, co.delivery_mode cur_mode, coalesce(security.delivery_mode_from_text(pg.candidates->'adapter_extra'->>'mode'), security.delivery_mode_from_location(coalesce(pg.candidates->'adapter_extra'->>'location', pg.candidates->'adapter_extra'->>'campus'))) new_mode,
           (select pr.registration_code from catalogue.provider_registrations pr where pr.provider_id = pg.provider_id and lower(pr.registration_scheme) = 'cricos' and coalesce(pr.status, 'active') not in ('inactive', 'cancelled', 'archived') order by pr.checked_at desc nulls last limit 1) pc,
           (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1) cc,
           (select array_agg(distinct i.intake_label order by i.intake_label) from catalogue.course_intakes i where i.course_id = pg.course_id and i.status = 'active') cur_itk,
           (select r2.overall_score from catalogue.course_english_requirements r2 join ref.english_tests t on t.id = r2.english_test_id where r2.course_id = pg.course_id and t.code = 'IELTS' and coalesce(r2.status, 'active') = 'active' limit 1) cur_ielts,
           (select f.amount from catalogue.course_fees f where f.course_id = pg.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' order by f.fee_year desc nulls last limit 1) cur_fee,
           u.admit adm,
           (select (select array_agg(distinct z::int order by z::int) from jsonb_array_elements_text(l.cv->'months') z)
                   = (select array_agg(distinct extract(month from to_date(i.intake_label, 'Month'))::int order by extract(month from to_date(i.intake_label, 'Month'))::int)
                        from catalogue.course_intakes i where i.course_id = pg.course_id and i.status = 'active' and i.intake_label ~ '^(January|February|March|April|May|June|July|August|September|October|November|December)$')
              from (select x.candidate_value cv from pipeline.layer3_interpretations x where x.entity_type = 'course' and x.entity_id = pg.course_id and x.status = 'validated'
                       and x.task_class = 'provider_intake_validation' and jsonb_typeof(x.candidate_value->'months') = 'array' order by x.created_at desc limit 1) l) r5_itk,
           (select (select (t->>'overall')::numeric from jsonb_array_elements(l.cv->'tests') t where t->>'test' = 'IELTS' limit 1)
                   = (select r3.overall_score from catalogue.course_english_requirements r3 join ref.english_tests t3 on t3.id = r3.english_test_id where r3.course_id = pg.course_id and t3.code = 'IELTS' and coalesce(r3.status, 'active') = 'active' limit 1)
              from (select x.candidate_value cv from pipeline.layer3_interpretations x where x.entity_type = 'course' and x.entity_id = pg.course_id and x.status = 'validated'
                       and x.task_class = 'provider_english_validation' and jsonb_typeof(x.candidate_value->'tests') = 'array' order by x.created_at desc limit 1) l) r5_eng,
           (select abs((l.cv->>'amount')::numeric - (select f.amount from catalogue.course_fees f where f.course_id = pg.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' order by f.fee_year desc nulls last limit 1))
                   <= 0.01 * (l.cv->>'amount')::numeric
              from (select x.candidate_value cv from pipeline.layer3_interpretations x where x.entity_type = 'course' and x.entity_id = pg.course_id and x.status = 'validated'
                       and x.task_class = 'provider_current_tuition_validation' and (x.candidate_value->>'amount') ~ '^[0-9]+(\.[0-9]+)?$' order by x.created_at desc limit 1) l) r5_fee
      from pipeline.coverage_course_pages pg
      join pipeline.evidence_artifacts e on e.id = pg.evidence_id
      join catalogue.courses co on co.id = pg.course_id and co.lifecycle_status = 'active'
      join pipeline.uni_adapters u on u.provider_id = pg.provider_id and u.enabled
       and (u.admit or exists (select 1 from pipeline.layer3_interpretations l3 where l3.entity_type = 'course' and l3.entity_id = pg.course_id and l3.status = 'validated'
                                and l3.task_class in ('provider_intake_validation', 'provider_english_validation', 'provider_current_tuition_validation')))
     where pg.read_status = 'read' and pg.identity_basis is not null
       and (pg.candidates->>'intakes_by' = 'adapter' or pg.candidates->>'english_by' = 'adapter' or pg.candidates->>'fee_by' = 'adapter' or pg.candidates->'adapter_extra' ? 'mode' or pg.candidates->'adapter_extra' ? 'campus' or pg.candidates->'adapter_extra' ? 'location')
       and security.coverage_identity_allowed(pg.provider_id, pg.identity_basis, null)
       and not security.layer4_entity_or_parent_blocked('course', pg.course_id, 'operational')
  loop
    exit when v_ok >= greatest(1, least(coalesce(p_limit, 200), 1000));
    v_payload := '{}'::jsonb;
    v_itk := (select array_agg(distinct m order by m) from jsonb_array_elements_text(coalesce(r.c->'intakes', '[]'::jsonb)) m);
    if r.c->>'intakes_by' = 'adapter' and v_itk is not null and r.cur_itk is distinct from v_itk
       and security.coverage_identity_allowed(r.provider_id, r.ib, 'intakes') and (('intakes' = any (r.af) and r.adm) or coalesce(r.r5_itk, false)) and not security.uni_adapter_excluded(r.course_id, 'intakes')
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('intakes', 'intake')) then
      v_payload := v_payload || jsonb_build_object('intakes', (select jsonb_agg(jsonb_build_object('intake_label', m, 'source_intake_key', lower(coalesce(r.cc, r.course_id::text)) || ':current:' || lower(m))) from unnest(v_itk) m));
    end if;
    v_ielts := nullif(r.c->'english'->>'ielts_overall', '')::numeric;
    v_band := nullif(r.c->'english'->>'ielts_min_band', '')::numeric;
    if r.c->>'english_by' = 'adapter' and v_ielts is not null and r.cur_ielts is distinct from v_ielts
       and security.coverage_identity_allowed(r.provider_id, r.ib, 'english') and (('english' = any (r.af) and r.adm) or coalesce(r.r5_eng, false)) and not security.uni_adapter_excluded(r.course_id, 'english')
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('english', 'english_requirements')) then
      v_payload := v_payload || jsonb_build_object('english_requirements', jsonb_build_array(jsonb_build_object('test_code', 'IELTS', 'overall_score', v_ielts,
                      'component_scores', case when v_band is null then '{}'::jsonb else jsonb_build_object('listening', v_band, 'reading', v_band, 'writing', v_band, 'speaking', v_band) end,
                      'notes', 'University adapter reading of the course page')));
    end if;
    -- v0.17 (Platform Admin 23:41, decision 4): the international annual fee the adapter read is admitted too
    v_fee := nullif(r.c->'fee'->>'value', '')::numeric;
    v_fy := coalesce(nullif(r.c->'fee'->>'fee_year', '')::int, security.adapter_fee_year_setting(r.rd), extract(year from now() at time zone 'Australia/Melbourne')::int);
    v_cur := coalesce(nullif(r.c->'fee'->>'currency', ''), case security.coverage_country(r.provider_id) when 'NZ' then 'NZD' when 'CA' then 'CAD' else 'AUD' end);
    if r.c->>'fee_by' = 'adapter' and v_fee is not null and v_fee between 1000 and 500000 and (select f.amount from catalogue.course_fees f where f.course_id = r.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and coalesce(f.fee_year, 0) = coalesce(v_fy, 0) order by f.updated_at desc nulls last limit 1) is distinct from v_fee
       and (('fee' = any (r.af) and r.adm) or coalesce(r.r5_fee, false)) and not security.uni_adapter_excluded(r.course_id, 'fee') and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('tuition', 'fee', 'fees')) then
      v_payload := v_payload || jsonb_build_object('fee_amount', v_fee, 'fee_year', v_fy, 'currency_code', v_cur, 'fee_basis', 'annual', 'audience', 'international',
                     'fee_notes', 'University adapter reading of the course page (international annual fee)',
                     'fee_key', lower(coalesce(r.cc, r.course_id::text)) || ':international:' || coalesce(v_fy::text, 'current') || ':annual');
    end if;
    -- 5 Oct (Platform Admin 11:48): delivery read from the international view of the course page
    if r.new_mode is not null and r.cur_mode is distinct from r.new_mode and ('delivery' = any (r.af) and r.adm) and not security.uni_adapter_excluded(r.course_id, 'delivery')
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('delivery_mode', 'delivery')) then
      begin
        update catalogue.courses set delivery_mode = r.new_mode, updated_at = now() where id = r.course_id;
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'delivery', to_jsonb(r.cur_mode), to_jsonb(r.new_mode), r.evidence_id, r.url);
        v_mode_n := v_mode_n + 1; v_courses := v_courses || r.course_id;
      exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
      end;
    end if;
    continue when v_payload = '{}'::jsonb;
    begin
      v_src := security.coverage_sweep_source(r.provider_id);
      insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
        select 'courses', d, v_src, 'approved', 'CF-CHG-20260915-247, Decision 253, Platform Admin 4 Oct 2026 22:43 (adapter readings replace held values)', now(), now(), now()
        from unnest(array_remove(array[case when v_payload ? 'intakes' then 'course_intake' end, case when v_payload ? 'english_requirements' then 'course_english' end, case when v_payload ? 'fee_amount' then 'provider_current_tuition' end], null)) d
        where not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = d and g.source_id = v_src);
      if v_payload ? 'intakes' then
        update catalogue.course_intakes set status = 'withdrawn' where course_id = r.course_id and status = 'active' and source_id is not null and intake_label <> all (v_itk);
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'intakes', to_jsonb(r.cur_itk), to_jsonb(v_itk), r.evidence_id, r.url);
      end if;
      if v_payload ? 'english_requirements' then
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'english_ielts', to_jsonb(r.cur_ielts), to_jsonb(v_ielts), r.evidence_id, r.url);
      end if;
      if v_payload ? 'fee_amount' then
        update catalogue.course_fees set status = 'superseded', updated_at = now() where course_id = r.course_id and status = 'active' and fee_type = 'provider_current_tuition' and audience = 'international' and source_id is not null and coalesce(fee_year, 0) = coalesce(v_fy, 0) and amount <> v_fee;
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'fee', to_jsonb(r.cur_fee), jsonb_build_object('amount', v_fee, 'year', v_fy, 'currency', v_cur), r.evidence_id, r.url);
      end if;
      if r.pc is null or r.cc is null then
        perform security.coverage_apply_course_v1(r.course_id, v_src, r.evidence_id, r.url, r.content_hash, v_payload);
      else
        perform public.svc_coursefacts_apply_record(v_src, r.evidence_id, r.pc, r.cc, 'coverage:' || r.course_id, r.url, r.content_hash, v_payload, true);
      end if;
      update pipeline.layer4_review_items set status = 'superseded', decided_at = now() where entity_type = 'course' and entity_id = r.course_id and status = 'pending' and field_code in (case when v_payload ? 'intakes' then 'course_intake' end, case when v_payload ? 'english_requirements' then 'course_english' end, case when v_payload ? 'fee_amount' then 'course_tuition' end);
      v_ok := v_ok + 1; v_courses := v_courses || r.course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if cardinality(v_courses) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_courses, true); end if;
  return jsonb_build_object('delivery', v_mode_n, 'replaced', v_ok, 'errors', v_err, 'last_error', v_last);
end $function$
