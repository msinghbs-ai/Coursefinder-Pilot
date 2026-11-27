-- CF-247 s1295 (S2-RM-Design; DR-19 slice 4, SS-Programme-Control 27 Nov 2026 11:28 AEDT: "Complete DR-19 Diagnostic and Learning Integration"
-- without another diagnostic framework).
-- What changes (no table, job, dashboard or learning mechanism; existing integration issues, recovery knowledge, route register and link audience):
--   1. Provider trace performance: security.pim_provider_trace_v1 gains a page (offset, page size at most pim.trace_page_size). Every answer
--      accounts for the whole provider: active_courses, offset, courses_read, next_offset (null when complete), remaining, complete. Nothing is
--      cut silently; pim.trace_max_courses no longer applies. The authenticated read keeps under the 8-second statement limit by paging.
--   2. International applicability per field (diagnosis.international_applicability), from evidence only:
--      field_international_verified (international or all-audience rows held for the field), domestic_source_detected (only domestic rows, or
--      a domestic-tagged official link), audience_ambiguous (official links of different audiences, or an open integration issue naming the
--      course as a domestic-path suspect: s1294 treats a URL as a signal, not proof), international_source_verified (official link tagged
--      international by source integrity), shared_source_verified (tagged all or shared), international_not_checked (no tagged link).
--      Never inferred from a URL or from course availability. The trace returns the course's official_link_audience counts.
--   3. Recovery cause (diagnosis.recovery_cause): admission_or_publication_hold, no_reader_configuration, reader_not_qualified (route off and
--      its note says not qualified), qualified_reader_awaiting_activation (route off, or the field off in the AI routes), missing_official_source,
--      unsupported_website_structure, repeated_ineffective_extraction (pim.trace_failure_attempts reached), no_eligible_work_from_planner,
--      incorrect_source_audience, plus account_refusal, technical_failure, identity_unproven, insufficient_evidence.
--   4. Knowledge capture: history.integration_issues (the course's issues: status, root cause, remedy, verification) and history.knowledge (the
--      pipeline.ops_remedy_knowledge patterns those issues' remedies belong to, with their applied, verified, failed counts). Outcomes stay
--      counted once, where s1292 and s1294 record them; nothing is recorded here.
-- G1: no job. G2: pim.trace_page_size. G3: 75/48 asserted. Locks, cron and spend untouched. Nothing dropped.
-- Replaces: security.pim_record_trace_v1 body (s1282); security.pim_provider_trace_v1 body (s1273).
-- Retires: the pim.trace_max_courses cut in the provider trace (the setting stays; paging replaces it).
set local lock_timeout = '5s';  -- fixed: lock wait for the function definitions

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1295_base on commit drop as
  select (select count(*) from pipeline.manual_locks) locks, (select count(*) from cron.job where active) jobs;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'pim.trace_page_size', 'PIM trace: courses per provider page',
  'The provider diagnosis reads at most this many courses per call and returns the offset of the next page, so a large provider is read in pages within the statement time limit.',
  'number', '150'::jsonb, 10, 1000, 'courses', 1606, 'PIM', 'security.pim_provider_trace_v1 (s1295)', 'CF-247 s1295 DR-19 slice 4')
on conflict (toolset_key, key) do nothing;

create or replace function security.pim_record_trace_v1(p_course uuid, p_field text default null, p_consumer boolean default true)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $f$
declare
  v_course record; r record; v_last record; v_w jsonb; v_z jsonb; v_cc text; v_hist jsonb; v_key text; v_val jsonb; v_served boolean; v_match boolean; v_desc text; v_cause text; v_har text; v_aud jsonb; v_rc text; v_intl text; v_route record; v_issues jsonb; v_know jsonb; v_src jsonb;
  v_har_on boolean := security.pipeline_num_v1('har.ai_escalate_on', 0) >= 1;
  v_har_model text := nullif((select p.value #>> '{}' from pipeline.platform_toolset_settings p where p.toolset_key = 'pipeline' and p.key = 'har.ai_escalation_model'), '');
  v_map jsonb := '{"description":"description","official_url":"official_url","intakes":"intakes","deadline":"intakes","provider_tuition":"tuition","registered_tuition":"tuition","campus":"campuses","campus_city":"campus_city","duration":"duration_months","delivery":"delivery_modes","level":"study_level","field_of_study":"field_of_study_codes","english":"english_requirements","academic_entry":"entry"}'::jsonb;  -- fixed: field register field to Website v3 item key (schema mapping)
  v_state jsonb; v_items jsonb; v_abs jsonb; v_l4 jsonb; v_out jsonb := '[]'::jsonb;
  v_class text; v_detail text; v_revisit timestamptz; v_actions jsonb; v_listed boolean;
  v_attempts int := greatest(security.pipeline_num_v1('pim.trace_failure_attempts', 3)::int, 1);
  v_recent int := greatest(security.pipeline_num_v1('pim.trace_recent_items', 5)::int, 1);
  v_enrich text[] := array(select e.field from security.enrich_fields_v1() e);
  v_off text[] := array(select jsonb_array_elements_text(security.ai_enrich_routes_v1()->'off_fields'));
begin
  select c.id, c.provider_id, c.lifecycle_status, c.stable_key, c.description into v_course from catalogue.courses c where c.id = p_course;
  select jsonb_build_object('n_international', count(*) filter (where l.audience = 'international'), 'n_shared', count(*) filter (where l.audience in ('all', 'shared')),
           'n_domestic', count(*) filter (where l.audience = 'domestic'), 'n_untagged', count(*) filter (where l.audience is null),
           'n_distinct', count(distinct l.audience))
    into v_src from catalogue.course_links l where l.course_id = p_course and l.link_type = 'official_course' and coalesce(l.status, 'active') = 'active';
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
    v_detail := null; v_revisit := null; v_actions := '[]'::jsonb; v_cause := null; v_har := null; v_aud := null; v_rc := null; v_intl := null;
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
    -- DR-19 slice 4: recovery cause (what would make this field recoverable), from the existing route register, integration issues and attempts
    select s.enabled, s.migration_state, s.note into v_route from pipeline.ai_service_routes s
     where s.service_code = case r.field when 'description' then 'course_description' when 'academic_entry' then 'course_entry_requirements'
                                         when 'deadline' then 'course_other_fields' when 'intakes' then 'course_other_fields' when 'duration' then 'course_other_fields'
                                         when 'campus' then 'course_other_fields' when 'delivery' then 'course_other_fields' when 'english' then 'course_other_fields' end;
    select coalesce(jsonb_agg(jsonb_build_object('issue_ref', i.issue_ref, 'title', left(i.title, 140), 'status', i.status, 'root_cause_class', i.root_cause_class,
             'remedy_code', i.remedy_code, 'verification_outcome', i.verification_outcome, 'verified_at', i.verified_at) order by i.detected_at desc), '[]'::jsonb)
      into v_issues from (select * from pipeline.integration_issues i where p_course = any(i.course_ids) order by i.detected_at desc limit v_recent) i;
    -- knowledge: existing recovery knowledge patterns referenced by this course's issues (outcomes stay counted once, in ops_remedy_knowledge)
    select coalesce(jsonb_agg(distinct jsonb_build_object('code', k.code, 'title', left(k.title, 120), 'remedy_code', k.remedy_code, 'applied', k.applied, 'verified', k.verified,
             'failed', k.failed, 'no_yield_streak', k.no_yield_streak, 'auto_eligible', k.auto_eligible)), '[]'::jsonb)
      into v_know from pipeline.ops_remedy_knowledge k
     where k.remedy_code is not null and exists (select 1 from jsonb_array_elements(v_issues) x where x->>'remedy_code' = k.remedy_code);
    v_rc := case
      when v_class = 'protected_hold' then 'admission_or_publication_hold'
      when v_class in ('verified', 'not_applicable', 'in_progress') then null
      when r.reader = 'none' then 'no_reader_configuration'
      when v_route.enabled is false and coalesce(v_route.note, '') ~* 'not (been )?qualified' then 'reader_not_qualified'
      when v_route.enabled is false or r.field = any(v_off) then 'qualified_reader_awaiting_activation'
      when v_cause = 'no_source' then 'missing_official_source'
      when coalesce(v_abs->>'reason', v_last.reason, '') ~* '(unsupported|layout|structure|javascript|scanned|image-only|no text layer)' then 'unsupported_website_structure'
      when v_last.id is not null and coalesce(v_last.attempts, 0) >= v_attempts and v_last.state in ('failed', 'skipped') then 'repeated_ineffective_extraction'
      when v_class = 'awaiting_first_read' then 'no_eligible_work_from_planner'
      when v_cause in ('account_refusal', 'technical_failure') then v_cause
      when v_cause = 'identity_unproven' then 'identity_unproven'
      when v_cause = 'insufficient_evidence' then 'insufficient_evidence' end;
    -- international applicability (DR-19 slice 4): from the audience held on the course's official links (S1-Build source integrity) and,
    -- per field, the audience of the held rows. Never from a URL or from course availability.
    v_intl := case
      when coalesce((v_aud->>'international_held')::boolean, false) then 'field_international_verified'
      when coalesce((v_aud->>'domestic_only')::boolean, false) then 'domestic_source_detected'
      when (v_src->>'n_domestic')::int > 0 then 'domestic_source_detected'
      when (v_src->>'n_distinct')::int > 1 then 'audience_ambiguous'
      when exists (select 1 from jsonb_array_elements(v_issues) i where i->>'status' not in ('closed', 'resolved', 'verified') and (i->>'title') ~* 'domestic') then 'audience_ambiguous'
      when (v_src->>'n_international')::int > 0 then 'international_source_verified'
      when (v_src->>'n_shared')::int > 0 then 'shared_source_verified'
      else 'international_not_checked' end;
    if v_rc is null and v_intl = 'domestic_source_detected' and v_class not in ('verified', 'not_applicable', 'in_progress', 'protected_hold') then v_rc := 'incorrect_source_audience'; end if;
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
      'state', v_state, 'attempts', v_items, 'absence', v_abs, 'layer4', v_l4, 'history', v_hist || jsonb_build_object('integration_issues', v_issues, 'knowledge', v_know),
      'consumer_field', case when not p_consumer then null else jsonb_build_object('website_v3_key', v_key, 'served', v_served, 'matches_canonical', v_match,
        'delivery', case when v_key is null then 'not_mapped' when v_served is null then 'not_read'
                         when v_served and v_state->>'completeness' = 'verified' then 'served_and_verified'
                         when not v_served and v_state->>'completeness' = 'verified' then 'verified_not_served'
                         when v_served then 'served_not_verified' else 'neither' end) end,
      'diagnosis', jsonb_build_object('class', v_class, 'cause', v_cause, 'recovery_cause', v_rc, 'international_applicability', v_intl, 'detail', v_detail, 'revisit_after', v_revisit, 'permitted_actions', v_actions,
        'second_opinion', case when v_har is null then null else jsonb_build_object('har_class', v_har, 'ai_step_on', v_har_on, 'pinned_model', v_har_model) end),
      'audience', v_aud));
  end loop;
  return jsonb_build_object('course_id', v_course.id, 'official_link_audience', v_src, 'provider_id', v_course.provider_id, 'lifecycle_status', v_course.lifecycle_status,
                            'checked_at', now(), 'fields', v_out,
                            'consumer', jsonb_build_object('checked_at', clock_timestamp(),
                              'website_v3', jsonb_build_object('returned', v_w ? 'item' and not (v_w ? 'error'), 'error', v_w->'error'->>'code'),
                              'zoho_v3', jsonb_build_object('returned', v_z ? 'item' and not (v_z ? 'error'), 'error', v_z->'error'->>'code'),
                              'website_v2', 'not read (frozen surface)', 'asked_as', v_cc))
                            || case when p_consumer then '{}'::jsonb else jsonb_build_object('consumer', null) end;
end $f$;
comment on function security.pim_record_trace_v1(uuid, text, boolean) is
  'PIM DR-19 (s1273 to s1295): one course''s processing chain per registered course field, an evidence-only diagnosis (class, cause, recovery cause, international applicability) with permitted actions and the second-opinion class, audience, resolution history with integration issues and recovery knowledge, and field-level Website v3 delivery (presence, not accuracy). Read-only.';

create or replace function security.pim_provider_trace_v1(p_provider uuid, p_field text, p_class text, p_limit int, p_offset int)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $f$
declare
  v_page int := greatest(least(coalesce(p_limit, security.pipeline_num_v1('pim.trace_page_size', 150)::int), security.pipeline_num_v1('pim.trace_page_size', 150)::int), 1);
  v_off int := greatest(coalesce(p_offset, 0), 0);
  v_total int; v_rows jsonb; v_read int;
begin
  if p_field is null or not exists (select 1 from pipeline.field_register f where f.field = p_field and f.level = 'course') then
    raise exception 'INVALID_INPUT: a registered course field is required' using errcode = '22023';
  end if;
  select count(*) into v_total from catalogue.courses c where c.provider_id = p_provider and c.lifecycle_status = 'active';
  with d as materialized (
         select c.id course_id, (security.pim_record_trace_v1(c.id, p_field, false)->'fields'->0->'diagnosis') g
           from (select id from catalogue.courses where provider_id = p_provider and lifecycle_status = 'active' order by id offset v_off limit v_page) c)
  select (select count(*) from d), jsonb_build_object(
           'by_class', coalesce((select jsonb_object_agg(k, n) from (select g->>'class' k, count(*) n from d group by 1) z), '{}'::jsonb),
           'by_recovery_cause', coalesce((select jsonb_object_agg(k, n) from (select g->>'recovery_cause' k, count(*) n from d where g->>'recovery_cause' is not null group by 1) z), '{}'::jsonb),
           'by_international_applicability', coalesce((select jsonb_object_agg(k, n) from (select g->>'international_applicability' k, count(*) n from d group by 1) z), '{}'::jsonb),
           'top_details', coalesce((select jsonb_agg(jsonb_build_object('class', k, 'detail', t, 'courses', n) order by n desc)
                                      from (select g->>'class' k, left(g->>'detail', 160) t, count(*) n from d
                                             where g->>'class' not in ('verified', 'not_applicable') group by 1, 2 order by 3 desc limit 10) z), '[]'::jsonb),
           'records', case when p_class is null then null else coalesce((select jsonb_agg(jsonb_build_object('course_id', course_id, 'class', g->>'class',
                                  'recovery_cause', g->>'recovery_cause', 'detail', left(g->>'detail', 200), 'revisit_after', g->>'revisit_after') order by course_id)
                                  from d where g->>'class' = p_class), '[]'::jsonb) end)
    into v_read, v_rows;
  return jsonb_build_object('provider_id', p_provider, 'field', p_field, 'class', p_class, 'active_courses', v_total, 'offset', v_off, 'page_size', v_page,
                            'courses_read', v_read, 'next_offset', case when v_off + v_read < v_total then v_off + v_read end,
                            'remaining', greatest(v_total - v_off - v_read, 0), 'complete', v_off + v_read >= v_total, 'checked_at', now()) || v_rows;
end $f$;
comment on function security.pim_provider_trace_v1(uuid, text, text, integer, integer) is
  'PIM DR-19 (s1295): one page of the record-trace diagnosis over a provider''s active courses for one field (at most pim.trace_page_size), counted by class, recovery cause and international applicability, with whole-provider accounting (active_courses, next_offset, remaining, complete).';

create or replace function security.pim_provider_trace_v1(p_provider uuid, p_field text, p_class text default null, p_limit int default null)
returns jsonb language sql stable security definer set search_path = pg_catalog, public as $f$
  select security.pim_provider_trace_v1(p_provider, p_field, p_class, p_limit, 0)
$f$;
comment on function security.pim_provider_trace_v1(uuid, text, text, integer) is 'PIM DR-19 (s1273, s1295): the first page of the provider diagnosis (see the five-argument read).';

create or replace function public.admin_pim_provider_trace_v1(p_provider uuid, p_field text, p_class text, p_limit int, p_offset int)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $f$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 1 then  -- fixed: Viewer and above
    raise exception 'assigned StudySearch role required' using errcode = '42501';
  end if;
  return security.pim_provider_trace_v1(p_provider, p_field, p_class, p_limit, p_offset);
end $f$;
comment on function public.admin_pim_provider_trace_v1(uuid, text, text, integer, integer) is 'PIM DR-19 (s1295): admin read of one provider diagnosis page, Viewer and above.';
revoke all on function security.pim_provider_trace_v1(uuid, text, text, integer, integer), public.admin_pim_provider_trace_v1(uuid, text, text, integer, integer) from public, anon;
grant execute on function public.admin_pim_provider_trace_v1(uuid, text, text, integer, integer) to authenticated;

do $p$
declare v jsonb := security.consumer_api_check_v1(); b record; t jsonb;
begin
  select * into b from pg_temp.s1295_base;
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> b.jobs then raise exception 'post-check: active job count changed'; end if;
  t := security.pim_record_trace_v1((select c.id from catalogue.courses c where c.lifecycle_status = 'active' order by c.id limit 1), null, false);
  if exists (select 1 from jsonb_array_elements(t->'fields') e where e->'diagnosis'->>'class' is null or e->'diagnosis'->>'international_applicability' is null) then
    raise exception 'post-check: the trace did not diagnose every field: %', left(t::text, 400);
  end if;
end $p$;
