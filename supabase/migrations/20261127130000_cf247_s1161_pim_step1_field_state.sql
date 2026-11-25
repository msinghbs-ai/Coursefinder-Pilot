-- CF-247 s1161 (S1-RM-Design; Global Autonomous PIM, Master Plan section 6.3 step 1, interface 2; design approved Platform Admin 25 Nov 2026 18:42 AEDT, Admin #1097).
-- Field state is five separate facts, never one status. security.field_state_v1(field, course) returns them for a course field:
--   applicability (security.field_applicable_v1, s1160);
--   completeness: verified when a value is held (a manually locked value counts), none when not; partial is not produced yet (no field has a rule for it);
--   freshness: the held value's last verified date for the course; the refresh window is step 5 and is not set here (window_days null);
--   source_finding where there is no value: the open pipeline.course_field_absence class and its evidence, else unknown;
--   protected_hold: a manual lock on the field (or 'all'); it never removes a held value from completeness;
--   processing: the latest pipeline.field_enrich_items state, a job fact shown on Scheduled jobs.
-- A field with no held-value test here (campus_city and the provider fields) reports completeness 'unmeasured' rather than a guess.
-- Monitoring acceptance (F-OPS.21): this is the per-field fact source for the Data Delivery progress read (next slice, s1162); it adds no screen, queue or job.
-- Read only; service role only. G1: no job. G2: no operational number. G3: no consumer API object touched (checked before and after). Locks and cron unchanged.
-- Replaces: none. Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: the guard reads and a rehearsal sample

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1161_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1161_cron on commit drop as select count(*) n from cron.job where active;

create or replace function security.field_state_v1(p_field text, p_course uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare r pipeline.field_register%rowtype; c catalogue.courses%rowtype; v_app jsonb; v_held boolean; v_measured boolean := true;
        v_abs record; v_enrich record; v_locked boolean; v_verified timestamptz;
begin
  select * into r from pipeline.field_register where field = p_field;
  v_app := security.field_applicable_v1(p_field, p_course);
  if r.field is null or r.entity_grain <> 'course' then
    return jsonb_build_object('field', p_field, 'applicability', v_app, 'completeness', 'unmeasured', 'freshness', null, 'source_finding', null, 'protected_hold', false, 'processing', null);
  end if;
  select * into c from catalogue.courses where id = p_course;
  if c.id is null then return null; end if;
  v_held := case p_field
    when 'official_url' then nullif(btrim(coalesce(c.course_url, '')), '') is not null
                              or exists (select 1 from catalogue.course_links l where l.course_id = c.id and l.link_type = 'official_course' and coalesce(l.status, 'active') = 'active')
    when 'level' then c.study_level_id is not null
    when 'field_of_study' then c.primary_field_id is not null
    when 'duration' then c.duration_value is not null
    when 'delivery' then nullif(btrim(coalesce(c.delivery_mode, '')), '') is not null
    when 'campus' then exists (select 1 from catalogue.course_campuses x where x.course_id = c.id)
    when 'international' then c.open_to_international is not null
    when 'provider_tuition' then exists (select 1 from catalogue.course_fees f where f.course_id = c.id and f.fee_type ~ '^provider_current_' and coalesce(f.status, 'active') = 'active')
    when 'registered_tuition' then exists (select 1 from catalogue.course_fees f where f.course_id = c.id and f.fee_type = 'tuition' and f.basis = 'registered_total_course' and coalesce(f.status, 'active') = 'active')
    when 'intakes' then exists (select 1 from catalogue.course_intakes i where i.course_id = c.id and i.status = 'active')
    when 'deadline' then exists (select 1 from catalogue.course_intakes i where i.course_id = c.id and i.status = 'active' and i.application_deadline is not null)
    when 'english' then exists (select 1 from catalogue.course_english_requirements e where e.course_id = c.id and coalesce(e.status, 'active') = 'active')
    when 'academic_entry' then exists (select 1 from catalogue.course_entry_requirements q where q.course_id = c.id and q.status = 'active')
    when 'description' then nullif(btrim(coalesce(c.description, '')), '') is not null
    else null end;
  if v_held is null then v_measured := false; end if;
  select exists (select 1 from pipeline.manual_locks lk where lk.entity = 'course' and lk.entity_id = c.id and lk.field in (p_field, 'all')) into v_locked;
  if v_held then v_verified := c.last_verified_at; end if;
  select a.absence_class, a.evidence_id, a.next_eligible_at into v_abs from pipeline.course_field_absence a
   where a.course_id = c.id and a.field = r.absence_field and a.resolved_at is null order by a.classified_at desc limit 1;
  select e.state, e.updated_at into v_enrich from pipeline.field_enrich_items e where e.course_id = c.id and e.field = p_field order by e.id desc limit 1;
  return jsonb_build_object(
    'field', p_field,
    'applicability', v_app,
    'completeness', case when not v_measured then 'unmeasured' when v_held then 'verified' else 'none' end,
    'freshness', case when v_held then jsonb_build_object('last_verified_at', v_verified, 'window_days', null) end,
    'source_finding', case when v_held or not v_measured then null
                           else jsonb_build_object('finding', coalesce(v_abs.absence_class, 'unknown'), 'evidence_id', v_abs.evidence_id, 'next_eligible_at', v_abs.next_eligible_at) end,
    'protected_hold', v_locked,
    'processing', case when v_enrich.state is null then null else jsonb_build_object('state', v_enrich.state, 'at', v_enrich.updated_at) end);
end $f$;
comment on function security.field_state_v1(text, uuid) is 'PIM interface 2 (s1161): the five facts of a course field (applicability, completeness, freshness, source finding, protected hold) plus the job fact; never one status.';
revoke all on function security.field_state_v1(text, uuid) from public, anon, authenticated;
grant execute on function security.field_state_v1(text, uuid) to service_role;

do $c$
declare v jsonb := security.consumer_api_check_v1(); s jsonb; v_cnt int; v_id uuid;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1161_locks) then raise exception 'guard: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1161_cron) then raise exception 'guard: active cron jobs changed'; end if;
  -- every course field answers with the five facts; a sample of courses
  select count(*) into v_cnt from (select c.id from catalogue.courses c where c.lifecycle_status = 'active' limit 20) c  -- fixed: a sample for the rehearsal
    cross join pipeline.field_register r
   where r.level = 'course' and (security.field_state_v1(r.field, c.id)->>'completeness') not in ('verified', 'none', 'unmeasured');
  if v_cnt <> 0 then raise exception 'guard: % unknown completeness answers', v_cnt; end if;
  select c.id into v_id from catalogue.courses c where c.lifecycle_status = 'active' and c.duration_value is not null limit 1;
  s := security.field_state_v1('duration', v_id);
  if s->>'completeness' <> 'verified' or s->'applicability'->>'applicable' <> 'true' or jsonb_typeof(s->'source_finding') <> 'null' then raise exception 'guard: a held duration is not verified: %', s; end if;
  select c.id into v_id from catalogue.courses c where c.lifecycle_status = 'active' and c.duration_value is null limit 1;
  if v_id is not null then
    s := security.field_state_v1('duration', v_id);
    if s->>'completeness' <> 'none' or s->'source_finding'->>'finding' is null then raise exception 'guard: an empty duration has no source finding: %', s; end if;
  end if;
end $c$;
