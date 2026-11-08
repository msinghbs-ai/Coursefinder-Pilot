-- Guards: IQ-00313 (Deakin commencement-date contamination, 8 Nov 2026): the correction file as run on the fixture (two contaminated intakes that no earlier case
-- touched). It withdrew only the month-only date and year, kept every reading, event and filled decision, held the courses, recorded the rejected reading,
-- left the stored Website and Zoho items at the month only, and left everything else (an eligible course written by the fixed job, and the courses withdrawn earlier) as it was.
\set ON_ERROR_STOP on
\set QUIET on
do $$
declare y0 int := public.fixture_dk_y0(); c record; n int; w jsonb; z jsonb; v_ev jsonb;
begin
  for c in select * from public.dk_cases where name in ('cC', 'cD') loop
    if (select start_date from catalogue.course_intakes where id = c.intake_id) is not null or (select intake_year from catalogue.course_intakes where id = c.intake_id) is not null
       or (select intake_label from catalogue.course_intakes where id = c.intake_id) <> 'November' or (select status from catalogue.course_intakes where id = c.intake_id) <> 'active' then
      raise exception 'not month-only November: %', c.name; end if;
    if not exists (select 1 from pipeline.manual_locks where entity = 'course' and entity_id = c.course_id and field = 'intakes' and mode = 'value') then raise exception 'no hold: %', c.name; end if;
    if (select count(*) from pipeline.course_intake_date_events where intake_id = c.intake_id and outcome = 'filled') < 1 or (select count(*) from pipeline.course_intake_date_events where intake_id = c.intake_id and outcome = 'withdrawn') <> 1 then
      raise exception 'events: %', c.name; end if;
    select w2.item->'intakes', z2.item->'intakes' into w, z from pipeline.website_sync_items w2, pipeline.zoho_sync_items z2 where w2.entity = 'course' and w2.ref_id = c.course_id and z2.entity = 'course' and z2.ref_id = c.course_id;
    if w <> jsonb_build_array(jsonb_build_object('label', 'November', 'month', 11, 'year', null, 'start_date', null, 'application_deadline', null)) or z is distinct from w then raise exception 'stored items: % % %', c.name, w, z; end if;
  end loop;
  -- the audit event carries the operation, the reason, the before state of every intake and the holds
  select detail into v_ev from pipeline.admin_control_events where area = 'intake_dates' and action = 'withdraw' and target = 'IQ-00313-DEAKIN-20261108-WITHDRAW';
  if v_ev is null or jsonb_array_length(v_ev->'results') <> 2 or jsonb_array_length(v_ev->'before') <> 2 or jsonb_array_length(v_ev->'holds_placed') <> 2 or v_ev->>'reason' is null then raise exception 'audit: %', v_ev; end if;
  -- the rejected reading is recorded once, with the year the old rule gave
  if (select count(*) from pipeline.intake_date_rejections where year = y0 + 1 and start_date = make_date(y0 + 1, 11, 1) and case_ref = 'IQ-00313' and proposal_id = (select proposal_id from public.dk_cases where name = 'calendar')) <> 1 then raise exception 'rejection not recorded'; end if;
  -- nothing else moved: the eligible course keeps the date the fixed job wrote, the two courses withdrawn earlier are still month-only and held, no intake holds the value
  if (select start_date from catalogue.course_intakes i join public.dk_cases k on k.intake_id = i.id where k.name = 'cN') is distinct from make_date(y0, 11, 1) then raise exception 'cN changed'; end if;
  if exists (select 1 from catalogue.course_intakes i join public.dk_cases k on k.intake_id = i.id where k.name in ('cA', 'cB') and (i.start_date is not null or i.intake_year is not null)) then raise exception 'cA or cB changed'; end if;
  select count(*) into n from catalogue.course_intakes where start_date = make_date(y0 + 1, 11, 1);
  if n <> 0 then raise exception '% intakes still hold the rejected value', n; end if;
  -- the rejected reading cannot return: the fixed plan, run on a new November intake of a course that names Trimester 3, takes the true start
  raise notice 'PASS correction: the two contaminated intakes are month-only November, held, with the filled events and readings kept and one withdrawn event each; the rejected reading is recorded; the stored Website and Zoho items show November with no year and no date; the audit event carries the reason, the before state and the holds; nothing else moved';
end $$;
