-- Guards: F-INT D3 forward fix (Platform Admin decision 9 Nov 2026: no manual rerun of an applied migration; idempotent forward migration with checksum, row-count and forward-recovery safeguards):
-- the rows the backfill must leave alone, set up on the production-equivalent fixture (2,929 decision rows) with the switch still OFF. Every named row is one of the candidates of the original
-- step-6 predicate (active intake of an active course, a date missing, no revisit time, one of the four held actions) that the new migration must not touch, or a control row.
\set ON_ERROR_STOP on
\set QUIET on
create table public.rb_cases (name text primary key, intake_id uuid not null, course_id uuid not null);
create table public.rb_snap (label text not null, intake_id uuid not null, row_text text not null, primary key (label, intake_id));
-- the production trigger only recomputes a class when its own columns are written; the seeding below writes a reason, so it is held off while the cases are set up
alter table pipeline.course_intake_dates disable trigger intake_failure_class;
do $$
declare r record; v_pick uuid;
begin
  -- locked by hand
  select d.intake_id into v_pick from pipeline.course_intake_dates d where d.next_action = 'evidence_ambiguous' and d.next_revisit_at is null and not exists (select 1 from pipeline.manual_locks k where k.entity_id = d.course_id) order by d.intake_id offset 11 limit 1;
  insert into public.rb_cases select 'locked_by_hand', d.intake_id, d.course_id from pipeline.course_intake_dates d where d.intake_id = v_pick;
  insert into pipeline.manual_locks(entity, entity_id, field, mode, set_at) select 'course', course_id, 'intakes', 'value', now() from public.rb_cases where name = 'locked_by_hand';
  -- withdrawn: by event, by reason, by intake status
  select d.intake_id into v_pick from pipeline.course_intake_dates d where d.next_action = 'evidence_ambiguous' and d.next_revisit_at is null and d.intake_id not in (select intake_id from public.rb_cases) order by d.intake_id offset 23 limit 1;
  insert into public.rb_cases select 'withdrawn_event', d.intake_id, d.course_id from pipeline.course_intake_dates d where d.intake_id = v_pick;
  insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, outcome, reason, next_action) select intake_id, course_id, provider_id, 'withdrawn', 'withdrawn: fixture', 'human_decision_required' from pipeline.course_intake_dates where intake_id = v_pick;
  select d.intake_id into v_pick from pipeline.course_intake_dates d where d.next_action = 'evidence_ambiguous' and d.next_revisit_at is null and d.intake_id not in (select intake_id from public.rb_cases) order by d.intake_id offset 31 limit 1;
  insert into public.rb_cases select 'withdrawn_reason', d.intake_id, d.course_id from pipeline.course_intake_dates d where d.intake_id = v_pick;
  update pipeline.course_intake_dates set reason = 'withdrawn: the value was rejected earlier and is not admitted again (a person decides)' where intake_id = v_pick;
  select d.intake_id into v_pick from pipeline.course_intake_dates d where d.next_action = 'reader_correction_needed' and d.next_revisit_at is null and d.intake_id not in (select intake_id from public.rb_cases) order by d.intake_id limit 1;
  insert into public.rb_cases select 'withdrawn_status', d.intake_id, d.course_id from pipeline.course_intake_dates d where d.intake_id = v_pick;
  -- rejected: by the rejected-value memory (the reading and the year of the row), by a reason that names a rejected value
  select d.intake_id into v_pick from pipeline.course_intake_dates d where d.next_action = 'evidence_ambiguous' and d.next_revisit_at is null and d.intake_id not in (select intake_id from public.rb_cases)
     and d.evidence_year is not null and (select count(*) from pipeline.course_intake_dates e where e.provider_id = d.provider_id and e.proposal_id is not distinct from d.proposal_id and e.evidence_year is not distinct from d.evidence_year and e.next_revisit_at is null and e.next_action in ('evidence_ambiguous', 'reader_correction_needed', 'calendar_needs_correction', 'human_decision_required')) = 1
   order by d.intake_id limit 1;
  if v_pick is null then raise exception 'no row with a reading and year of its own for the rejected case'; end if;
  insert into public.rb_cases select 'rejected_reading', d.intake_id, d.course_id from pipeline.course_intake_dates d where d.intake_id = v_pick;
  insert into pipeline.intake_date_rejections(provider_id, proposal_id, quote, year, start_date, reason, rejected_by) select provider_id, proposal_id, 'fixture quote', evidence_year, make_date(evidence_year, 11, 1), 'fixture rejection', 'fixture' from pipeline.course_intake_dates where intake_id = v_pick;
  select d.intake_id into v_pick from pipeline.course_intake_dates d where d.next_action = 'evidence_ambiguous' and d.next_revisit_at is null and d.intake_id not in (select intake_id from public.rb_cases) order by d.intake_id offset 41 limit 1;
  insert into public.rb_cases select 'rejected_reason', d.intake_id, d.course_id from pipeline.course_intake_dates d where d.intake_id = v_pick;
  update pipeline.course_intake_dates set reason = 'the calendar value is a value recorded as rejected for this university (not admitted)' where intake_id = v_pick;
  -- not undated: all three dates held
  select d.intake_id into v_pick from pipeline.course_intake_dates d where d.next_action = 'evidence_ambiguous' and d.next_revisit_at is null and d.intake_id not in (select intake_id from public.rb_cases) order by d.intake_id offset 53 limit 1;
  insert into public.rb_cases select 'fully_dated', d.intake_id, d.course_id from pipeline.course_intake_dates d where d.intake_id = v_pick;
  -- inactive course
  select d.intake_id into v_pick from pipeline.course_intake_dates d where d.next_action = 'calendar_needs_correction' and d.next_revisit_at is null and d.intake_id not in (select intake_id from public.rb_cases) order by d.intake_id limit 1;
  if v_pick is null then select d.intake_id into v_pick from pipeline.course_intake_dates d where d.next_action = 'evidence_ambiguous' and d.next_revisit_at is null and d.intake_id not in (select intake_id from public.rb_cases) order by d.intake_id offset 67 limit 1; end if;
  insert into public.rb_cases select 'inactive_course', d.intake_id, d.course_id from pipeline.course_intake_dates d where d.intake_id = v_pick;
  -- controls: a row that already has a time, a row of another action (the original waiting actions), a row with no action
  select d.intake_id into v_pick from pipeline.course_intake_dates d where d.next_revisit_at is not null order by d.intake_id limit 1;
  insert into public.rb_cases select 'already_timed', d.intake_id, d.course_id from pipeline.course_intake_dates d where d.intake_id = v_pick;
  select d.intake_id into v_pick from pipeline.course_intake_dates d where d.next_action = 'awaiting_official_calendar' and d.next_revisit_at is null order by d.intake_id limit 1;
  insert into public.rb_cases select 'other_action', d.intake_id, d.course_id from pipeline.course_intake_dates d where d.intake_id = v_pick;
  select d.intake_id into v_pick from pipeline.course_intake_dates d where d.next_action is null and d.next_revisit_at is null order by d.intake_id limit 1;
  if v_pick is not null then insert into public.rb_cases select 'no_action', d.intake_id, d.course_id from pipeline.course_intake_dates d where d.intake_id = v_pick; end if;
  -- the three picks the migration tamper cases use (ordinary candidates)
  for r in select row_number() over (order by x.intake_id) rn, x.intake_id, x.course_id from (
            select d.intake_id, d.course_id from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id
             where d.next_action = 'evidence_ambiguous' and d.next_revisit_at is null and i.status = 'active' and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
               and d.intake_id not in (select intake_id from public.rb_cases) order by d.intake_id offset 101 limit 3) x loop
    insert into public.rb_cases values (case r.rn when 1 then 'tamper_pick' when 2 then 'edited_since_a' else 'edited_since_b' end, r.intake_id, r.course_id);
  end loop;
end $$;
alter table pipeline.course_intake_dates enable trigger intake_failure_class;
-- the intake-level conditions (the catalogue triggers guard other writes, so only the columns of these cases are written)
update catalogue.course_intakes set status = 'withdrawn' where id = (select intake_id from public.rb_cases where name = 'withdrawn_status');
update catalogue.course_intakes i set intake_year = 2027, start_date = date '2027-03-01', application_deadline = date '2027-01-15' where i.id = (select intake_id from public.rb_cases where name = 'fully_dated');
update catalogue.courses set lifecycle_status = 'archived' where id = (select course_id from public.rb_cases where name = 'inactive_course');
-- every named case exists
do $$
declare v_missing text;
begin
  select string_agg(n, ',') into v_missing from unnest(array['locked_by_hand', 'withdrawn_event', 'withdrawn_reason', 'withdrawn_status', 'rejected_reading', 'rejected_reason', 'fully_dated', 'inactive_course', 'already_timed', 'other_action', 'tamper_pick', 'edited_since_a', 'edited_since_b']) n where n not in (select name from public.rb_cases);
  if v_missing is not null then raise exception 'cases missing: %', v_missing; end if;
  raise notice 'PASS seed: % named cases set up with the switch OFF', (select count(*) from public.rb_cases);
end $$;
-- the state every case compares with: the whole row as jsonb, and the few typed values the expected set is worked out from (independently of the migration)
create table public.rb_pre as select d.intake_id, d.course_id, d.next_action, d.next_revisit_at, (i.status = 'active' and c.lifecycle_status = 'active' and (i.intake_year is null or i.start_date is null or i.application_deadline is null)) undated_active
  from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id join catalogue.courses c on c.id = i.course_id;
insert into public.rb_snap select 'seeded', d.intake_id, to_jsonb(d)::text from pipeline.course_intake_dates d;
-- the rows whose row text differs from a snapshot (a row added or removed counts)
create or replace function public.rb_diff(p_label text) returns setof uuid language sql stable as $f$
  select coalesce(d.intake_id, s.intake_id) from pipeline.course_intake_dates d full join (select * from public.rb_snap where label = p_label) s on s.intake_id = d.intake_id
   where s.row_text is distinct from to_jsonb(d)::text
$f$;
-- same, ignoring next_revisit_at (what must never change on any row)
create or replace function public.rb_diff_other(p_label text) returns setof uuid language sql stable as $f$
  select coalesce(d.intake_id, s.intake_id) from pipeline.course_intake_dates d full join (select * from public.rb_snap where label = p_label) s on s.intake_id = d.intake_id
   where (s.row_text::jsonb - 'next_revisit_at') is distinct from (to_jsonb(d) - 'next_revisit_at')
$f$;
