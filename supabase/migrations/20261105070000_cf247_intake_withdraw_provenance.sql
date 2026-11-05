-- CF-247 P0 IQ-00313 narrow correction (Platform Admin decision 5 Nov 2026 16:36 §2: "Reconcile the five earlier UNSW admissions individually.
-- Withdraw only values confirmed unsupported, preserving history"). Emergency scope under the engineering-hold rule for confirmed P0 integrity.
-- Why (production, 5 Nov 2026 16:47): security.intake_date_withdraw_v1 (v2.15.482) read the admission from the current decision row
--   (pipeline.course_intake_date_events' summary in pipeline.course_intake_dates). The 16:26 run re-decided the two Master of Industrial Research
--   intakes (outcome skipped, before = after = the admitted dates) after the containment setting changed the inputs, so the decision row no
--   longer shows the admission and the withdrawal would refuse them, although the catalogue still holds the unsupported 2027-02-15 and 2027-05-31.
-- What: the withdrawal takes the admission from its own record: the latest 'filled' event of the intake that no later withdrawal undid (its
--   before and after values), so only the fields that admission set are reverted, only while the catalogue still holds them. Nothing else changes.
-- Consumer API: unchanged (G3).
-- Replaces: md5-guarded edit of security.intake_date_withdraw_v1 (746b5c1a)
-- Retires: nothing
-- Nothing is dropped or deleted.

create or replace function pg_temp.edit(p_sig text, p_md5 text, p_marker text, p_old text[], p_new text[], p_times int[]) returns text language plpgsql as $e$
declare v text := pg_get_functiondef(p_sig::regprocedure); i int; n int;
begin
  if position(p_marker in v) > 0 then return p_sig || ': already applied'; end if;
  if md5(v) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %, expected %)', p_sig, md5(v), p_md5; end if;
  for i in 1 .. array_length(p_old, 1) loop
    n := (length(v) - length(replace(v, p_old[i], ''))) / length(p_old[i]);
    if n <> p_times[i] then raise exception '%: edit % must apply exactly % time(s), found %', p_sig, i, p_times[i], n; end if;
    v := replace(v, p_old[i], p_new[i]);
  end loop;
  execute v;
  return p_sig || ': edited';
end $e$;

select pg_temp.edit('security.intake_date_withdraw_v1(uuid,text,text,boolean)', '746b5c1a4141d4b5d022c1bfa0fa25f3', 'v_adm_after',
  array[$o$declare d pipeline.course_intake_dates%rowtype; i catalogue.course_intakes%rowtype; v_before jsonb; v_after jsonb;$o$,
        $o$  if d.intake_id is null or d.outcome <> 'filled' or d.after_value is null then$o$,
        $o$  v_year := case when d.before_value->>'year' is null and d.after_value->>'year' is not null and i.intake_year is not distinct from (d.after_value->>'year')::int then null else i.intake_year end;
  v_start := case when d.before_value->>'start_date' is null and d.after_value->>'start_date' is not null and i.start_date is not distinct from (d.after_value->>'start_date')::date then null else i.start_date end;
  v_dl := case when d.before_value->>'application_deadline' is null and d.after_value->>'application_deadline' is not null
                    and i.application_deadline is not distinct from (d.after_value->>'application_deadline')::date then null else i.application_deadline end;$o$],
  array[$n$declare d pipeline.course_intake_dates%rowtype; i catalogue.course_intakes%rowtype; v_before jsonb; v_after jsonb; v_adm_before jsonb; v_adm_after jsonb;$n$,
        $n$  -- IQ-00313: the admission from its own record (the latest filled event no later withdrawal undid); a later run may have re-decided the row
  select e.before_value, e.after_value into v_adm_before, v_adm_after from pipeline.course_intake_date_events e
   where e.intake_id = p_intake and e.outcome = 'filled'
     and not exists (select 1 from pipeline.course_intake_date_events w where w.intake_id = p_intake and w.outcome = 'withdrawn' and w.id > e.id)
   order by e.id desc limit 1;
  if d.intake_id is null or v_adm_after is null then$n$,
        $n$  v_year := case when v_adm_before->>'year' is null and v_adm_after->>'year' is not null and i.intake_year is not distinct from (v_adm_after->>'year')::int then null else i.intake_year end;
  v_start := case when v_adm_before->>'start_date' is null and v_adm_after->>'start_date' is not null and i.start_date is not distinct from (v_adm_after->>'start_date')::date then null else i.start_date end;
  v_dl := case when v_adm_before->>'application_deadline' is null and v_adm_after->>'application_deadline' is not null
                    and i.application_deadline is not distinct from (v_adm_after->>'application_deadline')::date then null else i.application_deadline end;$n$],
  array[1, 1, 1]);
comment on function security.intake_date_withdraw_v1(uuid, text, text, boolean) is 'CF-247 (direction 5 Nov 2026 15:50 §1, P0 IQ-00313; provenance 5 Nov 2026 16:47): withdraws a value the intake-dates process admitted, taken from the admission''s own record (the latest filled event no later withdrawal undid): reverts only the fields it set, only while the catalogue still holds them, never under a manual lock; the decision row becomes a course-level exception and, with p_hold (the default), the course''s intakes are held by the existing manual lock (mode value) until a person lifts it, a withdrawn event is appended (nothing earlier is changed or deleted), the projection is refreshed and the Website API v2 source is read back.';
