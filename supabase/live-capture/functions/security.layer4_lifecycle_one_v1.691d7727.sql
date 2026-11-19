CREATE OR REPLACE FUNCTION security.layer4_lifecycle_one_v1(p_kind text, p_ref text, p_full boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 (decision 12:24 §2, §3, §6): what happened to one Layer 4 item and what happens next, derived from the existing records only (no state
-- table). p_full adds the admission and publication checks (one card opened, or a decided item). The five distinctions are separate fields:
-- requested, executed (the operation ran), valid (the extraction passed its gates), approved (the Layer 4 decision), admitted, published.
declare v_n int := security.pipeline_num_v1('layer4.lifecycle_history_max', 8)::int;
        r pipeline.layer4_review_items; s pipeline.aer_read_supersessions; f pipeline.field_enrich_items; w pipeline.work_items; iv pipeline.layer4_interventions;
        fl pipeline.enrichment_flags; ob pipeline.provider_onboarding; e record; v_hist jsonb := '[]'; v_last jsonb; v_rep jsonb; v_pred jsonb; v_succ jsonb;
        v_first timestamptz; v_created timestamptz; v_upd timestamptz; v_rev timestamptz; v_auto timestamptz; v_entered timestamptz; v_next timestamptz; v_next_text text;
        v_decided timestamptz; v_admitted timestamptz; v_published timestamptz; v_status text; v_stage text; v_why text; v_owner text; v_entries int := 1;
        v_requested text := 'no'; v_executed text := 'not applicable'; v_valid text := 'not applicable'; v_approved text := 'not yet'; v_adm text := 'not yet'; v_pub text := 'not yet';
        v_rows int; v_pid uuid; v_open boolean := true; v_first_ev timestamptz; v_att record; v_recovery jsonb; v_course uuid; v_poll jsonb;
begin
  -- the Inbox's own audit rows for the item (every reviewer action, accepted or refused), newest first
  for e in select x.id, x.created_at, x.actor, x.detail from pipeline.admin_control_events x
            where x.area = 'layer4' and x.target = p_kind || ':' || p_ref and x.action in ('inbox_decide', 'inbox_navigate', 'inbox_refused') order by x.id desc limit v_n loop
    v_hist := v_hist || jsonb_build_array(jsonb_build_object('at', security.l4_time_v1(e.created_at), 'by', 'reviewer', 'action', e.detail->>'choice', 'ref', 'audit #' || e.id,
                'event_id', e.id, 'reason', e.detail->>'reason',
                'result', security.layer4_ack_normalise_v1(p_kind, e.detail->>'choice', null, e.detail->'result', null, null)
                          || jsonb_build_object('headline', security.layer4_ack_headline_v1(e.detail->>'choice',
                               security.layer4_ack_normalise_v1(p_kind, e.detail->>'choice', null, e.detail->'result', null, null),
                               coalesce(e.detail->'result'->'detail', e.detail->'result', '{}'::jsonb), e.created_at))));
    v_rev := greatest(v_rev, e.created_at);
  end loop;
  select min(x.created_at) into v_first_ev from pipeline.admin_control_events x where x.area = 'layer4' and x.target = p_kind || ':' || p_ref and x.action in ('inbox_decide', 'inbox_navigate');
  v_last := v_hist->0;
  if v_last is not null then v_requested := 'yes'; end if;

  if p_kind in ('course_link', 'aer_review', 'provider_description', 'no_page_first_run', 'conjoint_first_run') then
    select * into r from pipeline.layer4_review_items where id = p_ref::uuid;
    if r.id is null then return jsonb_build_object('kind', p_kind, 'ref', p_ref, 'found', false); end if;
    v_created := r.created_at; v_entered := r.created_at; v_status := r.status; v_decided := r.decided_at; v_open := r.status = 'pending';
    v_course := case when r.entity_type = 'course' then r.entity_id end;
    v_pid := coalesce((select c.provider_id from catalogue.courses c where c.id = v_course), case when r.entity_type = 'provider' then r.entity_id end);
    v_approved := case when r.status in ('approved', 'edited_approved') then 'yes' when r.status = 'pending' then 'not yet' else 'no (' || r.status || ')' end;
    -- first entered Layer 4: the earliest item of the same record and field, and up the chain of corrected reads (never reset by a re-read)
    select min(x.created_at), count(*) into v_first, v_entries from pipeline.layer4_review_items x where x.entity_id = r.entity_id and x.field_code = r.field_code;
    v_first := least(v_first, (with recursive ch(id, d) as (select r.id, 0 union all
                                  select s2.old_item_id, ch.d + 1 from ch join pipeline.aer_read_supersessions s2 on s2.new_item_id = ch.id where ch.d < 50)  -- fixed: cycle guard
                               select min(x.created_at) from ch join pipeline.layer4_review_items x on x.id = ch.id));
    select jsonb_build_object('ref', x.old_item_id, 'relation', 'this read replaced it (superseded)', 'at', security.l4_time_v1(x.closed_at), 'request', x.id)
      into v_pred from pipeline.aer_read_supersessions x where x.new_item_id = r.id order by x.requested_at desc limit 1;
    if r.field_code = 'course_entry_first_read' then
      v_executed := 'not asked'; v_valid := 'not asked';
      -- corrected reads asked for this item (the reviewer's, the scheduled job's and recovery's)
      -- observation 13:00 §2: each corrected read with its attempt number, operation (request and enrich item), reader times, the original and
      -- replacement reads and when the replacement entered Layer 4
      for v_att in select x.*, row_number() over (order by x.requested_at) n, f2.created_at f_start, f2.updated_at f_end, f2.state f_state, f2.reason f_reason,
                          f2.evidence_id f_ev, f2.cost_usd f_cost, nr.created_at new_at
                     from pipeline.aer_read_supersessions x left join pipeline.field_enrich_items f2 on f2.id = x.enrich_item_id
                     left join pipeline.layer4_review_items nr on nr.id = x.new_item_id
                    where x.old_item_id = r.id order by x.requested_at desc limit v_n loop
        v_hist := v_hist || jsonb_build_array(jsonb_build_object('at', security.l4_time_v1(v_att.requested_at),
                    'by', case when v_att.reason ilike 'Layer 4 recovery%' then 'reviewer' when v_att.reason ilike 'Human input needed%' then 'human input' else 'automatic' end,
                    'action', 'corrected read', 'attempt', v_att.n, 'ref', 'request ' || left(v_att.id::text, 8), 'reason', v_att.reason,
                    'operation', jsonb_build_object('request', v_att.id, 'enrich_item', v_att.enrich_item_id, 'job', v_att.job_id),
                    'reader', jsonb_strip_nulls(jsonb_build_object('started', security.l4_time_v1(v_att.f_start),
                                'completed', case when v_att.state <> 'requested' then security.l4_time_v1(coalesce(v_att.closed_at, v_att.f_end)) end,
                                'state', v_att.f_state, 'detail', v_att.f_reason, 'stored_copy', v_att.f_ev, 'cost_usd', v_att.f_cost)),
                    'original_read', v_att.old_item_id, 'replacement_read', v_att.new_item_id, 're_entered', security.l4_time_v1(v_att.new_at),
                    'result', jsonb_build_object('outcome', case v_att.state when 'requested' then 'queued' when 'superseded' then 'completed' else 'failed' end,
                                                 'headline', security.layer4_recovery_headline_v1(v_att.state, v_att.outcome, v_att.requested_at),
                                                 'reason', coalesce(v_att.outcome, case v_att.state when 'superseded' then 'complete: a new read replaced this one' else 'waiting for the reader' end),
                                                 'at', security.l4_time_v1(v_att.closed_at))));
        if v_recovery is null then v_recovery := v_hist->-1; end if;
        if v_att.reason not ilike 'Layer 4 recovery%' then v_auto := greatest(v_auto, v_att.requested_at, v_att.closed_at); end if;
        v_upd := greatest(v_upd, v_att.requested_at, v_att.closed_at);
      end loop;
      select * into s from pipeline.aer_read_supersessions x where x.old_item_id = r.id order by x.requested_at desc limit 1;
      if s.id is not null then
        v_requested := 'yes';
        select * into f from pipeline.field_enrich_items x where x.id = s.enrich_item_id;
        v_executed := case when s.state <> 'requested' then 'yes, ' || coalesce(security.l4_time_v1(s.closed_at)->>'text', '') when f.state in ('leased', 'ai') then 'running' else 'waiting for the reader' end;
        v_valid := case s.state when 'superseded' then 'yes (complete)' when 'refused' then 'no: ' || coalesce(s.outcome, 'refused') else 'not yet' end;
        v_stage := case when s.state = 'requested' and f.state in ('leased', 'ai') then 'executing' when s.state = 'requested' then 'scheduled'
                        when s.state = 'refused' then 'failed' else 'completed' end;
        if s.state = 'superseded' then
          v_succ := (select jsonb_build_object('ref', s.new_item_id, 'relation', 'replaced by a corrected read', 'status', x.status, 'at', security.l4_time_v1(s.closed_at),
                                               're_entered', security.l4_time_v1(x.created_at),
                                               'complete', case when p_full then (security.course_entry_gate_v1(x.id, '{}'::uuid[])->>'complete')::boolean end)
                       from pipeline.layer4_review_items x where x.id = s.new_item_id);
        end if;
      end if;
      v_rep := security.layer4_reread_repeat_v1(r.id);
      select * into w from pipeline.work_items x where x.lane = 'aer_technical' and x.entity = p_ref and x.work_kind = 'l4_item';
      if w.id is not null then
        v_auto := greatest(v_auto, w.last_attempt_at); v_upd := greatest(v_upd, w.updated_at); v_next := w.next_eligible_at;
        if w.next_eligible_at is not null and w.next_eligible_at > now() then v_next_text := 'technical recovery tries again (' || coalesce(w.failure_class, w.stage) || ')'; end if;
      end if;
      select * into iv from pipeline.layer4_interventions x where x.lane = 'aer_item' and x.entity = p_ref and x.status in ('ai_pending', 'awaiting_input', 'resuming')
       order by x.id desc limit 1;
      if iv.id is null then
        select i.* into iv from pipeline.layer4_aer_recovery_actions a join pipeline.layer4_interventions i on i.id = a.intervention_id
         where a.review_item_id = r.id and i.status in ('ai_pending', 'awaiting_input', 'resuming') order by a.id desc limit 1;
      end if;
      if (p_full or not v_open) then
        select count(*), max(x.updated_at) into v_rows, v_admitted from catalogue.course_entry_requirements x
         where x.course_id = r.entity_id and x.provenance->>'review_item_id' = r.id::text and x.status = 'active';
        v_adm := case when v_rows > 0 then 'yes: ' || v_rows || ' row' || case when v_rows = 1 then '' else 's' end || ' active' when v_open then 'not yet' else 'no row active' end;
        select c.provider_id into v_pid from catalogue.courses c where c.id = r.entity_id;
        if v_rows > 0 and exists (select 1 from catalogue.courses c join catalogue.providers p on p.id = c.provider_id
                                    where c.id = r.entity_id and c.lifecycle_status = 'active' and p.publication_status = 'published') then
          v_pub := 'yes: course and university published'; v_published := v_admitted;
        elsif v_rows > 0 then v_pub := 'no: the course or its university is not published';
        end if;
      end if;
    elsif r.field_code in ('entry_matrix_first_run', 'entry_matrix_change') then
      select x.updated_at into v_auto from pipeline.entry_matrix_runs x where x.review_item_id = r.id order by x.created_at desc limit 1;
    elsif p_kind = 'course_link' and not v_open then
      v_adm := case when exists (select 1 from catalogue.course_links l where l.course_id = r.entity_id and l.link_type = 'official_course' and l.status = 'active')
                    then 'yes: the course''s official page is active' else 'no active official page' end;
    end if;
  elsif p_kind = 'held_scholarship' then
    for e in select x.created_at, x.status, x.decided_at, s2.publication_status from pipeline.scholarship_ai_reviews x left join scholarship.scholarships s2 on s2.id = x.scholarship_id
              where x.id = p_ref::bigint loop
      v_created := e.created_at; v_first := e.created_at; v_entered := e.created_at; v_status := e.status; v_decided := e.decided_at; v_open := e.status = 'pending';
      v_approved := case when e.status = 'pending' then 'not yet' else e.status end;
      v_pub := case when e.publication_status = 'published' then 'yes' when v_open then 'not yet' else 'no (' || coalesce(e.publication_status, 'no scholarship') || ')' end;
    end loop;
  elsif p_kind in ('website_needed', 'too_few_pages', 'nothing_ready', 'central_to_approve', 'onboarding_failed') then
    select * into ob from pipeline.provider_onboarding x where x.id = p_ref::uuid;
    v_created := ob.created_at; v_entered := ob.updated_at; v_status := ob.status; v_pid := ob.provider_id; v_auto := ob.updated_at; v_open := ob.status = 'stopped';
    select min(x.created_at), count(*) into v_first, v_entries from pipeline.provider_onboarding x where x.provider_id = ob.provider_id and x.status = 'stopped' and x.stop_reason = ob.stop_reason;
    -- what the decision started: the university's newer onboarding run
    for e in select x.id, x.status, x.created_at, x.updated_at, x.stop_reason from pipeline.provider_onboarding x
              where x.provider_id = ob.provider_id and x.created_at > ob.created_at order by x.created_at desc limit 1 loop
      v_stage := case when e.status = 'stopped' then 'failed' when e.status in ('done', 'completed', 'finished') then 'completed' else 'executing' end;
      v_auto := greatest(v_auto, e.updated_at); v_executed := e.status;
      v_why := case when e.status = 'stopped' then 'The new onboarding run stopped again: ' || coalesce(e.stop_reason, 'unknown') end;
    end loop;
  elsif p_kind in ('pages_not_found', 'site_down', 'fee_check', 'not_offered', 'not_on_site') then
    select * into fl from pipeline.enrichment_flags x where x.id = p_ref::bigint;
    -- Keep waiting moves flagged_at forward (asked again later); the first entry is the earliest of it and the first action on the item
    v_created := fl.flagged_at; v_entered := fl.flagged_at; v_status := fl.state; v_decided := fl.released_at; v_open := fl.state = 'raised';
    v_first := least(coalesce(fl.first_flagged_at, fl.flagged_at), v_first_ev); v_next := fl.next_check_at; v_auto := fl.updated_at; v_pid := fl.provider_id;
    if v_open and fl.next_check_at is not null then v_next_text := 'checked again automatically'; end if;
    if p_kind = 'site_down' and v_open then v_next_text := 'the site is checked again automatically; asked again after the waiting period'; end if;
  elsif p_kind = 'course_page_needed' then
    for e in select * from pipeline.course_page_needed x where x.course_id = p_ref::uuid loop
      v_created := e.created_at; v_first := e.created_at; v_entered := coalesce(e.last_refused_at, e.created_at); v_status := e.state; v_decided := e.decided_at;
      v_open := e.state = 'open'; v_auto := e.last_refused_at; v_upd := e.updated_at; v_pid := e.provider_id;
      if e.searches_requested > 0 and v_open then v_stage := 'scheduled'; v_next_text := 'the course-link search looks for the page again'; end if;
    end loop;
  elsif p_kind = 'counsellor_report' then
    for e in select * from pipeline.data_flags x where x.id = p_ref::uuid loop
      v_created := e.created_at; v_first := e.created_at; v_entered := e.created_at; v_status := e.status; v_decided := e.resolved_at; v_open := e.status = 'open';
    end loop;
  elsif p_kind = 'provider_departure' then
    for e in select * from pipeline.layer1_provider_departures x where x.id = p_ref::bigint loop
      v_created := e.created_at; v_first := e.created_at; v_entered := e.created_at; v_status := e.status; v_decided := e.reviewed_at; v_open := e.status = 'needs_review';
    end loop;
  elsif p_kind = 'intervention' then
    select * into iv from pipeline.layer4_interventions x where x.id = p_ref::bigint;
    v_created := iv.created_at; v_first := iv.created_at; v_entered := iv.created_at; v_status := iv.status; v_decided := iv.input_at; v_upd := iv.updated_at;
    v_open := iv.status in ('ai_pending', 'awaiting_input', 'resuming'); v_admitted := iv.admitted_at; v_published := iv.published_at;
    v_adm := case when iv.admitted_at is not null then 'yes' when v_open then 'not yet' else 'no' end;
    v_pub := case when iv.published_at is not null then 'yes' when v_open then 'not yet' else 'no' end;
    v_executed := case when iv.resumed_at is not null then 'yes, resumed' else 'not yet' end;
    v_valid := case when iv.verified_at is not null then 'yes: ' || coalesce(iv.verified_outcome, 'verified') else 'not yet' end;
    for e in select x.at, x.actor, x.action, x.status_before, x.status_after, x.result from pipeline.layer4_intervention_events x
              where x.intervention_id = iv.id and x.actor is null order by x.id desc limit v_n loop
      v_hist := v_hist || jsonb_build_array(jsonb_build_object('at', security.l4_time_v1(e.at), 'by', 'automatic', 'action', e.action,
                  'result', jsonb_build_object('outcome', coalesce(e.status_after, 'recorded'), 'reason', coalesce(e.result->>'request', e.result->>'state', e.result->>'reason'))));
      v_auto := greatest(v_auto, e.at);
    end loop;
  else
    return jsonb_build_object('kind', p_kind, 'ref', p_ref, 'found', false);
  end if;

  -- where the item stands (the shared lifecycle)
  if iv.id is not null and (p_kind = 'intervention' or v_open) and iv.status in ('ai_pending', 'awaiting_input', 'resuming') then
    v_stage := case iv.status when 'awaiting_input' then 'awaiting_input' else 'executing' end;
    v_owner := iv.assigned_to; v_next := coalesce(iv.next_action_at, v_next);
    v_next_text := case iv.status when 'awaiting_input' then 'Human input needed item ' || iv.id || ' waits for a person; the work resumes by itself when the input checks out'
                                  when 'ai_pending' then 'the stronger model analyses the failure once, then a person is asked'
                                  else 'the work resumes and is verified automatically' end;
  elsif p_kind = 'intervention' then
    v_stage := case when iv.verified_at is not null then 'verified' else 'resolved' end;
  end if;
  if not v_open then
    v_stage := case when v_status = 'superseded' then 'superseded' when v_stage in ('verified') then v_stage else 'resolved' end;
  elsif v_stage is null then
    v_stage := case v_last->'result'->>'outcome' when 'refused' then 'refused' when 'queued' then 'scheduled' when 'human_input' then 'awaiting_input'
                    when 'completed' then 'completed' when 'accepted' then 'accepted' when 'incomplete' then 'awaiting_input' else 'awaiting_decision' end;
  end if;
  v_why := coalesce(v_why, case
    when not v_open then null
    when v_stage = 'failed' and s.id is not null then 'The last corrected read was refused by the reader: ' || coalesce(s.outcome, 'refused') || '. The original read stays pending'
    when v_stage = 'awaiting_input' then 'Waiting for human input' || coalesce(' (item ' || iv.id || ')', '')
    when v_stage in ('scheduled', 'executing') then 'Waiting for the operation that was asked for'
    when v_stage = 'refused' then 'The last action was refused: ' || coalesce(v_last->'result'->>'reason', 'see the reason')
    else 'No reviewer action yet' end);
  if coalesce((v_rep->>'repeat')::boolean, false) and v_open then v_next_text := v_rep->>'alternative'; v_next := null; end if;
  if v_open and v_next_text is null then
    v_next := null;
    v_next_text := case
      when v_stage = 'scheduled' and s.id is not null then 'the entry reader reads the stored copy (job ' || left(s.job_id::text, 8) || ')'
      when v_stage = 'executing' then 'running now'
      when v_last->'result'->>'alternative' is not null and v_stage in ('refused', 'awaiting_input') then v_last->'result'->>'alternative'
      else 'a reviewer decides' end;
  end if;
  v_owner := coalesce(v_owner, case when v_stage in ('scheduled', 'executing') then 'the platform (automatic)' when v_open then 'Layer 4 reviewer' end);
  v_upd := greatest(v_upd, v_created, v_rev, v_auto, v_decided, v_entered);
  if v_open and v_stage in ('scheduled', 'executing') then
    v_poll := jsonb_build_object('every_seconds', security.pipeline_num_v1('layer4.lifecycle_poll_seconds', 15), 'max', security.pipeline_num_v1('layer4.lifecycle_poll_max', 40));
  end if;
  return jsonb_build_object('kind', p_kind, 'ref', p_ref, 'found', true, 'status', v_status, 'open', v_open, 'provider_id', v_pid, 'course_id', v_course,
    'recovery', v_recovery, 'poll', v_poll,
    'waiting', case when v_open then jsonb_build_object('hours', round(extract(epoch from now() - coalesce(v_first, v_created)) / 3600, 1),
                     'text', case when now() - coalesce(v_first, v_created) >= make_interval(days => 1)
                                  then extract(day from now() - coalesce(v_first, v_created))::int || ' d ' || extract(hour from now() - coalesce(v_first, v_created))::int || ' h'
                                  else extract(hour from now() - coalesce(v_first, v_created))::int || ' h ' || extract(minute from now() - coalesce(v_first, v_created))::int || ' min' end) end,
    'stage', v_stage,
    'stage_label', case v_stage when 'awaiting_decision' then 'Waiting for a reviewer' when 'accepted' then 'Accepted' when 'refused' then 'Refused'
                     when 'scheduled' then 'Scheduled' when 'executing' then 'Running' when 'completed' then 'Completed' when 'failed' then 'Failed: still pending'
                     when 'awaiting_input' then 'Waiting for human input' when 'verified' then 'Verified' when 'superseded' then 'Superseded' else 'Resolved' end,
    'why_pending', v_why, 'owner', v_owner,
    'next', case when v_open then jsonb_build_object('text', v_next_text, 'at', security.l4_time_v1(v_next)) end,
    'times', jsonb_strip_nulls(jsonb_build_object('first_entered', security.l4_time_v1(coalesce(v_first, v_created)), 'item_created', security.l4_time_v1(v_created),
      'last_updated', security.l4_time_v1(v_upd), 'last_reviewer_action', security.l4_time_v1(v_rev), 'last_automated_attempt', security.l4_time_v1(v_auto),
      'last_entered', security.l4_time_v1(v_entered), 'next_action', security.l4_time_v1(case when v_open then v_next end), 'decided', security.l4_time_v1(v_decided),
      'admitted', security.l4_time_v1(v_admitted), 'published', security.l4_time_v1(v_published))),
    'entries', v_entries,
    'steps', jsonb_build_object('requested', v_requested, 'executed', v_executed, 'valid', v_valid, 'approved', v_approved, 'admitted', v_adm, 'published', v_pub),
    'predecessor', v_pred, 'successor', v_succ,
    'repeat_guard', case when coalesce((v_rep->>'repeat')::boolean, false) then jsonb_build_object('action', 'reread_stored', 'why', v_rep->>'why', 'alternative', v_rep->>'alternative') end,
    'last_action', v_last,
    'history', (select coalesce(jsonb_agg(h order by (h->'at'->>'at')::timestamptz desc), '[]'::jsonb) from (select h from jsonb_array_elements(v_hist) h order by (h->'at'->>'at')::timestamptz desc limit v_n) z));
end $function$
