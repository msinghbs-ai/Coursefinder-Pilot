CREATE OR REPLACE FUNCTION security.enrich_course_text_record_v1(p_item bigint, p_r jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.field_enrich_items%rowtype; g record; v_chk jsonb; v_text text; v_review uuid; v_pid uuid; v_n int := 0; x jsonb; it record;
        v_date date; v_kept jsonb := '[]'::jsonb; v_dl jsonb := '[]'::jsonb; v_why text; v_max_before int := security.pipeline_num_v1('intake_dates.deadline_max_days_before', 366)::int;
        v_targets uuid[]; v_one uuid; v_kinds text[];
begin
  select * into i from pipeline.field_enrich_items where id = p_item for update;
  if i.id is null or i.course_id is null or i.field not in ('description', 'deadline') then return 'nothing'; end if;
  select pg.provider_id, pg.identity_basis, pg.url, pg.evidence_id, e.captured_at into g
    from pipeline.coverage_course_pages pg left join pipeline.evidence_artifacts e on e.id = pg.evidence_id where pg.course_id = i.course_id;
  if g.provider_id is null or not security.coverage_identity_allowed(g.provider_id, g.identity_basis, i.field) then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'the page''s proof (' || coalesce(g.identity_basis, 'none') || ') does not admit ' || i.field || ' for this country',
           value = p_r->'value', updated_at = now() where id = i.id;
    return 'not_admitted';
  end if;
  -- only the course's own page: the stored copy read is the copy bound to the course now
  if i.evidence_id is distinct from g.evidence_id then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'the copy read is no longer the course''s bound page (it is read again with the new copy)', value = p_r->'value', updated_at = now() where id = i.id;
    return 'not_admitted';
  end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.course_id
               and l.field in (i.field, case i.field when 'deadline' then 'intake' else 'course_description' end, 'all')) then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'locked by hand', value = p_r->'value', updated_at = now() where id = i.id;
    return 'locked';
  end if;
  select c.provider_id into v_pid from catalogue.courses c where c.id = i.course_id;

  if i.field = 'description' then
    if exists (select 1 from catalogue.courses c where c.id = i.course_id and nullif(btrim(c.description), '') is not null) then
      update pipeline.field_enrich_items set state = 'skipped', reason = 'already filled', value = p_r->'value', updated_at = now() where id = i.id; return 'already';
    end if;
    v_chk := security.course_description_check_v1(i.course_id, p_r->'value');
    if not coalesce((v_chk->>'ok')::boolean, false) then
      update pipeline.field_enrich_items set state = 'skipped', value = coalesce(p_r->'value', '{}'::jsonb) || jsonb_build_object('check', v_chk, 'reader', jsonb_build_object('model', p_r->>'model', 'prompt', p_r->>'prompt_version', 'worker', p_r->>'worker')),
             reason = left(case when v_chk->>'rule' = 'not_stated' then coalesce(nullif(p_r->>'reason', ''), 'the page does not state it')
                                else 'held: ' || (v_chk->>'rule') || ': ' || (v_chk->>'reason') end, 300), updated_at = now()
       where id = i.id;
      return case when v_chk->>'rule' = 'not_stated' then 'not_stated' else 'held' end;
    end if;
    v_text := v_chk->>'text';
    if security.course_description_trusted_v1(v_pid) then
      update catalogue.courses set description = v_text, updated_at = now() where id = i.course_id and nullif(btrim(description), '') is null;
      get diagnostics v_n = row_count;
      update pipeline.field_enrich_items set state = case when v_n > 0 then 'filled' else 'skipped' end, reason = case when v_n > 0 then null else 'already filled' end,
             value = p_r->'value' || jsonb_build_object('text', v_text, 'check', v_chk, 'admitted', 'checks (provider''s first descriptions approved in Layer 4)'),
             quote = left(coalesce(p_r->>'quote', i.quote), 300), updated_at = now() where id = i.id;
      insert into search.refresh_requests(requested_by) select 'AI reader (course description, deadline)'
       where v_n > 0 and not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'AI reader (course description, deadline)');
      return case when v_n > 0 then 'filled' else 'already' end;
    end if;
    -- Layer 4 on first admission: at most enrich.course_description_pending_max of the provider's wait at once; the rest keep their reading
    -- the provider's places: pending_max less the waiting descriptions the machine has not already declined for good (those wait for a person and take no place a reading could use)
    if security.cdesc_provider_slots_v1(v_pid) <= 0 then
      update pipeline.field_enrich_items set state = 'skipped', reason = 'held_first_admission: the provider''s first descriptions wait in Layer 4; admitted once they are approved',
             value = p_r->'value' || jsonb_build_object('text', v_text, 'check', v_chk, 'reader', jsonb_build_object('model', p_r->>'model', 'prompt', p_r->>'prompt_version', 'worker', p_r->>'worker')), quote = left(coalesce(p_r->>'quote', i.quote), 300), updated_at = now() where id = i.id;
      return 'held_first_admission';
    end if;
    insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
    values ('course', i.course_id, 'course_description_first_read', g.evidence_id, jsonb_build_object('description', null),
            jsonb_build_object('description', v_text, 'item_id', i.id, 'source_url', g.url, 'checks', v_chk->'checks',
                               'sentences', (select jsonb_agg(jsonb_build_object('text', s->>'text', 'quote', s->>'quote') order by o) from jsonb_array_elements(p_r->'value'->'sentences') with ordinality e(s, o))),
            jsonb_build_object('source', 'course description reader', 'page', g.url, 'identity_basis', g.identity_basis),
            jsonb_build_object('item_id', i.id, 'model', p_r->>'model', 'prompt', p_r->>'prompt_version', 'worker', p_r->>'worker'),
            'pending', 'Course description read from the course''s own page. This is one of the provider''s first course descriptions, so a person approves it as read or rejects it.',
            'CF-CHG-20260915-247')
    returning id into v_review;
    update pipeline.field_enrich_items set state = 'review', reason = null, value = p_r->'value' || jsonb_build_object('text', v_text, 'check', v_chk, 'review_item_id', v_review),
           quote = left(coalesce(p_r->>'quote', i.quote), 300), updated_at = now() where id = i.id;
    return 'review';
  end if;

  -- deadline: explicit dates only, tied to an intake the page names (or the course's only active intake)
  if not exists (select 1 from catalogue.course_intakes x where x.course_id = i.course_id and x.status = 'active') then
    update pipeline.field_enrich_items set state = 'skipped', reason = 'no active intake to hold a deadline', value = p_r->'value', updated_at = now() where id = i.id; return 'not_admitted';
  end if;
  for x in select * from jsonb_array_elements(coalesce(p_r->'value'->'deadlines', '[]'::jsonb)) loop
    v_why := null; v_targets := '{}'; v_date := null;
    if x->>'kind' <> 'date' then v_why := coalesce(x->>'kind', 'not_stated');
    elsif not coalesce((x->>'on_page')::boolean, false) then v_why := 'quote_not_on_page';
    elsif coalesce(x->>'date', '') !~ '^\d{4}-\d{2}-\d{2}$' then v_why := 'no_full_date';
    else
      begin v_date := (x->>'date')::date; exception when others then v_date := null; end;
      if v_date is null then v_why := 'no_full_date';
      elsif not security.course_deadline_in_quote_v1(v_date, x->>'quote') then v_why := 'date_not_in_quote';
      end if;
    end if;
    if v_why is null then
      if nullif(btrim(x->>'intake'), '') is null then
        select array_agg(ci.id) into v_targets from catalogue.course_intakes ci where ci.course_id = i.course_id and ci.status = 'active';
        if cardinality(v_targets) <> 1 then v_why := 'not_tied_to_one_intake'; v_targets := '{}'; end if;
      else
        select coalesce(array_agg(ci.id), '{}') into v_targets from catalogue.course_intakes ci
         where ci.course_id = i.course_id and ci.status = 'active' and security.course_deadline_intake_match_v1(ci.intake_label, ci.intake_year, x->>'intake');
        if cardinality(v_targets) = 0 then v_why := 'intake_not_matched'; end if;
      end if;
    end if;
    v_dl := v_dl || (x || jsonb_build_object('outcome', coalesce(v_why, 'kept'), 'intake_ids', to_jsonb(v_targets)));
    if v_why is null then
      foreach v_one in array v_targets loop v_kept := v_kept || jsonb_build_object('intake_id', v_one, 'date', v_date, 'quote', x->>'quote'); end loop;
    end if;
  end loop;
  -- per intake: one date only (two different dates for one intake are held), within the intake's window, never over a deadline held
  for it in select ci.id, ci.start_date, ci.intake_year, ci.application_deadline, array_agg(distinct (k->>'date')::date) dates, min(k->>'quote') quote
              from jsonb_array_elements(v_kept) k join catalogue.course_intakes ci on ci.id = (k->>'intake_id')::uuid group by 1, 2, 3, 4 loop
    if cardinality(it.dates) > 1 then v_dl := v_dl || jsonb_build_object('intake_ids', jsonb_build_array(it.id), 'outcome', 'conflicting_dates'); continue; end if;
    v_date := it.dates[1];
    if it.application_deadline is not null then continue; end if;
    if (it.start_date is not null and (v_date > it.start_date or v_date < it.start_date - v_max_before))
       or (it.start_date is null and it.intake_year is not null and (v_date < make_date(it.intake_year - 1, 1, 1) or v_date > make_date(it.intake_year, 12, 31))) then
      v_dl := v_dl || jsonb_build_object('intake_ids', jsonb_build_array(it.id), 'outcome', 'outside_intake_window', 'date', v_date); continue;
    end if;
    update catalogue.course_intakes set application_deadline = v_date where id = it.id and application_deadline is null;
    if found then v_n := v_n + 1; end if;
  end loop;
  v_kinds := array(select distinct d->>'outcome' from jsonb_array_elements(v_dl) d);
  update pipeline.field_enrich_items set state = case when v_n > 0 then 'filled' else 'skipped' end,
         value = jsonb_build_object('deadlines', v_dl, 'applied', v_n),
         quote = left(coalesce((select k->>'quote' from jsonb_array_elements(v_kept) k limit 1), p_r->>'quote', i.quote), 300),
         reason = case when v_n > 0 then null
                       when cardinality(v_kinds) = 0 or v_kinds <@ array['not_stated'] then coalesce(nullif(p_r->>'reason', ''), 'the page does not state it')
                       when v_kinds <@ array['rolling', 'not_stated'] then 'the page says applications are rolling (no date to hold)'
                       when 'kept' = any (v_kinds) then 'already filled or outside the intake''s dates'
                       else left('held: ' || array_to_string(v_kinds, ', '), 300) end,
         updated_at = now()
   where id = i.id;
  if v_n > 0 then
    insert into search.refresh_requests(requested_by) select 'AI reader (course description, deadline)'
     where not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'AI reader (course description, deadline)');
  end if;
  return case when v_n > 0 then 'filled' else 'not_admitted' end;
end $function$
