-- CF-247 s1277 (S2-RM-Design; DR-19 slice 2, SS-Programme-Control 26 Nov 2026 21:36 AEDT: "Historical resolution references and realised
-- recovery gains ... Recover eligible records from the 554 identified operational failures through existing processing mechanisms ... Verify
-- actual canonical admission and field-level consumer delivery ... Do not treat course presence in a consumer API as proof of field-level accuracy").
-- Measured live 26 Nov 2026 21:40 to 22:10 AEDT (rolled back; head 20261129235000):
--   554 open course_field_absence rows (all published courses) record an account or service refusal, not evidence: OpenRouter "HTTP 403 Key
--   limit exceeded (weekly limit)" (280), "the AI service refused the call (key limit)" (224) and "HTTP 401 User not found" (50); 506
--   descriptions, 45 deadlines, 2 intakes, 1 English. Their items (source ai_stored) used all 3 attempts during the outage (330 failed, 224
--   skipped). All were due again between 13 and 23 Nov, but the worker claims only items in state 'ai' with fewer than 3 attempts, so nothing
--   re-read them: a missing recovery hand-off.
-- What changes:
--   1. Configurable classification: three rows in pipeline.recovery_error_classes (root_cause_class 'service_limit', owner 'operations') name the
--      AI account refusals. security.pim_operational_reason_v1(reason) reads those rows (plus HTTP 5xx, rate limit and time-out wording), and the
--      record trace uses it, so a new refusal wording is a row, not code.
--   2. security.pim_operational_recovery_v1(limit): for open absences whose reason is operational, on an active course with no manual lock on the
--      field, it hands the latest failed or skipped ai_stored item back to the existing AI worker (state 'ai', one more attempt: attempts at
--      most 2, so the 3-attempt cap stands), and resolves the absence (resolved_at; nothing deleted). The worker's own route caps and the
--      US$5.00 daily ceiling decide when each is read. It runs once here (live on deploy) and is the trace's permitted action afterwards.
--      Estimated cost: 554 x US$0.00038 (7-day average for course_description) = about US$0.21, inside today's cap.
--   3. security.pim_operational_recovery_measure_v1(): realised gain (DR-19 contract item 4): the re-armed items by state now, the fields filled,
--      and how many filled descriptions Website v3 serves equal to the catalogue.
--   4. security.pim_record_trace_v1 (replaced, same signature): resolution history per field (resolved absences, Layer 4 decisions with their
--      change_control_ref: contract item 3) and field-level consumer delivery (Website v3 serves a value for the field: served_and_verified,
--      verified_not_served, served_not_verified, neither; the description is compared with the catalogue text). Presence is reported as presence,
--      never as accuracy.
--   Admin reads: public.admin_pim_operational_recovery_measure_v1 (Viewer and above).
-- Reconciliation with s1261 and s1274: academic entry still reads software_defect "no automatic producer" because pipeline.field_register keeps
--   reader = 'none' for it although the s1274 planner step now queues entry reads. The register row is S1-RM-Design's (DR-16); it is reported
--   for them to update, not changed here.
-- G1: no job. G2: setting pim.op_recovery_batch. G3: 75/48 asserted. Manual locks untouched (and honoured). Cron unchanged. AI spend only through
-- the existing worker and its caps. Nothing dropped or deleted.
-- Replaces: security.pim_record_trace_v1 body (s1273), its operational-reason pattern.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function definitions

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1277_base on commit drop as
  select (select count(*) from pipeline.manual_locks) locks, (select count(*) from cron.job where active) jobs;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'pim.op_recovery_batch', 'PIM recovery: operational failures handed back per run',
  'At most this many open absences recorded from an account or service refusal are handed back to the existing AI worker in one recovery run.',
  'number', '600'::jsonb, 10, 5000, 'records', 1605, 'PIM', 'security.pim_operational_recovery_v1 (s1277)', 'CF-247 s1277 DR-19 slice 2')
on conflict (toolset_key, key) do nothing;

insert into pipeline.recovery_error_classes (pattern, error_class, root_cause_class, owner, title, repeat_setting, sort)
select v.pattern, 'ai_account_refusal', 'service_limit', 'operations', v.title, null, v.sort
  from (values ('%Key limit exceeded%', 'The AI service refused the call: the key''s spend limit was reached', 90),
               ('%refused the call (key limit%', 'The AI service refused the call (key limit), recorded by a re-read', 91),
               ('%"User not found."%', 'The AI service did not recognise the account key (HTTP 401)', 92)) v(pattern, title, sort)
 where not exists (select 1 from pipeline.recovery_error_classes e where e.pattern = v.pattern);

create or replace function security.pim_operational_reason_v1(p_reason text)
returns boolean language sql stable security definer set search_path = pg_catalog, public as $f$
  select coalesce(p_reason, '') <> '' and (
           exists (select 1 from pipeline.recovery_error_classes e where e.root_cause_class = 'service_limit' and p_reason ilike e.pattern)
        or p_reason ~* '(HTTP 5[0-9]{2}|rate limit|quota exceeded|timed? ?out|time-out|ECONNRESET)')
$f$;
comment on function security.pim_operational_reason_v1(text) is
  'PIM DR-19 (s1277): true when a recorded reason is an account or service failure (pipeline.recovery_error_classes rows with root_cause_class service_limit, or HTTP 5xx, rate limit, time-out wording), not evidence about the source.';

create or replace function security.pim_record_trace_v1(p_course uuid, p_field text default null, p_consumer boolean default true)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $f$
declare
  v_course record; r record; v_last record; v_w jsonb; v_z jsonb; v_cc text; v_hist jsonb; v_key text; v_val jsonb; v_served boolean; v_match boolean; v_desc text;
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
    elsif v_last.state in ('waiting', 'ai', 'leased') or v_last.leased_until > now() then
      v_class := 'in_progress'; v_detail := 'attempt ' || v_last.state || coalesce(', leased until ' || v_last.leased_until::text, '');
    elsif security.pim_operational_reason_v1(coalesce(v_abs->>'reason', case when v_last.state in ('failed', 'skipped') then v_last.reason end)) then
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
    -- resolution history (DR-19 contract item 3): absences resolved and Layer 4 decisions with their change-control reference
    select jsonb_build_object(
             'resolved_absences', coalesce((select jsonb_agg(jsonb_build_object('absence_class', x.absence_class, 'reason', left(x.reason, 160), 'classified_at', x.classified_at, 'resolved_at', x.resolved_at) order by x.resolved_at desc)
                                     from (select * from pipeline.course_field_absence a where a.course_id = p_course and a.field in (r.field, r.af) and a.resolved_at is not null order by a.resolved_at desc limit v_recent) x), '[]'::jsonb),
             'decided_layer4', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'field_code', x.field_code, 'status', x.status, 'decided_at', x.decided_at, 'change_control_ref', x.change_control_ref) order by x.decided_at desc)
                                     from (select * from pipeline.layer4_review_items l where l.entity_type = 'course' and l.entity_id = p_course and l.decided_at is not null
                                             and (l.field_code in (r.field, r.af) or (r.field = 'academic_entry' and l.field_code like 'course_entry%')) order by l.decided_at desc limit v_recent) x), '[]'::jsonb))
      into v_hist;
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
      'diagnosis', jsonb_build_object('class', v_class, 'detail', v_detail, 'revisit_after', v_revisit, 'permitted_actions', v_actions)));
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
  'PIM DR-19 (s1273, s1277): one course''s processing chain per registered course field (interface 2 facts, producer, attempts, absence, open Layer 4, resolution history), an evidence-only diagnosis with permitted actions, and field-level Website v3 delivery set against the platform state (presence, not accuracy). Read-only.';

create or replace function security.pim_operational_recovery_v1(p_limit int default null)
returns jsonb language plpgsql volatile security definer set search_path = pg_catalog, public as $f$
declare v_lim int := greatest(coalesce(p_limit, security.pipeline_num_v1('pim.op_recovery_batch', 600)::int), 1); v_items int; v_abs int; v_by jsonb;
begin
  create temp table if not exists pim_oprec_t (absence_course uuid, absence_field text, item_id bigint) on commit drop;
  truncate pim_oprec_t;
  insert into pim_oprec_t
  select a.course_id, a.field, i.id
    from pipeline.course_field_absence a
    join catalogue.courses c on c.id = a.course_id and c.lifecycle_status = 'active'
    join lateral (select e.id, e.state, e.source from pipeline.field_enrich_items e where e.course_id = a.course_id and e.field = a.field order by e.updated_at desc limit 1) i on true
   where a.resolved_at is null and security.pim_operational_reason_v1(a.reason)
     and i.state in ('failed', 'skipped') and i.source = 'ai_stored'
     and not exists (select 1 from pipeline.manual_locks m where m.entity_id = a.course_id and m.field = a.field)
   order by a.classified_at
   limit v_lim;
  update pipeline.field_enrich_items e
     set state = 'ai', attempts = least(e.attempts, 2), leased_until = null, updated_at = now(),
         reason = left('s1277 handed back after an account or service refusal; was: ' || coalesce(e.reason, ''), 500)
    from pim_oprec_t t where e.id = t.item_id and e.state in ('failed', 'skipped');
  get diagnostics v_items = row_count;
  update pipeline.course_field_absence a set resolved_at = now()
    from pim_oprec_t t where a.course_id = t.absence_course and a.field = t.absence_field and a.resolved_at is null;
  get diagnostics v_abs = row_count;
  select coalesce(jsonb_object_agg(absence_field, n), '{}'::jsonb) into v_by from (select absence_field, count(*) n from pim_oprec_t group by 1) z;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('pim', 'pim_operational_recovery', 'pipeline.field_enrich_items', jsonb_build_object('change', 's1277', 'items_handed_back', v_items, 'absences_resolved', v_abs, 'by_field', v_by,
                         'item_ids', (select coalesce(jsonb_agg(item_id), '[]'::jsonb) from pim_oprec_t)), null);
  return jsonb_build_object('items_handed_back', v_items, 'absences_resolved', v_abs, 'by_field', v_by, 'at', now());
end $f$;
comment on function security.pim_operational_recovery_v1(integer) is
  'PIM DR-19 (s1277): hands items whose open absence records an account or service refusal back to the existing AI worker for one more attempt (cap of 3 kept), honouring manual locks, and resolves those absences. The worker''s route caps and daily ceiling decide when they are read.';

create or replace function security.pim_operational_recovery_measure_v1()
returns jsonb language sql stable security definer set search_path = pg_catalog, public as $f$
  with ids as (select distinct (x #>> '{}')::bigint id from pipeline.admin_control_events k, jsonb_array_elements(coalesce(k.detail->'item_ids', '[]'::jsonb)) x
                where k.action = 'pim_operational_recovery'),
       t as (select e.id, e.course_id, e.field, e.state, e.cost_usd from pipeline.field_enrich_items e join ids on ids.id = e.id)
  select jsonb_build_object('items', (select count(*) from t),
           'by_state', coalesce((select jsonb_object_agg(state, n) from (select state, count(*) n from t group by 1) z), '{}'::jsonb),
           'filled_by_field', coalesce((select jsonb_object_agg(field, n) from (select field, count(*) n from t where state = 'filled' group by 1) z), '{}'::jsonb),
           'cost_usd', (select round(coalesce(sum(cost_usd), 0)::numeric, 4) from t),
           'measured_at', now())
$f$;
comment on function security.pim_operational_recovery_measure_v1() is
  'PIM DR-19 (s1277): realised gain of the operational-failure recovery: the handed-back items by state now, the fields filled and their cost.';

create or replace function public.admin_pim_operational_recovery_measure_v1()
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public as $f$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 1 then  -- fixed: Viewer and above
    raise exception 'assigned StudySearch role required' using errcode = '42501';
  end if;
  return security.pim_operational_recovery_measure_v1();
end $f$;
comment on function public.admin_pim_operational_recovery_measure_v1() is 'PIM DR-19 (s1277): admin read of the operational recovery measure, Viewer and above.';

revoke all on function security.pim_operational_reason_v1(text), security.pim_operational_recovery_v1(integer), security.pim_operational_recovery_measure_v1(),
                       public.admin_pim_operational_recovery_measure_v1() from public, anon;
grant execute on function public.admin_pim_operational_recovery_measure_v1() to authenticated;

do $r$
declare v jsonb; b record;
begin
  v := security.pim_operational_recovery_v1(null);
  raise notice 's1277 recovery: %', v;
  select * into b from pg_temp.s1277_base;
  if (select count(*) from pipeline.manual_locks) <> b.locks then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> b.jobs then raise exception 'post-check: active job count changed'; end if;
  v := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if exists (select 1 from pipeline.course_field_absence a where a.resolved_at is null and security.pim_operational_reason_v1(a.reason)
               and exists (select 1 from pipeline.field_enrich_items e where e.course_id = a.course_id and e.field = a.field and e.source = 'ai_stored' and e.state in ('failed', 'skipped')
                             and e.updated_at = (select max(e2.updated_at) from pipeline.field_enrich_items e2 where e2.course_id = a.course_id and e2.field = a.field))
               and not exists (select 1 from pipeline.manual_locks m where m.entity_id = a.course_id and m.field = a.field)
               and exists (select 1 from catalogue.courses c where c.id = a.course_id and c.lifecycle_status = 'active')) then
    raise exception 'post-check: an eligible operational failure was left';
  end if;
end $r$;
