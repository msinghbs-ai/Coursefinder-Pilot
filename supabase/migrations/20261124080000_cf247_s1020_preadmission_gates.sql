-- CF-247 s1020 (S1-Build; Platform Admin 24 Nov 2026 05:54 and 06:27 AEDT; UI-UX plan v1.2 slice 6): pre-admission gates at the table.
-- A machine write (no signed-in person, no cf.manual_edit) that would ADMIT a doubtful value is held and sent to Layer 4 instead of being
-- admitted silently. Gates act on new admissions only (an insert, or a row moving to active); an already active row is never demoted, so no
-- live value is withdrawn (Standing Authority Charter 5e); a doubtful refresh of an active row raises the Layer 4 item and keeps the row.
-- The pattern is the existing fee identity gate (security.course_fee_identity_gate_tg, 26 Oct 2026).
-- Measured live before this change (rolled back, 24 Nov 2026): 11,735 active current tuition rows, 335 outside 2026-2027 (215 in 2025, 109 in
-- 2028); 8,008 PTE or TOEFL iBT rows on courses holding IELTS, 2,132 with an overall score and four bands; 0 course-campus links across
-- providers. Existing rows are not changed; their gaps are reported by scripts/ci/validate-golden-courses.mjs (slice 6) and the digest.
-- 1. Fee year (catalogue.course_fees, provider_current_tuition): no fee year, a year before the current Melbourne year, more than
--    gates.fee_year_ahead years ahead, or older than the year already held for the course and audience -> status unverified and a pending
--    Layer 4 item 'provider_current_tuition' (Approve re-admits through security.layer4_tuition_apply_impl).
-- 2. English bands (catalogue.course_english_requirements): a PTE or TOEFL iBT row on a course that holds IELTS needs an overall score and
--    four bands (listening, reading, writing, speaking) or a stated minimum for each band; otherwise status unverified and a pending
--    Layer 4 item 'course_english' (Approve re-admits through security.layer4_course_english_apply_impl). Platform Admin 24 Nov 2026: held rows
--    surface as one Layer 4 group card per provider and test (security.layer4_groups_v1 groups waiting items by provider and kind).
-- 3. Campus (catalogue.course_campuses): a campus that is not on the course provider's own campus list is not linked; a pending Layer 4
--    notice 'campus_link' names it (Adelaide University included: its canonical campus list is its own).
-- Every gate decision is logged in pipeline.preadmission_gate_events (new). Each gate has an on switch (G2, Settings > Pipeline settings).
-- Consumer reads filter English and fee rows on status = 'active' (read live), so held rows are not served (G3 unchanged, checked).
-- Scholarship GPA (slice 6 gate 4) follows as s1021 with its own Layer 4 approve hook.
-- G1: no job. G2: switches and the year window are settings. Manual locks and active cron checked unchanged. Nothing dropped or deleted.
-- Replaces: silent admission of a fee with no or an out-of-window year, of a PTE or TOEFL row without bands, and of a cross-provider campus link.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads and the trigger changes

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1020_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1020_cron on commit drop as select count(*) n from cron.job where active;

-- Settings (G2)
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'gates.fee_year_on', 'Pre-admission gate: tuition fee year',
        'On (1): a machine-read tuition fee with no year, a year before the current one, too far ahead, or older than the year already held is held as unverified and sent to Layer 4 instead of being admitted. Off (0): fees are admitted as before. Fees already admitted are never withdrawn by this gate.',
        'number', to_jsonb(1), 0, 1, 'on/off', 3340, 'Pre-admission gates', 'security.gate_fee_year_tg (catalogue.course_fees)', 'CF-247 s1020: slice 6 pre-admission gates (Platform Admin 24 Nov 2026)'),
       ('pipeline', 'gates.fee_year_ahead', 'Pre-admission gate: fee years ahead accepted',
        'How many years after the current Melbourne year a machine-read tuition fee may be for and still be admitted (1: this year and next). A fee further ahead is held for Layer 4.',
        'number', to_jsonb(1), 0, 3, 'years', 3341, 'Pre-admission gates', 'security.gate_fee_year_tg (catalogue.course_fees)', 'CF-247 s1020: slice 6 pre-admission gates (Platform Admin 24 Nov 2026)'),
       ('pipeline', 'gates.english_bands_on', 'Pre-admission gate: PTE and TOEFL bands',
        'On (1): a machine-read PTE or TOEFL iBT requirement on a course that holds IELTS needs an overall score and all four bands (or a stated minimum for each band); otherwise it is held as unverified and sent to Layer 4. Requirements already admitted are never withdrawn by this gate.',
        'number', to_jsonb(1), 0, 1, 'on/off', 3342, 'Pre-admission gates', 'security.gate_english_bands_tg (catalogue.course_english_requirements)', 'CF-247 s1020: slice 6 pre-admission gates (Platform Admin 24 Nov 2026)'),
       ('pipeline', 'gates.campus_provider_on', 'Pre-admission gate: campus on the provider''s own list',
        'On (1): a machine-made link from a course to a campus that belongs to another provider is not made and is sent to Layer 4 as a notice. Off (0): links are made as before.',
        'number', to_jsonb(1), 0, 1, 'on/off', 3343, 'Pre-admission gates', 'security.gate_campus_provider_tg (catalogue.course_campuses)', 'CF-247 s1020: slice 6 pre-admission gates (Platform Admin 24 Nov 2026)')
on conflict do nothing;

-- Gate decision log
create table if not exists pipeline.preadmission_gate_events (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  gate text not null,
  entity_type text not null,
  entity_id uuid not null,
  row_ref text,
  outcome text not null,
  reason text not null,
  detail jsonb not null default '{}'::jsonb,
  review_item_id uuid
);
comment on table pipeline.preadmission_gate_events is 'CF-247 s1020: every pre-admission gate decision (held, notice raised on an active row, campus link not made) with its reason and Layer 4 item.';
create index if not exists preadmission_gate_events_at_idx on pipeline.preadmission_gate_events (at desc);
create index if not exists preadmission_gate_events_entity_idx on pipeline.preadmission_gate_events (entity_type, entity_id);
alter table pipeline.preadmission_gate_events enable row level security;
revoke all on pipeline.preadmission_gate_events from public, anon, authenticated;

insert into pipeline.layer4_field_registry (entity_type, field_code, display_label, value_kind, editability_class, min_role_rank, publication_sensitive, enabled, notes)
select 'course', 'campus_link', 'Campus link (pre-admission gate)', d.value_kind, d.editability_class, 3, false, true,
       'CF-247 s1020: a machine-made link to a campus on another provider''s list was not made; a person decides.'
  from pipeline.layer4_field_registry d where d.entity_type = 'course' and d.field_code = 'duration'
on conflict do nothing;

-- Shared: raise one pending Layer 4 item per entity and field, log the decision
CREATE OR REPLACE FUNCTION security.preadmission_gate_raise_v1(p_gate text, p_entity_type text, p_entity_id uuid, p_field text, p_evidence uuid,
  p_proposed jsonb, p_reason text, p_outcome text, p_row_ref text, p_detail jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_item uuid;
begin
  select l.id into v_item from pipeline.layer4_review_items l
   where l.entity_type = p_entity_type and l.entity_id = p_entity_id and l.field_code = p_field and l.status = 'pending' limit 1;
  if v_item is null then
    insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
    values (p_entity_type, p_entity_id, p_field, p_evidence, null, p_proposed,
            jsonb_build_object('source', 'preadmission_gate', 'gate', p_gate, 'state', p_outcome) || coalesce(p_detail, '{}'::jsonb), '{}'::jsonb, 'pending',
            'pre-admission gate (' || p_gate || '): ' || p_reason, 'CF-247 s1020 pre-admission gate')
    returning id into v_item;
  end if;
  insert into pipeline.preadmission_gate_events(gate, entity_type, entity_id, row_ref, outcome, reason, detail, review_item_id)
  values (p_gate, p_entity_type, p_entity_id, p_row_ref, p_outcome, p_reason, coalesce(p_detail, '{}'::jsonb), v_item);
  return v_item;
end $function$;
revoke all on function security.preadmission_gate_raise_v1(text, text, uuid, text, uuid, jsonb, text, text, text, jsonb) from public, anon, authenticated;

-- 1. Fee year
CREATE OR REPLACE FUNCTION security.gate_fee_year_tg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_y int; v_ahead int; v_held int; v_reason text; v_refresh boolean;
begin
  if new.fee_type is distinct from 'provider_current_tuition' or new.status is distinct from 'active' then return new; end if;
  if coalesce(current_setting('cf.manual_edit', true), '') = 'on' or auth.uid() is not null then return new; end if;
  if security.pipeline_num_v1('gates.fee_year_on', 1) < 1 then return new; end if;
  v_refresh := tg_op = 'UPDATE' and old.status = 'active';
  if v_refresh and old.fee_year is not distinct from new.fee_year then return new; end if;
  v_y := extract(year from now() at time zone 'Australia/Melbourne')::int;
  v_ahead := security.pipeline_num_v1('gates.fee_year_ahead', 1)::int;
  select max(f.fee_year) into v_held from catalogue.course_fees f
   where f.course_id = new.course_id and f.fee_type = new.fee_type and f.audience is not distinct from new.audience and f.status = 'active' and f.id <> new.id
     and f.fee_year between v_y and v_y + v_ahead;  -- only a held year inside the window counts, so a stray year never blocks a correct one
  v_reason := case when new.fee_year is null then 'the source states no fee year'
                   when new.fee_year < v_y then format('fee year %s is before the current year %s', new.fee_year, v_y)
                   when new.fee_year > v_y + v_ahead then format('fee year %s is more than %s year(s) after %s', new.fee_year, v_ahead, v_y)
                   when v_held is not null and new.fee_year < v_held then format('fee year %s is older than the year already held (%s)', new.fee_year, v_held) end;
  if v_reason is null then return new; end if;
  if not v_refresh then new.status := 'unverified'; end if;
  perform security.preadmission_gate_raise_v1('fee_year', 'course', new.course_id, 'provider_current_tuition', new.evidence_id,
    jsonb_build_object('amount', new.amount, 'currency', new.currency_code, 'basis', new.basis, 'fee_year', new.fee_year, 'audience', new.audience),
    v_reason, case when v_refresh then 'notice_active_kept' else 'held' end, new.id::text, jsonb_build_object('held_year', v_held, 'current_year', v_y));
  return new;
end $function$;

-- 2. English bands
CREATE OR REPLACE FUNCTION security.gate_english_bands_tg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_code text; v_cs jsonb; v_bands int; v_refresh boolean; v_reason text;
begin
  if new.status is distinct from 'active' then return new; end if;
  if coalesce(current_setting('cf.manual_edit', true), '') = 'on' or auth.uid() is not null then return new; end if;
  if security.pipeline_num_v1('gates.english_bands_on', 1) < 1 then return new; end if;
  select t.code into v_code from ref.english_tests t where t.id = new.english_test_id;
  if v_code is null or v_code not in ('PTE', 'TOEFL_IBT') then return new; end if;
  if not exists (select 1 from catalogue.course_english_requirements i join ref.english_tests ti on ti.id = i.english_test_id
                  where i.course_id = new.course_id and i.status = 'active' and ti.code = 'IELTS') then return new; end if;
  v_refresh := tg_op = 'UPDATE' and old.status = 'active';
  if v_refresh and old.overall_score is not distinct from new.overall_score and old.component_scores is not distinct from new.component_scores then return new; end if;
  v_cs := case when jsonb_typeof(new.component_scores) = 'object' then new.component_scores else '{}'::jsonb end;
  select count(*) into v_bands from jsonb_object_keys(v_cs) k where k in ('listening', 'reading', 'writing', 'speaking');
  if new.overall_score is not null and (v_bands = 4 or v_cs ? 'minimum_each') then return new; end if;
  v_reason := case when new.overall_score is null then v_code || ' has no overall score'
                   else format('%s has %s of the four bands (listening, reading, writing, speaking) and no minimum for each band', v_code, v_bands) end;
  if not v_refresh then new.status := 'unverified'; end if;
  perform security.preadmission_gate_raise_v1('english_bands', 'course', new.course_id, 'course_english', new.evidence_id,
    jsonb_build_object('english_requirements', jsonb_build_array(jsonb_build_object('test_code', v_code, 'overall_score', new.overall_score, 'component_scores', v_cs))),
    v_reason, case when v_refresh then 'notice_active_kept' else 'held' end, coalesce(new.id::text, ''), jsonb_build_object('test', v_code, 'bands', v_bands));
  return new;
end $function$;

-- 3. Campus on the provider's own list
CREATE OR REPLACE FUNCTION security.gate_campus_provider_tg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_course_provider uuid; v_campus_provider uuid; v_campus text;
begin
  if coalesce(current_setting('cf.manual_edit', true), '') = 'on' or auth.uid() is not null then return new; end if;
  if security.pipeline_num_v1('gates.campus_provider_on', 1) < 1 then return new; end if;
  if tg_op = 'UPDATE' and old.campus_id = new.campus_id and old.course_id = new.course_id then return new; end if;
  select c.provider_id into v_course_provider from catalogue.courses c where c.id = new.course_id;
  select k.provider_id, k.name into v_campus_provider, v_campus from catalogue.campuses k where k.id = new.campus_id;
  if v_campus_provider is null or v_course_provider is null or v_campus_provider = v_course_provider then return new; end if;
  perform security.preadmission_gate_raise_v1('campus_provider', 'course', new.course_id, 'campus_link', new.evidence_id,
    jsonb_build_object('campus_id', new.campus_id, 'campus', v_campus, 'campus_provider_id', v_campus_provider),
    format('campus %s is on another provider''s list; the link was not made', coalesce(v_campus, new.campus_id::text)), 'not_linked', new.campus_id::text,
    jsonb_build_object('course_provider_id', v_course_provider, 'campus_provider_id', v_campus_provider));
  if tg_op = 'UPDATE' then return old; end if;
  return null;
end $function$;

revoke all on function security.gate_fee_year_tg() from public, anon, authenticated;
revoke all on function security.gate_english_bands_tg() from public, anon, authenticated;
revoke all on function security.gate_campus_provider_tg() from public, anon, authenticated;

do $t$
declare v_sql text; v_try int;
begin
  foreach v_sql in array array[
    'create trigger course_fee_year_gate before insert or update on catalogue.course_fees for each row execute function security.gate_fee_year_tg()',
    'create trigger course_english_bands_gate before insert or update on catalogue.course_english_requirements for each row execute function security.gate_english_bands_tg()',
    'create trigger course_campus_provider_gate before insert or update on catalogue.course_campuses for each row execute function security.gate_campus_provider_tg()'] loop
    v_try := 0;
    loop
      begin
        perform set_config('lock_timeout', '3s', true);  -- fixed: lock wait per try
        execute v_sql;
        exit;
      exception when lock_not_available then
        v_try := v_try + 1;
        if v_try >= 5 then raise exception 'could not take the lock for: %', v_sql; end if;  -- fixed: tries before giving up
        perform pg_sleep(2);  -- fixed: pause between tries
      end;
    end loop;
  end loop;
  perform set_config('lock_timeout', '5s', true);  -- fixed: back to this change's lock wait
end $t$;

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1020_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1020_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pg_trigger where tgname in ('course_fee_year_gate', 'course_english_bands_gate', 'course_campus_provider_gate') and not tgisinternal) <> 3 then
    raise exception 'post-check: a gate trigger is missing';
  end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('gates.fee_year_on', 'gates.fee_year_ahead', 'gates.english_bands_on', 'gates.campus_provider_on')) <> 4 then
    raise exception 'post-check: a gate setting is missing';
  end if;
end $post$;
