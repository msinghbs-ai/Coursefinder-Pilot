-- HELD (not a migration, nothing applies it): withdraw EVERY course description the subset recovery admitted (20261110230000), through the existing withdraw function.
-- Run by the Platform Admin only if the subset recovery is to be taken back. Pause first (Settings: enrich.course_description_machine_on = 0, with a reason, or the forward recovery supabase/held/cdesc_subset_recovery_forward_recovery.sql),
-- so the job does not admit more while this runs.
-- What it does: for each live machine admission whose checks carry subset_of_reading, calls security.course_description_machine_withdraw_v1(course, reason, actor), exactly as
-- public.admin_course_description_machine_withdraw_v1 does for one course: the description goes back to what it was before the admission (empty), a search refresh is queued, the withdrawal is logged.
-- A course whose description a person changed since, or that is locked by hand, is kept and reported (the function refuses it). A withdrawn course is parked for a person (withdrawn_awaiting_person); the machine does not admit it again.
-- Nothing is dropped or deleted. Fill in v_actor (the Platform Admin's user id, auth.users.id) before running: the function refuses a withdrawal without a named person.

do $w$
declare v_actor uuid := null;  -- <- paste the Platform Admin's user id here
        v_reason text := 'Subset recovery taken back by the Platform Admin (bulk withdrawal of every admission by subset)';
        r record; v_res jsonb; v_ok int := 0; v_kept jsonb := '[]'::jsonb; v_total int;
begin
  if v_actor is null then raise exception 'set v_actor to the Platform Admin user id first'; end if;
  select count(*) into v_total from pipeline.course_description_machine_admissions a where a.outcome = 'admitted' and a.withdrawn_at is null and a.checks ? 'subset_of_reading';
  raise notice 'admissions by subset still live: %', v_total;
  for r in select a.course_id from pipeline.course_description_machine_admissions a where a.outcome = 'admitted' and a.withdrawn_at is null and a.checks ? 'subset_of_reading' order by a.id loop
    v_res := security.course_description_machine_withdraw_v1(r.course_id, v_reason, v_actor);
    if coalesce((v_res->>'ok')::boolean, false) then v_ok := v_ok + 1;
    else v_kept := v_kept || jsonb_build_object('course_id', r.course_id, 'rule', v_res->>'rule'); end if;
  end loop;
  raise notice 'withdrawn: %, kept because the function refused: %', v_ok, v_kept;
end $w$;
