-- CF-247 s1282 (S2-RM-Design; DR-19 slice 3, SS-Programme-Control 26 Nov 2026 22:32 AEDT: "AI-assisted diagnosis using existing qualified
-- services and permitted recovery actions ... controlled second-opinion processing ... Validate provider, course, field and international
-- audience identity ... Retain successful recovery strategies ... Distinguish account refusals, technical failures, insufficient evidence and
-- genuine no-source outcomes ... Do not introduce additional spending, protected admission overrides or a new recovery mechanism").
-- What changes (no table, job, route or spend; the stronger-model step is read, never switched on):
--   1. security.pim_failure_cause_v1(reason): account_refusal (pipeline.recovery_error_classes rows with root_cause_class service_limit) or
--      technical_failure (HTTP 5xx, rate limit, time-out); null otherwise.
--   2. security.pim_record_trace_v1 (replaced, same signature): diagnosis.cause beside the stable class: account_refusal, technical_failure,
--      insufficient_evidence, no_source (needs_source_discovery, source_unreachable, no statement on the allowed pages), identity_unproven,
--      software_defect. diagnosis.second_opinion names the existing human-assisted recovery class the case belongs to (academic entry:
--      aer_course_identity, aer_source_missing, aer_empty_read; intakes and deadline: intake_incomplete) with that framework's stronger-model
--      step state read live (har.ai_escalate_on, har.ai_escalation_model): today off, with no model pinned, so no second opinion runs and none
--      is invented. audience (academic entry, tuition): the held rows by audience, whether an international or all-audience row is held, and
--      whether only domestic rows are held.
--   3. Retained strategy: pipeline.work_recovery_policies row ai_account_refusal (defer_recheck, does not count an attempt, escalates as budget,
--      never to a person), the s1277 hand-back expressed as policy for policy-aware workers. The field-enrich worker's own attempt counting is
--      S1-Build's change.
-- G1: no job. G2: no new number (reads har.* settings). G3: 75/48 asserted. Locks, cron and spend untouched. Nothing dropped.
-- Replaces: security.pim_record_trace_v1 body (s1277).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function definitions

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1282_base on commit drop as
  select (select count(*) from pipeline.manual_locks) locks, (select count(*) from cron.job where active) jobs;

insert into pipeline.work_recovery_policies (failure_class, title, action, counts_attempt, max_attempts_key, recheck_key, escalate_as, escalate_when, root_cause, description)
values ('ai_account_refusal', 'The AI service refused the call for the account (key limit or unknown key)', 'defer_recheck', false, null, null, 'budget', 'never', 'service_limit',
        'Not evidence about the source. The item waits for the account limit to clear and is read again without using an attempt (DR-19 s1277 hand-back, kept as policy by s1282).')
on conflict (failure_class) do nothing;

create or replace function security.pim_failure_cause_v1(p_reason text)
returns text language sql stable security definer set search_path = pg_catalog, public as $f$
  select case when coalesce(p_reason, '') = '' then null
              when exists (select 1 from pipeline.recovery_error_classes e where e.root_cause_class = 'service_limit' and p_reason ilike e.pattern) then 'account_refusal'
              when p_reason ~* '(HTTP 5[0-9]{2}|rate limit|quota exceeded|timed? ?out|time-out|ECONNRESET)' then 'technical_failure' end
$f$;
comment on function security.pim_failure_cause_v1(text) is
  'PIM DR-19 (s1282): account_refusal (recovery_error_classes service_limit rows) or technical_failure (HTTP 5xx, rate limit, time-out) for a recorded reason; null otherwise.';
revoke all on function security.pim_failure_cause_v1(text) from public, anon;

create or replace function security.pim_record_trace_v1(p_course uuid, p_field text default null, p_consumer boolean default true)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $f$
declare
  v_course record; r record; v_last record; v_w jsonb; v_z jsonb; v_cc text; v_hist jsonb; v_key text; v_val jsonb; v_served boolean; v_match boolean; v_desc text; v_cause text; v_har text; v_aud jsonb;
  v_har_on boolean := security.pipeline_num_v1('har.ai_escalate_on', 0) >= 1;
  v_har_model text := nullif((select p.value #>> '{}' from pipeline.platform_toolset_settings p where p.toolset_key = 'pipeline' and p.key = 'har.ai_escalation_model'), '');
  v_map jsonb := '{"description":"description","official_url":"official_url","intakes":"intakes","deadline":"intakes","provider_tuition":"tuition","registered_tuition":"tuition","campus":"campuses","campus_city":"campus_city","duration":"duration_months","delivery":"delivery_modes","level":"study_level","field_of_study":"field_of_study_codes","english":"english_requirements","academic_entry":"entry"}'::jsonb;  -- fixed: field register field to Website v3 item key (schema mapping)
  v_state jsonb; v_items jsonb; v_abs jsonb; v_l4 jsonb; v_out jsonb := '[]'::jsonb;
  v_class text; v_detail text; v_revisit timestamptz; v_actions jsonb; v_listed boolean;
  v_attempts int := greatest(security.pipeline_num_v1('pim.trace_failure_attempts', 3)::int, 1);
  v_recent int := greatest(security.pipeline_num_v1('pim.trace_recent_items', 5)::int, 1);
  v_enrich text[] := array(select e.field from security.enrich_fields_v1() e);
begin
  select c.id, c.provider_id, c.lifecycle_status, c.stable_key, c.description into v_course from catalogue.courses c where c.id = p_course;
  if p_consumer and v_course.stable_key is not null then
    -- the consumer reads need an education country; the provider's own country is used only to ask what is returned
    select ct.iso_alpha2 into v_cc from catalogue.providers p join ref.countries ct on ct.id = p.country_id where p.id = v_course.provider_id;
    v_w := (public.website_v3_course(v_course.stable_key, v_cc))::jsonb;
    v_z := (public.zoho_v3_course(v_course.stable_key, v_cc))::jsonb;
  end if;
  if not found then raise exception 'INVALID_INPUT: course not found' using errcode = '22023'; end if;
  if p_field is not null and not exists (select 1 from pipeline.field_register f where f.field = p_field and f.level = 'course') then
    raise exception 'INVALID_INPUT: not a registered course field' using errcode = '22023';
  end if;
  for r in select f.field, f.label, f.fills, f.reader, coalesce(f.absence_field, f.field) af
             from pipeline.field_register f
            where f.level = 'course' and f.active and (p_field is null or f.field = p_field)
            order by f.sort loop
    v_state := security.field_state_v1(r.field, p_course);
    v_listed := r.field = any(v_enrich) or r.af = any(v_enrich);
    select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'state', i.state, 'source', i.source, 'attempts', i.attempts,
             'reason', left(i.reason, 240), 'model', i.model, 'cost_usd', i.cost_usd, 'evidence_id', i.evidence_id,
             'leased_until', i.leased_until, 'updated_at', i.updated_at) order by i.updated_at desc), '[]'::jsonb)
      into v_items
      from (select * from pipeline.field_enrich_items i where i.course_id = p_course and i.field in (r.field, r.af)
             order by i.updated_at desc limit v_recent) i;
    v_last := null;
    select i.id, i.state, i.attempts, i.reason, i.leased_until into v_last
      from pipeline.field_enrich_items i where i.course_id = p_course and i.field in (r.field, r.af)
     order by i.updated_at desc limit 1;
    v_abs := null;
    select jsonb_build_object('absence_class', a.absence_class, 'reason', a.reason, 'evidence_id', a.evidence_id, 'reader_version', a.reader_version,
             'next_eligible_at', a.next_eligible_at, 'reeval_trigger', a.reeval_trigger, 'classified_at', a.classified_at)
      into v_abs
      from pipeline.course_field_absence a where a.course_id = p_course and a.field in (r.field, r.af) and a.resolved_at is null
     order by a.classified_at desc limit 1;
    select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'field_code', l.field_code, 'status', l.status, 'created_at', l.created_at,
             'escalation_reason', left(l.escalation_reason, 200)) order by l.created_at), '[]'::jsonb)
      into v_l4
      from pipeline.layer4_review_items l
     where l.entity_type = 'course' and l.entity_id = p_course and l.decided_at is null and l.status = 'pending'
       and (l.field_code in (r.field, r.af) or (r.field = 'academic_entry' and l.field_code like 'course_entry%'));
    v_detail := null; v_revisit := null; v_actions := '[]'::jsonb; v_cause := null; v_har := null; v_aud := null;
    if coalesce((v_state->'applicability'->>'applicable')::boolean, true) = false then
      v_class := 'not_applicable'; v_detail := v_state->'applicability'->>'reason';
    elsif v_state->>'completeness' = 'verified' then
      v_class := 'verified'; v_detail := coalesce('freshness: ' || (v_state->>'freshness'), 'held and verified');
    elsif coalesce((v_state->>'protected_hold')::boolean, false) or jsonb_array_length(v_l4) > 0 or v_last.state = 'review' then
      v_class := 'protected_hold';
      v_detail := case when jsonb_array_length(v_l4) > 0 then 'open Layer 4 item' when v_last.state = 'review' then 'attempt waiting for review'
                       else 'manual lock or protected policy: automatic change stops' end;
      v_actions := case when jsonb_array_length(v_l4) > 0 or v_last.state = 'review' then '["Layer 4 decision (Approve, Approve except, Reject)"]'::jsonb
                        else '["none automatic: the protection stays"]'::jsonb end;
    elsif v_last.state in ('waiting', 'ai', 'leased') or v_last.leased_until > now() then
      v_class := 'in_progress'; v_detail := 'attempt ' || v_last.state || coalesce(', leased until ' || v_last.leased_until::text, '');
    elsif security.pim_operational_reason_v1(coalesce(v_abs->>'reason', case when v_last.state in ('failed', 'skipped') then v_last.reason end)) then
      v_class := 'operational_failure'; v_cause := security.pim_failure_cause_v1(coalesce(v_abs->>'reason', v_last.reason));
      v_detail := 'account or service failure, not evidence about the source: ' || left(coalesce(v_abs->>'reason', v_last.reason), 200);
      v_revisit := (v_abs->>'next_eligible_at')::timestamptz;
      v_actions := '["retry once the account limit or service recovers (existing retry and revisit)"]'::jsonb;
    elsif v_abs is not null then
      v_class := 'data_exception'; v_detail := (v_abs->>'absence_class') || ': ' || coalesce(v_abs->>'reason', '');
      v_cause := case when v_abs->>'absence_class' = 'identity_unresolved' then 'identity_unproven'
                      when v_abs->>'absence_class' in ('needs_source_discovery', 'source_unreachable', 'no_statement_on_allowed_pages', 'no_source') then 'no_source'
                      else 'insufficient_evidence' end;
      v_revisit := (v_abs->>'next_eligible_at')::timestamptz;
      v_actions := jsonb_build_array(case
        when v_abs->>'absence_class' in ('needs_source_discovery', 'identity_unresolved') then 'source or course-page identity recovery by the field''s owner lane'
        when v_abs->>'absence_class' in ('not_on_this_page', 'on_other_stored_page') then 'read another stored page of the provider (bounded revisit, security.pim_source_revisit_v1)'
        else 'automatic revisit when eligible' end);
    elsif v_last.state = 'failed' and coalesce(v_last.attempts, 0) >= v_attempts then
      v_class := 'software_defect'; v_cause := 'software_defect'; v_detail := 'latest read failed ' || v_last.attempts || ' times with no evidence explaining the gap: ' || coalesce(left(v_last.reason, 200), 'no reason');
      v_actions := '["engineering review of the reader for this field"]'::jsonb;
    elsif r.reader = 'none' then
      v_class := 'software_defect'; v_cause := 'software_defect'; v_detail := 'no automatic producer: the field register declares none (' || coalesce(r.fills, '') || ')';
      v_actions := '["engineering: add the producer through the existing planner step"]'::jsonb;
    elsif v_last.state = 'skipped' then
      v_class := 'data_exception'; v_cause := 'insufficient_evidence'; v_detail := 'skipped: ' || coalesce(left(v_last.reason, 200), 'no reason');
      v_actions := '["automatic revisit when its input changes"]'::jsonb;
    elsif v_state->>'completeness' = 'partial' then
      v_class := 'partial'; v_detail := 'part of the value is held';
    else
      v_class := 'awaiting_first_read';
      v_detail := 'applicable gap with no attempt and no absence finding' || case when r.reader = 'enrich' and not v_listed then '; not offered to the enrich planner' else '' end;
      v_actions := '["planner or gap queue picks it up"]'::jsonb;
    end if;
    -- resolution history (DR-19 contract item 3): absences resolved and Layer 4 decisions with their change-control reference
    select jsonb_build_object(
             'resolved_absences', coalesce((select jsonb_agg(jsonb_build_object('absence_class', x.absence_class, 'reason', left(x.reason, 160), 'classified_at', x.classified_at, 'resolved_at', x.resolved_at) order by x.resolved_at desc)
                                     from (select * from pipeline.course_field_absence a where a.course_id = p_course and a.field in (r.field, r.af) and a.resolved_at is not null order by a.resolved_at desc limit v_recent) x), '[]'::jsonb),
             'decided_layer4', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'field_code', x.field_code, 'status', x.status, 'decided_at', x.decided_at, 'change_control_ref', x.change_control_ref) order by x.decided_at desc)
                                     from (select * from pipeline.layer4_review_items l where l.entity_type = 'course' and l.entity_id = p_course and l.decided_at is not null
                                             and (l.field_code in (r.field, r.af) or (r.field = 'academic_entry' and l.field_code like 'course_entry%')) order by l.decided_at desc limit v_recent) x), '[]'::jsonb))
      into v_hist;
    -- controlled second opinion (DR-19 slice 3): the existing human-assisted recovery class this case belongs to, and whether that framework's
    -- stronger-model step is on (har.ai_escalate_on) with a pinned model (har.ai_escalation_model). Nothing is run from here.
    v_har := case when r.field = 'academic_entry' then case v_cause when 'identity_unproven' then 'aer_course_identity' when 'no_source' then 'aer_source_missing'
                                                                     when 'insufficient_evidence' then 'aer_empty_read' end
                  when r.field in ('intakes', 'deadline') and v_cause in ('insufficient_evidence', 'no_source') then 'intake_incomplete' end;
    -- international audience validity (DR-19 slice 3): which audience the held rows are for, where the field has an audience
    if r.field = 'academic_entry' then
      select jsonb_build_object('rows_by_audience', coalesce(jsonb_object_agg(coalesce(q.audience, 'unstated'), q.n), '{}'::jsonb),
               'international_held', coalesce(bool_or(q.audience in ('international', 'all')), false),
               'domestic_only', coalesce(bool_and(q.audience = 'domestic'), false))
        into v_aud from (select x.audience, count(*) n from catalogue.course_entry_requirements x where x.course_id = p_course and x.status = 'active' group by 1) q;
    elsif r.field in ('provider_tuition', 'registered_tuition') then
      select jsonb_build_object('rows_by_audience', coalesce(jsonb_object_agg(coalesce(q.audience, 'unstated'), q.n), '{}'::jsonb),
               'international_held', coalesce(bool_or(coalesce(q.audience, 'international') in ('international', 'all')), false),
               'domestic_only', coalesce(bool_and(q.audience = 'domestic'), false))
        into v_aud from (select x.audience, count(*) n from catalogue.course_fees x where x.course_id = p_course and coalesce(x.status, 'active') = 'active' group by 1) q;
    end if;
    -- field-level consumer delivery: whether Website v3 serves a value for this field, set against the platform's own state (presence is not accuracy)
    v_key := v_map->>r.field; v_served := null; v_match := null;
    if p_consumer and v_key is not null and v_w ? 'item' then
      v_val := v_w->'item'->v_key;
      v_served := v_val is not null and jsonb_typeof(v_val) <> 'null' and v_val::text not in ('[]', '{}', '""');
      if r.field = 'description' and v_served then v_match := btrim(v_val #>> '{}') = btrim(coalesce(v_course.description, '')); end if;
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'field', r.field, 'label', r.label,
      'producer', jsonb_build_object('kind', r.reader, 'description', r.fills, 'planner_listed', v_listed),
      'state', v_state, 'attempts', v_items, 'absence', v_abs, 'layer4', v_l4, 'history', v_hist,
      'consumer_field', case when not p_consumer then null else jsonb_build_object('website_v3_key', v_key, 'served', v_served, 'matches_canonical', v_match,
        'delivery', case when v_key is null then 'not_mapped' when v_served is null then 'not_read'
                         when v_served and v_state->>'completeness' = 'verified' then 'served_and_verified'
                         when not v_served and v_state->>'completeness' = 'verified' then 'verified_not_served'
                         when v_served then 'served_not_verified' else 'neither' end) end,
      'diagnosis', jsonb_build_object('class', v_class, 'cause', v_cause, 'detail', v_detail, 'revisit_after', v_revisit, 'permitted_actions', v_actions,
        'second_opinion', case when v_har is null then null else jsonb_build_object('har_class', v_har, 'ai_step_on', v_har_on, 'pinned_model', v_har_model) end),
      'audience', v_aud));
  end loop;
  return jsonb_build_object('course_id', v_course.id, 'provider_id', v_course.provider_id, 'lifecycle_status', v_course.lifecycle_status,
                            'checked_at', now(), 'fields', v_out,
                            'consumer', jsonb_build_object('checked_at', clock_timestamp(),
                              'website_v3', jsonb_build_object('returned', v_w ? 'item' and not (v_w ? 'error'), 'error', v_w->'error'->>'code'),
                              'zoho_v3', jsonb_build_object('returned', v_z ? 'item' and not (v_z ? 'error'), 'error', v_z->'error'->>'code'),
                              'website_v2', 'not read (frozen surface)', 'asked_as', v_cc))
                            || case when p_consumer then '{}'::jsonb else jsonb_build_object('consumer', null) end;
end $f$;
comment on function security.pim_record_trace_v1(uuid, text, boolean) is
  'PIM DR-19 (s1273, s1277, s1282): one course''s processing chain per registered course field, an evidence-only diagnosis (class and cause) with permitted actions and the human-assisted second-opinion class, audience validity, resolution history, and field-level Website v3 delivery (presence, not accuracy). Read-only.';

do $p$
declare v jsonb := security.consumer_api_check_v1(); b record; t jsonb;
begin
  select * into b from pg_temp.s1282_base;
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> b.jobs then raise exception 'post-check: active job count changed'; end if;
  t := security.pim_record_trace_v1((select c.id from catalogue.courses c where c.lifecycle_status = 'active' order by c.id limit 1), null, false);
  if jsonb_array_length(t->'fields') <> (select count(*) from pipeline.field_register where level = 'course' and active)
     or exists (select 1 from jsonb_array_elements(t->'fields') e where e->'diagnosis'->>'class' is null) then
    raise exception 'post-check: the trace did not diagnose every registered course field: %', left(t::text, 400);
  end if;
end $p$;
