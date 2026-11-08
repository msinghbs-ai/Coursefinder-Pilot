-- READY TO RUN, NOT RUN. Nothing in this file has run in production. Run by the Integration Controller only, in the Supabase SQL editor of project
-- fxcwkweaxjtknorudmwp (never coursefinder-demo), after the Platform Admin has approved it (IQ-00313 P0, directive 8 Nov 2026).
--
-- What it does: withdraws the twelve Deakin November commencement dates written as 1 November 2028 by job intake-dates-apply (rule calendar-v3, runs of
-- 7 Nov 2026 14:26 UTC to 8 Nov 2026 01:26 UTC; ten were written by 23:26 UTC on 7 Nov and two more at 01:26 UTC on 8 Nov, so the list GROWS while the job runs: set
-- intake_dates.apply_enabled to false first), from the calendar quote "Trimester 3: 1 Nov - 28 Jan 2028", approved reading 9d6eccfb, which starts on 1 November 2027).
-- It withdraws the date and the year only. The intake "November" stays as month only: the Deakin course pages list Trimester 3 / November as an intake.
-- It does NOT write 1 November 2027 (or any other date): no course page prints a start date or year, and a calendar date alone does not prove a course
-- is offered in that study period. A person decides each value afterwards (the intakes are held, human_decision_required).
--
-- It uses only governed routes: security.intake_date_withdraw_v1 (the existing withdrawal: reverts only the fields the process set, only while the
-- catalogue still holds the value it admitted, appends a withdrawn event whose before_value is the rejected value, keeps the filled event and the reading,
-- places the existing course-level intakes hold, refreshes the projection document), pipeline.intake_date_rejections (migration 20261108050000: the
-- rejected reading, so no run uses it again), security.intake_projection_reconcile_v1 (same migration: the stored Website and Zoho items follow at once)
-- and pipeline.admin_control_events (audit). The two migration objects are used only when they exist: run this file before the migration and the stored
-- items follow within about an hour by the scans (website_sync_check_v1, then zoho_sync_check_v1); run it after, and they follow in the same transaction.
-- No consumer API object is changed (G3). Nothing is dropped or deleted. No lock, original reading, event or history row is removed or edited.
--
-- Before running: (1) intake_dates.apply_enabled is false (containment) or migration 20261108050000 is released, so no run re-dates a withdrawn
-- intake meanwhile (the hold below already keeps every automated lane out of these courses); (2) the Integration Controller is the only writer.
-- The block stops, and changes nothing, unless every guard below matches production exactly (10 of 10 intakes, no other intake with the value, no
-- existing hold, a filled event from calendar-v3 for each, the operation not recorded before). If it stops with "N active intakes hold the value, the list
-- names 12", more were written since: list them with the query below, review each against the same quote, add them to the TARGETS block, and run again.
-- The list query: select i.id, i.course_id, i.source_intake_key, c.canonical_title from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
--                  where i.status = 'active' and i.start_date = '2028-11-01' order by 4;
--
-- After running: wait for the Website scan then the Zoho scan if the migration was not yet released (about 55 minutes), then run the verification
-- queries at the end of this file. To lift a hold later (only when a person has decided the value): delete the manual_locks row listed in the audit
-- event detail for that course; nothing here does it.
begin;
set local statement_timeout = '60s';
set local lock_timeout = '5s';
do $apply$
declare
  v_decision text := 'Platform Admin directive 8 Nov 2026 (IQ-00313 P0, Deakin commencement-date contamination)';
  v_actor uuid := null;   -- the authorising Platform Admin's user id if the SQL context requires one; null when run as postgres by the Integration Controller
  v_operation constant text := 'IQ-00313-DEAKIN-20261108-WITHDRAW';
  v_reason constant text := 'IQ-00313: Deakin Trimester 3 start dated 1 November 2028; the calendar quote starts 1 November 2027 (year read from the end date); no course page states a start date or year';
  v_before jsonb; v_count int; v_total int; v_results jsonb := '[]'::jsonb; v_one jsonb; v_recon jsonb := null; r record; v_ev_before jsonb; v_ev_after int; v_n int;
begin
  -- CONSTANTS-BEGIN
  create temp table iq00313_const on commit drop as select
    date '2028-11-01' as bad_date, 2028 as bad_year, 'November'::text as label, 'calendar-v3'::text as rule,
    'c5c5d225-3d4c-4e41-8275-78eddd261073'::uuid as provider_id, '9d6eccfb-c264-41b2-86c9-803acf2aeeb5'::uuid as proposal_id,
    'Trimester 3: 1 Nov - 28 Jan 2028'::text as quote, 'b524f892-6bb5-4836-9af7-98700a4e5080'::uuid as source_id;
  -- CONSTANTS-END
  -- TARGETS-BEGIN
  create temp table iq00313_targets on commit drop as select * from (values
    ('97396154-52c5-4307-b9c3-bacadfcb2d23'::uuid, '2bc66924-be2c-4e68-9b21-101493cf8d95'::uuid, '095262c:current:november', 'Bachelor of Business'),
    ('3cd3ac6f-3496-4eb1-8ad9-1e340d40b344'::uuid, '1f375f01-d4fd-46ea-8e2d-0834a8841682'::uuid, '0100819:current:november', 'Bachelor of Commerce / Bachelor of Arts'),
    ('222af1e5-ba50-4a8f-a8ad-ddddbc116839'::uuid, '1c9362f8-9164-45fb-976e-684902f0c6b6'::uuid, '063354g:current:november', 'Bachelor of Information Technology (Honours)'),
    ('43e54175-53a6-4a59-b0cd-2745fd612895'::uuid, '10d34659-8bf9-4396-8745-49d4a21b7741'::uuid, '075376c:current:november', 'Bachelor of International Studies / Bachelor of Commerce'),
    ('e8c356bc-ca2a-4c62-98fc-f50c2bc2643f'::uuid, '0742996e-6f5c-4379-9b69-116d4176282c'::uuid, '073434c:current:november', 'Graduate Diploma of Professional Accounting'),
    ('610b3e37-34ba-41bf-816f-fd502bd815de'::uuid, '229ecc52-f1e7-4353-9e96-7b6359766545'::uuid, '0100305:current:november', 'Master of Applied Artificial Intelligence'),
    ('fedaf904-a298-4e74-bc89-b9f55b241817'::uuid, '1c94e704-d9f6-47fb-8a69-f6fabfa11ef8'::uuid, '001869e:current:november', 'Master of Arts'),
    ('26643e11-e587-4995-9d3e-3758b6d02859'::uuid, '240145f7-892d-473e-befe-e915d601f7a4'::uuid, '079321g:current:november', 'Master of Construction Management (Professional)'),
    ('b3104e40-36ad-4888-8b50-0dbf0de44add'::uuid, '1fd069e9-926b-49f1-97ab-11261d2040fd'::uuid, '025405f:current:november', 'Master of Engineering'),
    ('bb847045-5dea-452b-b15c-d5ced763d8fe'::uuid, '006fc6a4-ce91-4e2f-b251-16fa46df8c74'::uuid, '102805c:current:november', 'Master of Information Technology'),
    ('41956ca2-787b-4837-a6b4-f4bd4f681c77'::uuid, '34737033-8e05-4819-8878-df6de8033b94'::uuid, '051581g:current:november', 'Master of Information Technology (Professional)'),
    ('239b124f-2085-4c42-99d6-b4feef01de71'::uuid, '31a3c64e-7dba-43ec-a836-73006d6c471a'::uuid, '102876k:current:november', 'Master of Professional Accounting')
  ) t(intake_id, course_id, expected_key, title);
  -- TARGETS-END
  select count(*) into v_total from iq00313_targets;
  -- the rows are locked for the whole operation: a concurrent run cannot pass the value guards as well
  perform 1 from catalogue.course_intakes where id in (select intake_id from iq00313_targets) order by id for update;
  if exists (select 1 from pipeline.admin_control_events where area = 'intake_dates' and action = 'withdraw' and target = v_operation) then
    raise exception 'operation % already recorded: reconcile, do not replay', v_operation;
  end if;
  -- guard 1: every target is exactly the contaminated intake (same course, active, November, 2028, 1 Nov 2028, no deadline, the sweep source and key)
  select count(*) into v_count from iq00313_targets t join iq00313_const k on true join catalogue.course_intakes i on i.id = t.intake_id and i.course_id = t.course_id
   where i.status = 'active' and i.intake_label = k.label and i.intake_year = k.bad_year and i.start_date = k.bad_date and i.source_id = k.source_id
     and i.source_intake_key is not distinct from t.expected_key;
  if v_count <> v_total then raise exception 'only % of % intakes match the contaminated value exactly; nothing changed', v_count, v_total; end if;
  -- guard 2: no other active intake in the catalogue holds the value (a different set would need its own review)
  select count(*) into v_count from catalogue.course_intakes i join iq00313_const k on true where i.status = 'active' and i.start_date = k.bad_date and i.intake_year = k.bad_year;
  if v_count <> v_total then raise exception '% active intakes hold the value, the list names %; stop and review', v_count, v_total; end if;
  -- guard 3: each was written by the job from the named quote and reading, and no later withdrawal undid it
  select count(*) into v_count from iq00313_targets t join iq00313_const k on true
   where exists (select 1 from pipeline.course_intake_date_events e where e.intake_id = t.intake_id and e.outcome = 'filled' and e.rule = k.rule and e.provider_id = k.provider_id
                    and e.proposal_id = k.proposal_id and e.start_quote = k.quote and (e.after_value->>'start_date')::date = k.bad_date and (e.after_value->>'year')::int = k.bad_year
                    and not exists (select 1 from pipeline.course_intake_date_events w where w.intake_id = t.intake_id and w.outcome = 'withdrawn' and w.id > e.id));
  if v_count <> v_total then raise exception 'only % of % intakes have the filled event of the named quote and reading; nothing changed', v_count, v_total; end if;
  -- guard 4: no hold exists on these courses (never bypass or change a human lock)
  if exists (select 1 from pipeline.manual_locks l join iq00313_targets t on l.entity = 'course' and l.entity_id = t.course_id and l.field in ('all', 'intake', 'intakes')) then
    raise exception 'an intakes hold already exists on one of the courses: stop for its owner';
  end if;
  -- what is kept and what is about to change (audit)
  select jsonb_agg(jsonb_build_object('intake', to_jsonb(i), 'events', (select count(*) from pipeline.course_intake_date_events e where e.intake_id = i.id)) order by i.id) into v_before
    from catalogue.course_intakes i where i.id in (select intake_id from iq00313_targets);
  -- the withdrawal, one intake at a time, each held (the existing course-level hold, so no automated lane fills the course's intakes again)
  for r in select * from iq00313_targets order by title loop
    v_one := security.intake_date_withdraw_v1(r.intake_id, v_reason, 'IQ-00313 Integration Controller', true);
    if not coalesce((v_one->>'withdrawn')::boolean, false) then raise exception 'withdrawal refused for % (%): %', r.title, r.intake_id, v_one; end if;
    v_results := v_results || jsonb_build_array(jsonb_build_object('title', r.title, 'intake_id', r.intake_id, 'course_id', r.course_id, 'before', v_one->'before', 'after', v_one->'after', 'website_verified', v_one->'website_verified'));
  end loop;
  -- the rejected reading is recorded so no run uses it again (migration 20261108050000; skipped when it is not released yet)
  if to_regclass('pipeline.intake_date_rejections') is not null then
    execute 'insert into pipeline.intake_date_rejections(provider_id, proposal_id, quote, year, start_date, reason, case_ref, rejected_by) select k.provider_id, k.proposal_id, k.quote, k.bad_year, k.bad_date, $1, $2, $3 from iq00313_const k on conflict do nothing'
      using 'the quote starts 1 November of the year before the year printed after its end date; read as 1 November of that year', 'IQ-00313', 'Integration Controller';
  end if;
  -- the stored Website and Zoho items follow at once (migration 20261108050000; otherwise the scheduled scans do it within about an hour)
  if to_regprocedure('security.intake_projection_reconcile_v1(uuid[])') is not null then
    execute 'select security.intake_projection_reconcile_v1((select array_agg(course_id) from iq00313_targets))' into v_recon;
  end if;
  -- verification inside the transaction: nothing holds the value, the filled event and reading are kept, a withdrawn event exists, the hold exists, the Website v2 item shows the month only
  select count(*) into v_n from catalogue.course_intakes i join iq00313_targets t on t.intake_id = i.id
   where i.start_date is not null or i.intake_year is not null or i.status <> 'active' or i.intake_label <> 'November';
  if v_n <> 0 then raise exception '% intakes are not month-only November after the withdrawal', v_n; end if;
  select count(*) into v_n from iq00313_targets t where exists (select 1 from pipeline.course_intake_date_events e where e.intake_id = t.intake_id and e.outcome = 'filled')
     and exists (select 1 from pipeline.course_intake_date_events e where e.intake_id = t.intake_id and e.outcome = 'withdrawn' and (e.before_value->>'start_date')::date = (select bad_date from iq00313_const))
     and exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = t.course_id and l.field = 'intakes' and l.mode = 'value');
  if v_n <> v_total then raise exception 'history or hold missing for % of % intakes', v_total - v_n, v_total; end if;
  select count(*) into v_n from iq00313_targets t, jsonb_array_elements(coalesce(api.website_v2_course_item(t.course_id)->'intakes', '[]'::jsonb)) e
   where e->>'label' = 'November' and (e->>'start_date' is not null or e->>'year' is not null);
  if v_n <> 0 then raise exception 'the Website v2 item of % courses still shows a November date or year', v_n; end if;
  if v_recon is not null then
    select count(*) into v_n from jsonb_array_elements(v_recon) c, jsonb_array_elements(coalesce(c->'website', '[]'::jsonb)) w where w->>'label' = 'November' and (w->>'start_date' is not null or w->>'year' is not null);
    if v_n <> 0 then raise exception 'a stored Website item still shows a November date'; end if;
    select count(*) into v_n from jsonb_array_elements(v_recon) c, jsonb_array_elements(coalesce(c->'zoho', '[]'::jsonb)) w where w->>'label' = 'November' and (w->>'start_date' is not null or w->>'year' is not null);
    if v_n <> 0 then raise exception 'a stored Zoho item still shows a November date'; end if;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('intake_dates', 'withdraw', v_operation, jsonb_build_object('governance', 'IQ-00313 P0', 'decision', v_decision, 'reason', v_reason, 'rule', 'calendar-v3',
          'calendar_quote', (select quote from iq00313_const), 'proposal_id', (select proposal_id from iq00313_const), 'fields_changed', jsonb_build_array('intake_year', 'start_date'),
          'fields_kept', jsonb_build_array('intake_label', 'application_deadline', 'source_id', 'evidence_id', 'confidence', 'status', 'readings', 'events', 'decisions'),
          'before', v_before, 'results', v_results, 'reconcile', v_recon, 'holds_placed', (select jsonb_agg(course_id order by course_id) from iq00313_targets)), v_actor);
  raise notice 'IQ-00313: % intakes withdrawn to month-only November, held for a person; rejection recorded: %; stored Website and Zoho items reconciled in this transaction: %',
    v_total, to_regclass('pipeline.intake_date_rejections') is not null, v_recon is not null;
end $apply$;
commit;

-- VERIFICATION (read only; run after the commit, and again after the Website and Zoho scans if the migration was not released when this ran)
-- 1 the catalogue: twelve November intakes, month only, active; nothing holds 1 November 2028
-- select c.canonical_title, i.intake_label, i.intake_year, i.start_date, i.status from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
--  where i.id in ('97396154-52c5-4307-b9c3-bacadfcb2d23','3cd3ac6f-3496-4eb1-8ad9-1e340d40b344','222af1e5-ba50-4a8f-a8ad-ddddbc116839','43e54175-53a6-4a59-b0cd-2745fd612895','e8c356bc-ca2a-4c62-98fc-f50c2bc2643f','610b3e37-34ba-41bf-816f-fd502bd815de','fedaf904-a298-4e74-bc89-b9f55b241817','26643e11-e587-4995-9d3e-3758b6d02859','b3104e40-36ad-4888-8b50-0dbf0de44add','bb847045-5dea-452b-b15c-d5ced763d8fe','41956ca2-787b-4837-a6b4-f4bd4f681c77','239b124f-2085-4c42-99d6-b4feef01de71') order by 1;
-- select count(*) from catalogue.course_intakes where start_date = '2028-11-01';   -- expect 0
-- 2 the stored Website and Zoho items: no November date or year (expect 0 rows each)
-- select w.item_key from pipeline.website_sync_items w, jsonb_array_elements(w.item->'intakes') e where w.entity = 'course' and w.removed_at is null and e->>'label' = 'November' and e->>'start_date' = '2028-11-01';
-- select z.item_key from pipeline.zoho_sync_items z, jsonb_array_elements(z.item->'intakes') e where z.entity = 'course' and z.removed_at is null and e->>'label' = 'November' and e->>'start_date' = '2028-11-01';
-- 3 the consumer endpoints (expect no November start date or year): api.website_v2_course_item(course_id)->'intakes', public.zoho_edge_course_lookup_v1(<cricos>)->'item'->'intakes', public.zoho_v2_course(<cricos>)->'item'->'intakes'
-- 4 the audit: select created_at, detail->>'reason', jsonb_array_length(detail->'results') from pipeline.admin_control_events where area = 'intake_dates' and action = 'withdraw' and target = 'IQ-00313-DEAKIN-20261108-WITHDRAW';
