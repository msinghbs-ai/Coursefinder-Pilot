-- CF-247 s1273 (S2-RM-Design; DR-19 slice 1, SS-Programme-Control assignment 26 Nov 2026 19:18 AEDT: "End-to-end record-level processing
-- correlation. Detection of failed or missing processing handoffs. Automatic failure classification ... Distinguish recoverable data exceptions
-- from genuine software defects").
-- What it adds (read-only; no table, job, worker, queue or planner; reuses the PIM interfaces):
--   security.pim_record_trace_v1(course, field)  one course, every registered course field (or one): the interface 2 facts
--     (security.field_state_v1), the field's producer from pipeline.field_register (fills, reader, offered to the enrich planner), the recent
--     processing attempts (pipeline.field_enrich_items), the open absence finding (pipeline.course_field_absence), open Layer 4 items, and a
--     diagnosis: one class from the evidence, never a guess:
--       not_applicable | verified | protected_hold | in_progress | operational_failure | data_exception | software_defect | partial | awaiting_first_read
--     operational_failure means the recorded reason is an account or service failure (HTTP 4xx/5xx, key or rate limit, time-out), not evidence
--     about the source: it recovers by retry once the limit or service recovers, and is never counted as a data exception.
--     software_defect means the platform cannot recover it by itself: the field register declares no automatic producer (reader = none, the
--     #1201 academic entry hand-off class), or the latest attempt failed at least pim.trace_failure_attempts times with no absence finding.
--     data_exception means evidence explains the gap (an absence finding, or a skipped attempt with its reason) and names when it may be revisited.
--     The answer lists the permitted actions the existing controls already offer; it runs nothing.
--     It also reads the course back through the consumer reads (Website v3 and Zoho v3, by stable key) and says whether each returned it, with
--     the time (DR-19 shared contract item 1, design 2026-11-26-dr19-record-journey-and-diagnosis-design.md section 5; Website v2 is not read).
--   security.pim_provider_trace_v1(provider, field, class, limit)  the same diagnosis over a provider's active courses (at most
--     pim.trace_max_courses), counted by class and detail, and, when a class is given, the records in it (course, class, detail, revisit),
--     at most pim.trace_list_limit: the per-record list behind Data Delivery's holds and recoveries (shared contract item 2).
--   public.admin_pim_record_trace_v1 / public.admin_pim_provider_trace_v1  Viewer and above (security.current_role_rank() >= 1).
-- Field register columns: reader holds the producer kind (enrich, coverage, register, none); fills holds its description.
-- G1: no job. G2: four settings (pim.trace_failure_attempts, pim.trace_recent_items, pim.trace_max_courses, pim.trace_list_limit). G3: no consumer object; 75/48
-- asserted before and after. Manual locks, cron, AI and spend untouched ($0). Nothing dropped.
-- Replaces: nothing.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function definitions

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1273_base on commit drop as
  select (select count(*) from pipeline.manual_locks) locks, (select count(*) from cron.job where active) jobs;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'pim.trace_failure_attempts', 'PIM trace: failed attempts that mark a software defect',
  'A course field whose latest read failed at least this many times, with no evidence explaining the gap, is diagnosed as a software defect for engineering, not a data exception.',
  'number', '3'::jsonb, 1, 20, 'attempts', 1601, 'PIM', 'security.pim_record_trace_v1 (s1273)', 'CF-247 s1273 DR-19 slice 1'),
 ('pipeline', 'pim.trace_recent_items', 'PIM trace: processing attempts shown per field',
  'How many of the most recent processing attempts the record trace returns for each course field.',
  'number', '5'::jsonb, 1, 50, 'attempts', 1602, 'PIM', 'security.pim_record_trace_v1 (s1273)', 'CF-247 s1273 DR-19 slice 1'),
 ('pipeline', 'pim.trace_max_courses', 'PIM trace: courses read per provider diagnosis',
  'The provider diagnosis reads at most this many of the provider''s active courses (ordered by id) and says when it stopped short.',
  'number', '1000'::jsonb, 50, 5000, 'courses', 1603, 'PIM', 'security.pim_provider_trace_v1 (s1273)', 'CF-247 s1273 DR-19 slice 1'),
 ('pipeline', 'pim.trace_list_limit', 'PIM trace: records listed per class',
  'When the provider diagnosis is asked for one class, it lists at most this many of its records.',
  'number', '200'::jsonb, 10, 2000, 'records', 1604, 'PIM', 'security.pim_provider_trace_v1 (s1273)', 'CF-247 s1273 DR-19 slice 1')
on conflict (toolset_key, key) do nothing;

create or replace function security.pim_record_trace_v1(p_course uuid, p_field text default null, p_consumer boolean default true)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $f$
declare
  v_course record; r record; v_last record; v_w jsonb; v_z jsonb; v_cc text;
  v_state jsonb; v_items jsonb; v_abs jsonb; v_l4 jsonb; v_out jsonb := '[]'::jsonb;
  v_class text; v_detail text; v_revisit timestamptz; v_actions jsonb; v_listed boolean;
  v_attempts int := greatest(security.pipeline_num_v1('pim.trace_failure_attempts', 3)::int, 1);
  v_recent int := greatest(security.pipeline_num_v1('pim.trace_recent_items', 5)::int, 1);
  v_enrich text[] := array(select e.field from security.enrich_fields_v1() e);
begin
  select c.id, c.provider_id, c.lifecycle_status, c.stable_key into v_course from catalogue.courses c where c.id = p_course;
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
    v_detail := null; v_revisit := null; v_actions := '[]'::jsonb;
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
    elsif v_last.state = 'waiting' or v_last.leased_until > now() then
      v_class := 'in_progress'; v_detail := 'attempt ' || v_last.state || coalesce(', leased until ' || v_last.leased_until::text, '');
    elsif coalesce(v_abs->>'reason', case when v_last.state in ('failed', 'skipped') then v_last.reason end, '') ~* '(HTTP [45][0-9]{2}|key limit|rate limit|quota|timed? ?out|time-out|503|502|ECONNRESET)' then
      v_class := 'operational_failure';
      v_detail := 'account or service failure, not evidence about the source: ' || left(coalesce(v_abs->>'reason', v_last.reason), 200);
      v_revisit := (v_abs->>'next_eligible_at')::timestamptz;
      v_actions := '["retry once the account limit or service recovers (existing retry and revisit)"]'::jsonb;
    elsif v_abs is not null then
      v_class := 'data_exception'; v_detail := (v_abs->>'absence_class') || ': ' || coalesce(v_abs->>'reason', '');
      v_revisit := (v_abs->>'next_eligible_at')::timestamptz;
      v_actions := jsonb_build_array(case
        when v_abs->>'absence_class' in ('needs_source_discovery', 'identity_unresolved') then 'source or course-page identity recovery by the field''s owner lane'
        when v_abs->>'absence_class' in ('not_on_this_page', 'on_other_stored_page') then 'read another stored page of the provider (bounded revisit, security.pim_source_revisit_v1)'
        else 'automatic revisit when eligible' end);
    elsif v_last.state = 'failed' and coalesce(v_last.attempts, 0) >= v_attempts then
      v_class := 'software_defect'; v_detail := 'latest read failed ' || v_last.attempts || ' times with no evidence explaining the gap: ' || coalesce(left(v_last.reason, 200), 'no reason');
      v_actions := '["engineering review of the reader for this field"]'::jsonb;
    elsif r.reader = 'none' then
      v_class := 'software_defect'; v_detail := 'no automatic producer: the field register declares none (' || coalesce(r.fills, '') || ')';
      v_actions := '["engineering: add the producer through the existing planner step"]'::jsonb;
    elsif v_last.state = 'skipped' then
      v_class := 'data_exception'; v_detail := 'skipped: ' || coalesce(left(v_last.reason, 200), 'no reason');
      v_actions := '["automatic revisit when its input changes"]'::jsonb;
    elsif v_state->>'completeness' = 'partial' then
      v_class := 'partial'; v_detail := 'part of the value is held';
    else
      v_class := 'awaiting_first_read';
      v_detail := 'applicable gap with no attempt and no absence finding' || case when r.reader = 'enrich' and not v_listed then '; not offered to the enrich planner' else '' end;
      v_actions := '["planner or gap queue picks it up"]'::jsonb;
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'field', r.field, 'label', r.label,
      'producer', jsonb_build_object('kind', r.reader, 'description', r.fills, 'planner_listed', v_listed),
      'state', v_state, 'attempts', v_items, 'absence', v_abs, 'layer4', v_l4,
      'diagnosis', jsonb_build_object('class', v_class, 'detail', v_detail, 'revisit_after', v_revisit, 'permitted_actions', v_actions)));
  end loop;
  if p_consumer and v_course.stable_key is not null then
    -- the consumer reads need an education country; the provider's own country is used only to ask whether the course is returned
    select ct.iso_alpha2 into v_cc from catalogue.providers p join ref.countries ct on ct.id = p.country_id where p.id = v_course.provider_id;
    v_w := (public.website_v3_course(v_course.stable_key, v_cc))::jsonb;
    v_z := (public.zoho_v3_course(v_course.stable_key, v_cc))::jsonb;
  end if;
  return jsonb_build_object('course_id', v_course.id, 'provider_id', v_course.provider_id, 'lifecycle_status', v_course.lifecycle_status,
                            'checked_at', now(), 'fields', v_out,
                            'consumer', jsonb_build_object('checked_at', clock_timestamp(),
                              'website_v3', jsonb_build_object('returned', v_w ? 'item' and not (v_w ? 'error'), 'error', v_w->'error'->>'code'),
                              'zoho_v3', jsonb_build_object('returned', v_z ? 'item' and not (v_z ? 'error'), 'error', v_z->'error'->>'code'),
                              'website_v2', 'not read (frozen surface)', 'asked_as', v_cc))
                            || case when p_consumer then '{}'::jsonb else jsonb_build_object('consumer', null) end;
end $f$;
comment on function security.pim_record_trace_v1(uuid, text, boolean) is
  'PIM DR-19 (s1273): one course''s processing chain per registered course field (interface 2 facts, producer, recent attempts, absence finding, open Layer 4 items) and an evidence-only diagnosis class with the permitted actions. Read-only.';

create or replace function security.pim_provider_trace_v1(p_provider uuid, p_field text, p_class text default null, p_limit int default null)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $f$
declare
  v_max int := greatest(security.pipeline_num_v1('pim.trace_max_courses', 1000)::int, 1);
  v_total int; v_rows jsonb;
  v_list int := least(greatest(coalesce(p_limit, security.pipeline_num_v1('pim.trace_list_limit', 200)::int), 1), greatest(security.pipeline_num_v1('pim.trace_list_limit', 200)::int, 1));
begin
  if p_field is null or not exists (select 1 from pipeline.field_register f where f.field = p_field and f.level = 'course') then
    raise exception 'INVALID_INPUT: a registered course field is required' using errcode = '22023';
  end if;
  select count(*) into v_total from catalogue.courses c where c.provider_id = p_provider and c.lifecycle_status = 'active';
  with d as (
    select c.id course_id, (security.pim_record_trace_v1(c.id, p_field, false)->'fields'->0->'diagnosis') g
      from (select id from catalogue.courses where provider_id = p_provider and lifecycle_status = 'active' order by id limit v_max) c)
  select jsonb_build_object(
           'by_class', coalesce((select jsonb_object_agg(k, n) from (select g->>'class' k, count(*) n from d group by 1) z), '{}'::jsonb),
           'top_details', coalesce((select jsonb_agg(jsonb_build_object('class', k, 'detail', t, 'courses', n) order by n desc)
                                      from (select g->>'class' k, left(g->>'detail', 160) t, count(*) n from d
                                             where g->>'class' not in ('verified', 'not_applicable') group by 1, 2 order by 3 desc limit 10) z), '[]'::jsonb),
           'records', case when p_class is null then null else coalesce((select jsonb_agg(jsonb_build_object('course_id', course_id, 'class', g->>'class',
                                  'detail', left(g->>'detail', 200), 'revisit_after', g->>'revisit_after') order by course_id)
                                  from (select * from d where g->>'class' = p_class order by course_id limit v_list) z), '[]'::jsonb) end)
    into v_rows;
  return jsonb_build_object('provider_id', p_provider, 'field', p_field, 'class', p_class, 'active_courses', v_total,
                            'courses_read', least(v_total, v_max), 'stopped_short', v_total > v_max, 'checked_at', now()) || v_rows;
end $f$;
comment on function security.pim_provider_trace_v1(uuid, text, text, integer) is
  'PIM DR-19 (s1273): the record-trace diagnosis over a provider''s active courses for one field (at most pim.trace_max_courses), counted by class and detail. Read-only.';

create or replace function public.admin_pim_record_trace_v1(p_course uuid, p_field text default null)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $f$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 1 then  -- fixed: Viewer and above
    raise exception 'assigned StudySearch role required' using errcode = '42501';
  end if;
  return security.pim_record_trace_v1(p_course, p_field, true);
end $f$;
comment on function public.admin_pim_record_trace_v1(uuid, text) is 'PIM DR-19 (s1273): admin read of security.pim_record_trace_v1, Viewer and above.';

create or replace function public.admin_pim_provider_trace_v1(p_provider uuid, p_field text, p_class text default null, p_limit int default null)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $f$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 1 then  -- fixed: Viewer and above
    raise exception 'assigned StudySearch role required' using errcode = '42501';
  end if;
  return security.pim_provider_trace_v1(p_provider, p_field, p_class, p_limit);
end $f$;
comment on function public.admin_pim_provider_trace_v1(uuid, text, text, integer) is 'PIM DR-19 (s1273): admin read of security.pim_provider_trace_v1, Viewer and above.';

revoke all on function security.pim_record_trace_v1(uuid, text, boolean), security.pim_provider_trace_v1(uuid, text, text, integer),
                       public.admin_pim_record_trace_v1(uuid, text), public.admin_pim_provider_trace_v1(uuid, text, text, integer) from public, anon;
grant execute on function public.admin_pim_record_trace_v1(uuid, text), public.admin_pim_provider_trace_v1(uuid, text, text, integer) to authenticated;

do $p$
declare v jsonb := security.consumer_api_check_v1(); b record; t jsonb;
begin
  select * into b from pg_temp.s1273_base;
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
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('pim', 'pim_record_trace', 'security.pim_record_trace_v1', jsonb_build_object('change', 's1273', 'assignment', 'DR-19 slice 1'), null);
end $p$;
