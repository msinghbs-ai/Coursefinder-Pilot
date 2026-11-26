-- CF-247 s1272 (S2-Build; DR-19, SS-Programme-Control 26 Nov 2026 19:19 AEDT, the Platform Admin's execution mandate "Intelligent monitoring and
-- human-assisted resolution"): the processing journey and diagnosis of one Layer 4 record, read by the new "Processing journey and diagnosis" fold on
-- every Layer 4 card. Design: admin docs/platform/2026-11-26-dr19-record-journey-and-diagnosis-design.md. Version above main's 20261129170000 and
-- the open 20261129190000 (s1261, #1675).
-- public.admin_record_journey_v1({kind, ref}), Curator and above (as the lifecycle read), returns eight stages (discovery, acquisition, extraction,
-- normalisation and mapping, validation, canonical admission, publication, website and Zoho verification), the stage where processing stopped and
-- why later stages are not reached, and the diagnosis: failure reason, stored evidence, attempts, reader and model, gate, the AI analysis the
-- platform already made (none is started here), similar resolved cases, references, recommended recovery, cost estimate, potential gain and
-- outcome. Unavailable (null with a reason), not verified (a state) and zero (0) are kept apart.
-- Read only: no table, no job, no model call, no spend. Not the consumer API (G3 checked). G1: no job. G2: two settings
-- (layer4.journey_similar_days, layer4.journey_similar_max). Locks untouched. Nothing dropped.
-- Replaces: nothing (new read beside the Layer 4 lifecycle read).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the new functions

create temp table s1272_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if to_regprocedure('security.layer4_item_lifecycle_v1(text,text)') is null or to_regprocedure('security.current_role_rank()') is null then
    raise exception 'pre-check: the Layer 4 lifecycle read or the role check is missing';
  end if;
end $pre$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
  ('pipeline', 'layer4.journey_similar_days', 'Record journey: days of similar resolved cases',
   'The Processing journey and diagnosis fold of a Layer 4 card lists items of the same field and hold reason that were decided in this many days, with their outcomes and references.',
   'number', to_jsonb(90), 7, 730, 'days', 891, 'Layer 4', 'security.record_journey_v1 (public.admin_record_journey_v1)', 'CF-247 s1272 (DR-19, SS-Programme-Control 26 Nov 2026 19:19)'),
  ('pipeline', 'layer4.journey_similar_max', 'Record journey: similar resolved cases listed',
   'How many of the latest similar resolved cases the fold lists by name. The counts by outcome are always the full counts.',
   'number', to_jsonb(5), 1, 20, 'cases', 892, 'Layer 4', 'security.record_journey_v1 (public.admin_record_journey_v1)', 'CF-247 s1272 (DR-19, SS-Programme-Control 26 Nov 2026 19:19)')
on conflict do nothing;

-- one stage of the journey
create or replace function security.record_journey_stage_v1(p_key text, p_label text, p_state text, p_reason text, p_at timestamptz, p_detail jsonb)
returns jsonb language sql immutable set search_path = '' as $function$
  select jsonb_strip_nulls(jsonb_build_object('key', p_key, 'label', p_label, 'state', p_state, 'reason', p_reason,
           'at', case when p_at is not null then to_char(p_at at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI') end,  -- fixed: Melbourne display time
           'detail', nullif(p_detail, '{}'::jsonb)))
$function$;
revoke all on function security.record_journey_stage_v1(text, text, text, text, timestamptz, jsonb) from public, anon, authenticated;

-- a lifecycle step text ("yes: 3 rows active", "not yet", "no ...") as a stage state
create or replace function security.record_journey_step_state_v1(p_text text)
returns text language sql immutable set search_path = '' as $function$
  select case when p_text is null then 'unavailable' when p_text ilike 'yes%' then 'done' when p_text ilike 'not yet%' then 'not_started'
              when p_text ilike 'not applicable%' or p_text ilike 'not asked%' then 'skipped' when p_text ilike 'no%' then 'failed' else 'not_started' end
$function$;
revoke all on function security.record_journey_step_state_v1(text) from public, anon, authenticated;

create or replace function security.record_journey_v1(p_kind text, p_ref text)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_days int := security.pipeline_num_v1('layer4.journey_similar_days', 90)::int;
        v_max int := security.pipeline_num_v1('layer4.journey_similar_max', 5)::int;
        lc jsonb := security.layer4_item_lifecycle_v1(p_kind, p_ref);
        r pipeline.layer4_review_items; ev pipeline.evidence_artifacts; li pipeline.layer3_interpretations; iv pipeline.layer4_interventions; wi pipeline.work_items;
        v_fe record; v_link text; v_gate jsonb; v_stages jsonb := '[]'::jsonb; v_stop int; v_out jsonb := '[]'::jsonb; st jsonb; i int;
        v_family text; v_subject text; v_course uuid; v_prov uuid; v_similar jsonb; v_refs jsonb := '[]'::jsonb; v_avg numeric; v_avg_n int;
        v_rows int; v_reads int := 0; v_steps jsonb := coalesce(lc->'steps', '{}'::jsonb); v_reason text; v_state text; v_ai jsonb; v_cost jsonb := '[]'::jsonb;
begin
  select f.* into v_fe from pipeline.field_enrich_items f where false;  -- the reader-run record has its shape before any branch reads it
  if p_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into r from pipeline.layer4_review_items where id = p_ref::uuid;
  end if;
  if r.id is not null then
    v_family := 'review_item';
    v_course := case when r.entity_type = 'course' then r.entity_id end;
    v_prov := coalesce((select c.provider_id from catalogue.courses c where c.id = v_course), case when r.entity_type = 'provider' then r.entity_id end);
    v_subject := coalesce((select coalesce(nullif(c.display_title, ''), c.canonical_title) from catalogue.courses c where c.id = v_course), '')
                 || coalesce(' · ' || (select coalesce(nullif(p.display_name, ''), p.canonical_name) from catalogue.providers p where p.id = v_prov), '');
    if r.evidence_id is not null then select * into ev from pipeline.evidence_artifacts where id = r.evidence_id; end if;
    if r.layer3_interpretation_id is not null then select * into li from pipeline.layer3_interpretations where id = r.layer3_interpretation_id; end if;
    if v_course is not null then
      select l.url into v_link from catalogue.course_links l where l.course_id = v_course and l.link_type = 'official_course' and l.status = 'active' order by l.id limit 1;  -- fixed: one link names the page
    end if;
    -- the reader run behind the item: the latest corrected read's enrich item, else the latest read of the same course and field
    select f.* into v_fe from pipeline.aer_read_supersessions s join pipeline.field_enrich_items f on f.id = s.enrich_item_id where s.old_item_id = r.id order by s.requested_at desc limit 1;
    if v_fe.id is null and v_course is not null then
      select f.* into v_fe from pipeline.field_enrich_items f where f.course_id = v_course and f.field = r.field_code order by f.updated_at desc limit 1;
    end if;
    select count(*) into v_reads from pipeline.aer_read_supersessions s where s.old_item_id = r.id;
    select * into wi from pipeline.work_items w where w.entity = p_ref and w.work_kind = 'l4_item' order by w.updated_at desc limit 1;
    select * into iv from pipeline.layer4_interventions x where (x.entity = p_ref) or (v_course is not null and x.course_id = v_course and x.field = r.field_code)
     order by x.id desc limit 1;
    if r.field_code = 'course_entry_first_read' and to_regprocedure('security.course_entry_gate_v1(uuid,uuid[])') is not null then
      execute 'select security.course_entry_gate_v1($1, $2)' into v_gate using r.id, '{}'::uuid[];
    end if;

    -- 1 discovery
    v_stages := v_stages || security.record_journey_stage_v1('discovery', 'Discovery',
      case when ev.source_url is not null or v_link is not null then 'done' when r.field_code = 'no_page_first_run' then 'failed' else 'not_started' end,
      case when ev.source_url is not null then 'Source page recorded with the stored evidence' when v_link is not null then 'The course''s official page is recorded'
           when r.field_code = 'no_page_first_run' then 'No official page was found for this course' else 'No source page is recorded for this record' end,
      ev.captured_at, jsonb_strip_nulls(jsonb_build_object('page', coalesce(ev.source_url, v_link))));
    -- 2 acquisition
    v_stages := v_stages || security.record_journey_stage_v1('acquisition', 'Acquisition',
      case when ev.id is null and (p_kind = 'course_link' or r.field_code in ('official_course_url', 'no_page_first_run')) then 'skipped'
           when ev.id is null then 'not_started' when ev.storage_path is not null or ev.content_hash is not null then 'done' else 'failed' end,
      case when ev.id is null and (p_kind = 'course_link' or r.field_code in ('official_course_url', 'no_page_first_run')) then 'A course page proposal needs no stored copy'
           when ev.id is null then 'No stored copy is linked to this item' when ev.storage_path is not null or ev.content_hash is not null then 'Stored copy kept'
           else 'The evidence row has no stored copy' end,
      ev.captured_at, jsonb_strip_nulls(jsonb_build_object('evidence_id', ev.id, 'type', ev.evidence_type, 'hash', left(ev.content_hash, 12))));
    -- 3 extraction
    v_stages := v_stages || security.record_journey_stage_v1('extraction', 'Extraction',
      case when r.proposed_value is not null and r.proposed_value <> 'null'::jsonb then 'done' else 'failed' end,
      case when r.proposed_value is not null and r.proposed_value <> 'null'::jsonb then 'The reader proposed a value' else 'The reader returned no value' || coalesce(': ' || v_fe.reason, '') end,
      coalesce(v_fe.updated_at, r.created_at),
      jsonb_strip_nulls(jsonb_build_object('reader', v_fe.source, 'model', v_fe.model, 'reader_state', v_fe.state, 'attempts', v_fe.attempts)));
    -- 4 normalisation and mapping
    v_stages := v_stages || security.record_journey_stage_v1('normalisation', 'Normalisation and mapping',
      case when li.id is not null and coalesce(li.validator_result->>'ok', li.validator_result->>'valid', 'true') = 'false' then 'failed'
           when li.id is not null and li.status in ('reserved', 'running') then 'not_started'
           when li.id is not null then 'done'
           when r.proposed_value is not null and r.proposed_value <> 'null'::jsonb then 'done' else 'not_started' end,
      case when li.id is not null and coalesce(li.validator_result->>'ok', li.validator_result->>'valid', 'true') = 'false'
             then 'The AI interpretation failed its validator' || coalesce(': ' || coalesce(li.validator_result->>'reason', li.validator_result->>'error'), '')
           when li.id is not null then 'AI interpretation ' || li.status || coalesce(' (confidence ' || round(li.confidence, 2) || ')', '')
           when r.proposed_value is not null and r.proposed_value <> 'null'::jsonb then 'No AI interpretation is linked: the reader''s value is in the platform''s shape'
           else 'Nothing to map yet' end,
      li.call_completed_at,
      jsonb_strip_nulls(jsonb_build_object('model', li.aggregator_response_model, 'prompt', li.prompt_profile_version, 'task', li.task_class, 'cost_usd', li.estimated_cost_usd)));
    -- 5 validation
    v_stages := v_stages || security.record_journey_stage_v1('validation', 'Validation',
      case when r.status = 'pending' then 'held' when r.status in ('approved', 'edited_approved') then 'done' when r.status = 'superseded' then 'skipped' else 'failed' end,
      case when r.status = 'pending' then coalesce(case when (v_gate->>'complete') = 'false' then 'Held by the course entry completeness gate' end, nullif(r.escalation_reason, ''), lc->>'why_pending', 'Waiting for a reviewer')
           when r.status in ('approved', 'edited_approved') then 'Decided by a reviewer: ' || replace(r.status, '_', ' ')
           when r.status = 'superseded' then 'Replaced by a newer read' else 'Decided: ' || replace(r.status, '_', ' ') end,
      coalesce(r.decided_at, r.created_at),
      jsonb_strip_nulls(jsonb_build_object('hold_reason', nullif(r.escalation_reason, ''), 'gate', v_gate)));
    -- 6 canonical admission, 7 publication
    v_stages := v_stages || security.record_journey_stage_v1('admission', 'Canonical admission', security.record_journey_step_state_v1(v_steps->>'admitted'),
      coalesce(v_steps->>'admitted', 'The lifecycle read keeps no admission check for this item'), null, '{}'::jsonb);
    v_stages := v_stages || security.record_journey_stage_v1('publication', 'Publication', security.record_journey_step_state_v1(v_steps->>'published'),
      coalesce(v_steps->>'published', 'The lifecycle read keeps no publication check for this item'), null, '{}'::jsonb);
  elsif p_kind = 'intervention' and p_ref ~ '^[0-9]+$' then
    select * into iv from pipeline.layer4_interventions where id = p_ref::bigint;
    if iv.id is null then return jsonb_build_object('kind', p_kind, 'ref', p_ref, 'found', false); end if;
    v_family := 'intervention'; v_course := iv.course_id; v_prov := iv.provider_id;
    v_subject := coalesce(iv.subject, iv.missing_fact, '');
    select * into wi from pipeline.work_items w where w.id = iv.work_item_id;
    for i in 1..4 loop
      v_stages := v_stages || security.record_journey_stage_v1((array['discovery', 'acquisition', 'extraction', 'normalisation'])[i],
        (array['Discovery', 'Acquisition', 'Extraction', 'Normalisation and mapping'])[i], 'unavailable',
        'An intervention keeps its issue and evidence, not a record per stage', null, '{}'::jsonb);
    end loop;
    v_stages := v_stages || security.record_journey_stage_v1('validation', 'Validation',
      case when iv.status = 'awaiting_input' then 'held' when iv.status in ('ai_pending', 'resuming') then 'not_started' when iv.verified_at is not null or iv.resumed_at is not null then 'done' else 'failed' end,
      coalesce(iv.issue->>'summary', iv.issue->>'text', iv.issue #>> '{}', iv.missing_fact, iv.status), iv.updated_at, jsonb_strip_nulls(jsonb_build_object('required_input', iv.required_input)));
    v_stages := v_stages || security.record_journey_stage_v1('admission', 'Canonical admission', case when iv.admitted_at is not null then 'done' else 'not_started' end,
      case when iv.admitted_at is not null then 'Admitted' else 'Not admitted' end, iv.admitted_at, '{}'::jsonb);
    v_stages := v_stages || security.record_journey_stage_v1('publication', 'Publication', case when iv.published_at is not null then 'done' else 'not_started' end,
      case when iv.published_at is not null then 'Published' else 'Not published' end, iv.published_at, '{}'::jsonb);
  else
    if coalesce((lc->>'found')::boolean, false) is false then return jsonb_build_object('kind', p_kind, 'ref', p_ref, 'found', false); end if;
    v_family := 'lifecycle_only'; v_prov := nullif(lc->>'provider_id', '')::uuid; v_course := nullif(lc->>'course_id', '')::uuid;
    for i in 1..4 loop
      v_stages := v_stages || security.record_journey_stage_v1((array['discovery', 'acquisition', 'extraction', 'normalisation'])[i],
        (array['Discovery', 'Acquisition', 'Extraction', 'Normalisation and mapping'])[i], 'unavailable',
        'This kind of Layer 4 item keeps no record per stage', null, '{}'::jsonb);
    end loop;
    v_stages := v_stages || security.record_journey_stage_v1('validation', 'Validation',
      case when coalesce((lc->>'open')::boolean, false) then 'held' else 'done' end, coalesce(lc->>'why_pending', lc->>'stage_label'), null, '{}'::jsonb);
    v_stages := v_stages || security.record_journey_stage_v1('admission', 'Canonical admission', security.record_journey_step_state_v1(v_steps->>'admitted'),
      coalesce(v_steps->>'admitted', 'Not recorded for this kind of item'), null, '{}'::jsonb);
    v_stages := v_stages || security.record_journey_stage_v1('publication', 'Publication', security.record_journey_step_state_v1(v_steps->>'published'),
      coalesce(v_steps->>'published', 'Not recorded for this kind of item'), null, '{}'::jsonb);
  end if;
  -- 8 website and Zoho verification: no per-record check is recorded yet (shared contract item 1, S2-RM-Design)
  v_stages := v_stages || security.record_journey_stage_v1('verification', 'Website and Zoho verification', 'not_verified',
    'No per-record check of the website or Zoho read is recorded yet', null, '{}'::jsonb);

  -- the stopping stage, and why later stages are not reached
  select min(n) into v_stop from jsonb_array_elements(v_stages) with ordinality e(s, n) where s->>'state' in ('failed', 'held', 'not_started');  -- unavailable is no record, not a stop
  for st, i in select e.s, e.n from jsonb_array_elements(v_stages) with ordinality e(s, n) order by e.n loop
    if v_stop is not null and i > v_stop and st->>'state' in ('not_started', 'failed', 'held') then
      st := st || jsonb_build_object('state', 'waiting', 'reason', 'Not reached: waits for ' || lower(v_stages->(v_stop - 1)->>'label'));
    end if;
    v_out := v_out || jsonb_build_array(st);
  end loop;

  -- similar resolved cases: the same field and hold reason, decided in the window
  if r.id is not null then
    select jsonb_build_object('days', v_days,
             'counts', coalesce((select jsonb_object_agg(status, n) from (select x.status, count(*) n from pipeline.layer4_review_items x
                         where x.field_code = r.field_code and coalesce(x.escalation_reason, '') = coalesce(r.escalation_reason, '') and x.id <> r.id
                           and x.status <> 'pending' and x.decided_at >= now() - make_interval(days => v_days) group by x.status) q), '{}'::jsonb),
             'latest', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('ref', x.id, 'status', x.status,
                           'decided', to_char(x.decided_at at time zone 'Australia/Melbourne', 'DD Mon YYYY'), 'reference', x.change_control_ref,
                           'subject', (select coalesce(nullif(c.display_title, ''), c.canonical_title) from catalogue.courses c where c.id = x.entity_id))) order by x.decided_at desc)
                         from (select * from pipeline.layer4_review_items x where x.field_code = r.field_code and coalesce(x.escalation_reason, '') = coalesce(r.escalation_reason, '')
                                  and x.id <> r.id and x.status <> 'pending' and x.decided_at >= now() - make_interval(days => v_days)
                                order by x.decided_at desc limit v_max) x), '[]'::jsonb))
      into v_similar;
    select coalesce(jsonb_agg(distinct x.change_control_ref), '[]'::jsonb) into v_refs from pipeline.layer4_review_items x
     where (x.id = r.id or (x.field_code = r.field_code and coalesce(x.escalation_reason, '') = coalesce(r.escalation_reason, '') and x.status <> 'pending'
            and x.decided_at >= now() - make_interval(days => v_days))) and nullif(x.change_control_ref, '') is not null;
    -- cost: a stored-copy re-read by the deterministic reader is $0 (entry reads); an AI re-interpretation is this task's recent average
    if r.field_code = 'course_entry_first_read' and ev.id is not null then
      v_cost := v_cost || jsonb_build_array(jsonb_build_object('action', 'Re-read from the stored copy (deterministic reader)', 'usd', 0, 'basis', 'no AI and no Firecrawl'));
    end if;
    if li.id is not null then
      select round(avg(x.estimated_cost_usd), 6), count(*) into v_avg, v_avg_n
        from (select x.estimated_cost_usd from pipeline.layer3_interpretations x where x.task_class = li.task_class and x.call_completed_at is not null order by x.call_completed_at desc limit 50) x;  -- fixed: a recent sample
      v_cost := v_cost || jsonb_build_array(jsonb_build_object('action', 'AI re-interpretation (' || li.task_class || ')', 'usd', v_avg, 'basis', 'average of the last ' || v_avg_n || ' interpretations'));
    end if;
    v_rows := case when jsonb_typeof(r.proposed_value->'rows') = 'array' then jsonb_array_length(r.proposed_value->'rows')
                   when jsonb_typeof(r.proposed_value) = 'array' then jsonb_array_length(r.proposed_value) end;
  end if;
  v_ai := case when iv.id is not null and iv.ai_analysis is not null
               then jsonb_strip_nulls(jsonb_build_object('state', 'available', 'analysis', iv.ai_analysis, 'recommended', iv.recommended, 'required_input', iv.required_input,
                      'intervention', iv.id, 'status', iv.status))
               else jsonb_build_object('state', 'not_run', 'reason', 'No AI analysis has been run for this record. The platform runs one only when automatic recovery fails, so nothing was spent.') end;
  if iv.integration_issue_id is not null then v_refs := v_refs || jsonb_build_array('integration issue ' || iv.integration_issue_id::text); end if;
  v_reason := case when v_stop is not null then v_out->(v_stop - 1)->>'reason' end;
  v_state := case when v_stop is not null then v_out->(v_stop - 1)->>'state' end;

  return jsonb_build_object('kind', p_kind, 'ref', p_ref, 'found', true, 'family', v_family, 'subject', nullif(v_subject, ''),
    'course_id', v_course, 'provider_id', v_prov,
    'stopped_at', case when v_stop is not null then v_out->(v_stop - 1)->>'key' end,
    'stopped_label', case when v_stop is not null then v_out->(v_stop - 1)->>'label' end,
    'stopped_state', v_state, 'stopped_reason', v_reason,
    'stages', v_out,
    'diagnosis', jsonb_build_object(
      'failure_reason', v_reason,
      'evidence', case when ev.id is not null then jsonb_strip_nulls(jsonb_build_object('id', ev.id, 'page', ev.source_url, 'type', ev.evidence_type, 'hash', left(ev.content_hash, 12),
                         'stored', ev.storage_path is not null or ev.content_hash is not null, 'captured', to_char(ev.captured_at at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'))) end,
      'attempts', jsonb_strip_nulls(jsonb_build_object('events', jsonb_array_length(coalesce(lc->'history', '[]'::jsonb)), 'corrected_reads', v_reads,
                    'recovery_attempts', wi.total_attempts, 'failure_class', wi.failure_class, 'unresolved_blocker', wi.unresolved_blocker,
                    'automated_attempts', iv.automated_attempts, 'last', lc->'times'->'last_automated_attempt'->>'text')),
      'reader', case when r.id is null then null else jsonb_strip_nulls(jsonb_build_object('reader', v_fe.source, 'reader_model', v_fe.model, 'reader_cost_usd', v_fe.cost_usd,
                    'ai_model', li.aggregator_response_model, 'prompt', li.prompt_profile_version, 'confidence', li.confidence,
                    'recorded', li.id is not null or v_fe.id is not null,
                    'deterministic', case when li.id is null and v_fe.id is not null then v_fe.model is null end)) end,
      'gate', jsonb_strip_nulls(jsonb_build_object('hold_reason', nullif(r.escalation_reason, ''), 'gate', v_gate, 'why_pending', lc->>'why_pending')),
      'ai_diagnosis', v_ai,
      'similar', v_similar,
      'references', v_refs,
      'recommendation', jsonb_strip_nulls(jsonb_build_object('text', coalesce(iv.recommended->>'text', iv.recommended->>'action', iv.recommended #>> '{}', lc->'repeat_guard'->>'alternative', lc->'next'->>'text'),
                          'basis', case when iv.recommended is not null then 'AI analysis' when lc->'repeat_guard' is not null then 'repeat guard' when lc->'next' is not null then 'lifecycle next step' end,
                          'owner', lc->>'owner')),
      'cost', v_cost,
      'gain', case when r.id is not null then jsonb_strip_nulls(jsonb_build_object('field', r.field_code, 'courses', case when v_course is not null then 1 end,
                     'providers', case when v_course is null and v_prov is not null then 1 end, 'rows', v_rows,
                     'state', case when security.record_journey_step_state_v1(v_steps->>'admitted') = 'done' then 'realised' else 'potential' end)) end,
      'outcome', jsonb_strip_nulls(jsonb_build_object('status', coalesce(r.status, iv.status, lc->>'status'), 'decided', lc->'times'->'decided'->>'text',
                   'admitted', v_steps->>'admitted', 'published', v_steps->>'published'))),
    'lifecycle_stage', lc->>'stage_label',
    'generated_at', to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'));
end $function$;
comment on function security.record_journey_v1(text, text) is 'CF-247 s1272 (DR-19): the eight-stage processing journey and diagnosis of one Layer 4 record; read only, no model call.';
revoke all on function security.record_journey_v1(text, text) from public, anon, authenticated;

create or replace function public.admin_record_journey_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;  -- fixed: as the Layer 4 lifecycle read
  if nullif(btrim(coalesce(p_args->>'kind', '')), '') is null or nullif(btrim(coalesce(p_args->>'ref', '')), '') is null then
    raise exception 'INVALID_INPUT: give kind and ref' using errcode = '22023';
  end if;
  return security.record_journey_v1(btrim(p_args->>'kind'), btrim(p_args->>'ref'));
end $function$;
comment on function public.admin_record_journey_v1(jsonb) is 'CF-247 s1272 (DR-19): Processing journey and diagnosis fold of a Layer 4 card; Curator and above.';
revoke all on function public.admin_record_journey_v1(jsonb) from public, anon;
grant execute on function public.admin_record_journey_v1(jsonb) to authenticated;

do $post$
declare v jsonb := security.consumer_api_check_v1(); x jsonb; v_ref uuid;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1272_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1272_guard) then raise exception 'post-check: manual locks changed'; end if;
  if has_function_privilege('anon', 'public.admin_record_journey_v1(jsonb)', 'execute') or has_function_privilege('authenticated', 'security.record_journey_v1(text,text)', 'execute') then
    raise exception 'post-check: execute privileges are not as released';
  end if;
  -- a pending course entry read: eight stages, a stopping stage, and later stages marked as not reached
  select id into v_ref from pipeline.layer4_review_items where status = 'pending' and field_code = 'course_entry_first_read' order by created_at limit 1;
  if v_ref is not null then
    x := security.record_journey_v1('aer_review', v_ref::text);
    if jsonb_array_length(x->'stages') <> 8 or x->>'stopped_at' is null or x->'stages'->7->>'state' not in ('not_verified', 'waiting') then
      raise exception 'post-check: the journey of a pending entry read is not as designed: %', left(x::text, 400);
    end if;
  end if;
end $post$;
