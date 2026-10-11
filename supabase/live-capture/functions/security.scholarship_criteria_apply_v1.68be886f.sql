CREATE OR REPLACE FUNCTION security.scholarship_criteria_apply_v1(p_scholarship_id uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare pg record; s record; v_src uuid; v_new jsonb; v_old jsonb; v_changes text[] := '{}'; v_dur text; n int;
begin
  select * into pg from pipeline.scholarship_pages where scholarship_id = p_scholarship_id;
  select * into s from scholarship.scholarships where id = p_scholarship_id;
  if s.id is null or pg.read_status is distinct from 'read' or pg.facts is null or not (pg.facts ? 'criteria') then return v_changes; end if;
  v_src := security.coverage_sweep_source(s.provider_id);

  -- the reader's criteria, in a fixed order, compared with the sweep's active rows
  select coalesce(jsonb_agg(x order by x->>'type', x->>'value_text', x->>'value_codes'), '[]') into v_new
    from (select jsonb_build_object('type', c->>'type', 'operator', c->>'operator', 'value_text', c->>'value_text',
                 'value_number', (c->>'value_number')::numeric, 'value_codes', c->'value_codes', 'scale', (c->>'scale')::numeric) x
            from jsonb_array_elements(case when jsonb_typeof(pg.facts->'criteria') = 'array' then pg.facts->'criteria' else '[]' end) c
           where c->>'type' in ('student_type','study_stage','study_load','academic_minimum','gender','nationality','application_method')) q;
  select coalesce(jsonb_agg(x order by x->>'type', x->>'value_text', x->>'value_codes'), '[]') into v_old
    from (select jsonb_build_object('type', cr.criterion_type, 'operator', cr.operator, 'value_text', cr.value_text,
                 'value_number', cr.value_number, 'value_codes', to_jsonb(cr.value_codes), 'scale', (cr.value_json->>'scale')::numeric) x
            from scholarship.criteria cr
           where cr.scholarship_id = s.id and cr.status = 'active' and cr.value_json->>'by' = 'scholarship_sweep') q;
  if v_new is distinct from v_old then
    update scholarship.criteria set status = 'superseded'
     where scholarship_id = s.id and status = 'active' and value_json->>'by' = 'scholarship_sweep';
    insert into scholarship.criteria(scholarship_id, criterion_type, operator, value_text, value_number, value_codes, value_json,
                                     human_text, is_mandatory, machine_evaluable, status, source_id, evidence_id, confidence)
    select s.id, c->>'type', c->>'operator', c->>'value_text', (c->>'value_number')::numeric,
           case when jsonb_typeof(c->'value_codes') = 'array' then array(select jsonb_array_elements_text(c->'value_codes')) end,
           jsonb_strip_nulls(jsonb_build_object('by', 'scholarship_sweep', 'extractor', coalesce(pg.facts->>'criteria_extractor', pg.facts->>'extractor'), 'scale', (c->>'scale')::numeric)),
           left(c->>'text', 300), true, c->>'type' <> 'application_method', 'active', v_src, pg.evidence_id, 0.7
      from jsonb_array_elements(case when jsonb_typeof(pg.facts->'criteria') = 'array' then pg.facts->'criteria' else '[]' end) c
     where c->>'type' in ('student_type','study_stage','study_load','academic_minimum','gender','nationality','application_method');
    get diagnostics n = row_count;
    insert into pipeline.scholarship_sweep_changes(scholarship_id, field, before_value, after_value, evidence_id)
    values (s.id, 'criteria', v_old, v_new, pg.evidence_id);
    v_changes := v_changes || 'criteria'::text;
  end if;

  -- award duration, only where the record has none (values entered by hand or by other sources stay)
  v_dur := pg.facts->'award_scope'->>'duration';
  if s.award_duration_basis is null and v_dur in ('one_off','first_year','annual','annual_program_duration','program_duration','per_semester') then
    begin
      update scholarship.scholarships set award_duration_basis = v_dur, updated_at = now() where id = s.id;
      insert into pipeline.scholarship_sweep_changes(scholarship_id, field, before_value, after_value, evidence_id)
      values (s.id, 'award_duration_basis', null, pg.facts->'award_scope', pg.evidence_id);
      v_changes := v_changes || 'award_duration'::text;
    exception when others then null; -- a value locked by hand is left as it is
    end;
  end if;
  -- Decision 212: one stated maximum ("up to $5,000", "up to 50%") is recorded as a maximum, only where the record has no value
  declare v_val jsonb := pg.facts->'value'; na int; np int; amt numeric; pct numeric;
  begin
    if not (s.award_value_type in ('percentage','fixed_amount') and coalesce(s.award_percentage, s.award_amount) is not null)
       and v_val->>'type' = 'ambiguous' and coalesce((v_val->>'up_to')::boolean, false) and not coalesce((v_val->>'foreign_currency')::boolean, false) then
      na := jsonb_array_length(case when jsonb_typeof(v_val->'amounts') = 'array' then v_val->'amounts' else '[]' end);
      np := jsonb_array_length(case when jsonb_typeof(v_val->'percentages') = 'array' then v_val->'percentages' else '[]' end);
      amt := case when na = 1 and np = 0 then (v_val->'amounts'->>0)::numeric end;
      pct := case when np = 1 and na = 0 then (v_val->'percentages'->>0)::numeric end;
      if amt between 500 and 200000 then
        update scholarship.scholarships set award_value_type = 'fixed_amount', award_amount = amt, award_currency_code = scholarship.provider_currency(s.provider_id), award_value_is_maximum = true,
               award_value_text = coalesce(award_value_text, 'Up to ' || scholarship.money_prefix(scholarship.provider_currency(s.provider_id)) || to_char(amt, 'FM999,999,999')), evidence_id = pg.evidence_id, updated_at = now()
         where id = s.id;
      elsif pct between 5 and 100 then
        update scholarship.scholarships set award_value_type = 'percentage', award_percentage = pct, award_value_is_maximum = true,
               award_applies_to_fee_type = case when coalesce(pg.facts->'award_scope'->'applies_to', '[]') ? 'tuition_fee' then coalesce(award_applies_to_fee_type, 'tuition_fee') else award_applies_to_fee_type end,
               award_value_text = coalesce(award_value_text, 'Up to ' || pct::text || '%' || case when coalesce(pg.facts->'award_scope'->'applies_to', '[]') ? 'tuition_fee' then ' of tuition fees' else '' end),
               evidence_id = pg.evidence_id, updated_at = now()
         where id = s.id;
      end if;
      if amt between 500 and 200000 or pct between 5 and 100 then
        insert into pipeline.scholarship_sweep_changes(scholarship_id, field, before_value, after_value, evidence_id)
        values (s.id, 'award_value_maximum', jsonb_build_object('type', s.award_value_type, 'text', s.award_value_text), v_val, pg.evidence_id);
        v_changes := v_changes || 'award_value_maximum'::text;
      end if;
    end if;
  exception when others then null; -- a value locked by hand is left as it is
  end;

  return v_changes;
end $function$
