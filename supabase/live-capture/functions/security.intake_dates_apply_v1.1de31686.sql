CREATE OR REPLACE FUNCTION security.intake_dates_apply_v1(p_limit integer, p_course_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_on boolean := coalesce((security.toolset_setting('pipeline', 'intake_dates.apply_enabled') #>> '{}')::boolean, false);
        v_filled int := 0; v_seen int := 0; v_courses uuid[] := '{}'; p record; v_n int; v_prov int := 0; v_by jsonb := '{}'::jsonb;
begin
  if not v_on then return jsonb_build_object('enabled', false, 'filled', 0); end if;
  perform pg_advisory_xact_lock(hashtext('cf247 intake dates apply'));  -- fixed: one run at a time
  -- 23:24 provenance: values filled before the page wording was kept get it now (as stored now), with the approved calendar's document
  update pipeline.course_intake_dates d
     set page_quote = coalesce(left(security.intake_page_wording_v1(d.course_id, i.evidence_id, e.source_url), 600), ''),
         calendar_evidence_id = cal.evidence_id, calendar_url = cal.url
    from catalogue.course_intakes i left join pipeline.evidence_artifacts e on e.id = i.evidence_id, pipeline.provider_policy_proposals cal
   where d.intake_id in (select d2.intake_id from pipeline.course_intake_dates d2 where d2.outcome = 'filled' and d2.calendar_url is null
                            and (p_course_ids is null or d2.course_id = any (p_course_ids))
                          limit security.pipeline_num_v1('batch.intake_dates_apply', 200)::int)
     and i.id = d.intake_id and cal.id = d.proposal_id;
  get diagnostics v_prov = row_count;
  -- CF-247 intake recovery (decision 5 Nov 2026): plan v3; every decision is also appended to pipeline.course_intake_date_events
  for p in select * from security.intake_dates_plan_v3(p_course_ids, p_limit) loop
    v_seen := v_seen + 1;
    if p.outcome = 'filled' then
      update catalogue.course_intakes i
         set intake_year = coalesce(i.intake_year, p.new_year), start_date = coalesce(i.start_date, p.new_start),
             application_deadline = coalesce(i.application_deadline, p.new_deadline)
       where i.id = p.intake_id and i.status = 'active'
         and (i.intake_year is null or i.intake_year = coalesce(p.new_year, i.intake_year));
      get diagnostics v_n = row_count;  -- 0 when a lock or the same-month guard kept the row as it was
      if v_n = 1 then v_filled := v_filled + 1; v_courses := v_courses || p.course_id; end if;
    end if;
    insert into pipeline.course_intake_dates(intake_id, course_id, provider_id, proposal_id, outcome, reason, periods, start_precision, deadline_kind, deadline_text,
                                             start_quote, deadline_quote, before_value, after_value, applied_at, page_quote, calendar_evidence_id, calendar_url, rule,
                                             calendar_set, inputs_fp, next_action, next_revisit_at)
    select p.intake_id, p.course_id, p.provider_id, p.proposal_id,
           case when p.outcome = 'filled' and v_n = 0 then 'skipped' else p.outcome end,
           case when p.outcome = 'filled' and v_n = 0 then 'kept by a lock or the same-month guard' else p.reason end,
           p.periods, p.start_precision, p.deadline_kind, p.deadline_text, p.start_quote, p.deadline_quote, p.before_value,
           (select jsonb_build_object('year', i.intake_year, 'start_date', i.start_date, 'application_deadline', i.application_deadline) from catalogue.course_intakes i where i.id = p.intake_id), now(),
           p.page_quote, p.calendar_evidence_id, p.calendar_url, p.rule, p.calendar_set, p.inputs_fp,
           case when p.outcome = 'filled' and v_n = 0 then 'human_decision_required' else p.next_action end,
           case when p.outcome = 'filled' and v_n = 0 then null else p.next_revisit_at end
    on conflict (intake_id) do update set proposal_id = excluded.proposal_id, outcome = excluded.outcome, reason = excluded.reason, periods = excluded.periods,
           start_precision = excluded.start_precision, deadline_kind = excluded.deadline_kind, deadline_text = excluded.deadline_text, start_quote = excluded.start_quote,
           deadline_quote = excluded.deadline_quote, before_value = excluded.before_value, after_value = excluded.after_value, applied_at = excluded.applied_at,
           page_quote = excluded.page_quote, calendar_evidence_id = excluded.calendar_evidence_id, calendar_url = excluded.calendar_url, rule = excluded.rule,
           calendar_set = excluded.calendar_set, inputs_fp = excluded.inputs_fp, next_action = excluded.next_action, next_revisit_at = excluded.next_revisit_at;
    insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, rule, outcome, reason, next_action, next_revisit_at, calendar_set, proposal_id, periods,
                                                   start_precision, deadline_kind, before_value, after_value, page_quote, start_quote, deadline_quote, calendar_url, calendar_evidence_id, bounded)
    select d.intake_id, d.course_id, d.provider_id, d.rule, d.outcome, d.reason, d.next_action, d.next_revisit_at, d.calendar_set, d.proposal_id, d.periods,
           d.start_precision, d.deadline_kind, d.before_value, d.after_value, d.page_quote, d.start_quote, d.deadline_quote, d.calendar_url, d.calendar_evidence_id, p_course_ids is not null
      from pipeline.course_intake_dates d where d.intake_id = p.intake_id;
    v_by := jsonb_set(v_by, array[coalesce(case when p.outcome = 'filled' and v_n = 0 then 'human_decision_required' else p.next_action end, 'unclassified')],
                      to_jsonb(coalesce((v_by->>coalesce(case when p.outcome = 'filled' and v_n = 0 then 'human_decision_required' else p.next_action end, 'unclassified'))::int, 0) + 1));
    v_n := null;
  end loop;
  if cardinality(v_courses) > 0 then
    -- 11 Nov 2026 (F-INT): never wait for the search-document writer. search-refresh-requested (every 10 minutes) holds it for 1-2 minutes and started at the
    -- same second as this job (10:26, 11:26): the apply waited, hit the statement time-out and rolled back every planned row. When the writer is busy the
    -- courses go to the search refresh queue instead (search.refresh_requests, processed by that job's next run).
    if pg_try_advisory_xact_lock(hashtext('cf247:search_course_documents_writer')) then  -- fixed: the one writer lock (W27)
      perform search.refresh_course_enrichment_scoped_v1((select array_agg(distinct x) from unnest(v_courses) x), true);
    else
      insert into search.refresh_requests(requested_by)
      values ('intake dates apply: ' || coalesce(cardinality((select array_agg(distinct x) from unnest(v_courses) x)), 0) || ' courses (search writer busy)');
    end if;
  end if;
  return jsonb_build_object('enabled', true, 'looked_at', v_seen, 'filled', v_filled, 'provenance_completed', v_prov, 'courses', coalesce(cardinality((select array_agg(distinct x) from unnest(v_courses) x)), 0),
                            'bounded', p_course_ids is not null, 'selected_courses', coalesce(cardinality(p_course_ids), 0), 'by_next_action', v_by);
end $function$
