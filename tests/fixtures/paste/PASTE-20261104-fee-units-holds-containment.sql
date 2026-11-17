-- CF-247 IQ-00111 (P0 fee integrity), containment. PASTE FILE: run by hand by the Platform Admin in the SQL editor of fxcwkweaxjtknorudmwp
-- (NOT coursefinder-demo). Not applied by any migration. Rollback: PASTE-20261104-fee-units-holds-containment-rollback.sql.
-- Route: the established fee-row status path (precedent PASTE-20261027-fee-divinity-gc-identity-withdraw.sql): status active -> inactive,
-- valid_to today, reason appended to notes, before-state kept in pipeline.admin_control_events. Nothing is deleted. admin_fee_reader has no
-- withdraw action, so this is the governed route.
--
-- What it withdraws: 13 active AI fee reader rows (catalogue.course_fees, fee_type provider_current_tuition) that Website API v2 and Zoho read.
--  A. 9 rows divided by 8 "units" a year where the count was credit points, VET units of competency or a whole-course count
--     (pipeline.fee_country_profiles AU: 8 units a year):
--     52bc162c Murdoch 096011C   12,600     page: "Full course fee (international) ... entire course ... 2027 $37,800"; course 52 weeks (1 year)
--     97c4caca UNSW 0100702      10,333.33  page: "2026 Indicative First Year Fee $31,000* ... Fee to Complete Degree $31,500*"; 34 weeks
--     9318d94a UNSW 0100908      10,333.33  page: "2026 Indicative full fee to complete degree $31,500*"; 34 weeks
--     00b40eeb UNSW 052690E      10,500     page: "2026 Indicative Fee to Complete Degree $32,000*"; 34 weeks
--     b6e2f56c UNSW 080476A      10,333.33  page: "2026 Indicative full fee to complete degree $31,500*"; 34 weeks
--     c5d7d256 UNSW 108475A      10,166.67  page: "2026 Indicative full fee to complete degree $31,000*"; 34 weeks
--     6417579c UNSW 121321K      10,333.33  page: "2026 Indicative full fee to complete degree $31,500*"; 36 weeks
--     9fb8be47 HELI 102291B      32,800     page: "Master of eLearning | $3,000 | $36,000 | $4,100 | $49,200" (12 units, whole course); 104 weeks;
--                                           CRICOS registered total 49,200, so 24,600 a year, not 32,800
--     2bc5fcb3 Reach 106655B     18,000     page: "Offshore Fee $29,000* Onshore Fee $27,000*" (whole course); 104 weeks, so 13,500 a year
--  B. 3 VIT rows where the unit count is real (24 units over 3 years, 16 over 2) but the reader kept the lowest row, which the same read
--     also classed as domestic; the international row and the CRICOS registered total agree on the higher figure:
--     ad9be016 VIT 085576A       12,000     page rows $36,000 and $51,000 for 24 units; CRICOS total 51,000 -> 17,000 a year
--     99acde0e VIT 114822C       18,000     page rows $36,000 and $48,000 for 16 units; CRICOS total 48,000 -> 24,000 a year
--     f5c95962 VIT 114579J       14,000     page rows $28,000 and $48,000 for 16 units; CRICOS total 48,000 (not shown to consumers today:
--                                           the 2026 adapter row da712724, 24,000, ranks first; withdrawn so it cannot surface)
--  C. 1 row admitted while its fee_crosscheck hold was raised (hold 6496144 raised 06:19 UTC 2 Nov, page queued 06:20, admitted 06:21):
--     0e01cb0c WSU 121432C       37,141     audit: the figure sits beside a Commonwealth Supported Places label; the hold is still pending
-- Kept (checked, not wrong): 67e4ceca Barton 119513J 28,000 (page: "Fees per year AUD $28,000 (8 units per year)"); 51ebae9d Reach 105389A
--   11,500 (23,000 whole course over 104 weeks); a805b998 VIT 117633F 16,000 (48,000 over 3 years; not shown to consumers).
-- Not touched: manual values (guard: none of the 13 courses has a manual lock), CRICOS rows, adapter rows, every other course.
--
-- What consumers return after this (security.course_fee_used_v1 Rule 2 fallback): the CRICOS registered fee a year
--   (registered total / greatest(course years, 1)): Murdoch 28,920; UNSW 31,000 / 31,000 / 31,500 / 31,000 / 30,500 / 31,000; HELI 24,600;
--   Reach 106655B 17,000; VIT 085576A 17,000, 114822C 24,000; WSU 26,526. VIT 114579J keeps its adapter 24,000. The website (search projection)
--   follows on the next search-refresh-requested run (every 10 minutes); Zoho reads live. Read-back: PASTE-20261104-fee-units-holds-readback.sql.
-- Scholarship savings: scholarship.refresh_course_financial_calculation skips inactive fees, so the 10 calculated savings built on these rows
--   (Murdoch 4: 2,520 / 2,520 / 1,890 / 3,150; UNSW 6: 2,033.33 to 2,100) are recomputed here for the 13 courses. With no provider fee the
--   function uses its Decision 247 estimate from the CRICOS registered total (Murdoch 20% -> 5,784, 15% -> 4,338, 25% -> 7,230; UNSW 20% ->
--   6,100 to 6,300). The hourly scholarship-fee-alignment job would also pick them up within 70 minutes; doing it here closes the gap.
-- Re-admission: these courses' pages are already read (queue rows exist for the same content hash), so the reader does not read them again
--   unless the page changes or an Enrich fields request requeues it. Until migration 20261104140000 (worker v0.59.6) is released, the optional
--   PASTE-20261104-fee-units-holds-interim-stop.sql stops course-page fee reads.
begin;
do $paste$
declare
  v_n int; v_upd int; r record; v_courses uuid[];
  v_reason text := 'Withdrawn 4 Nov 2026 (IQ-00111 P0 containment, Platform Admin paste): ';
begin
  create temporary table _iq111(id uuid primary key, course_id uuid, amount numeric, fee_year int, notes_md5 text, why text) on commit drop;
  insert into _iq111 values
   ('52bc162c-a1e0-4965-af76-d82b4b1e9839', 'd9dc5bb8-025b-46ca-ac24-7ca13157599f', 12600.00, 2027, '51583253b3a3d81d8663d8c080640fcb', 'units defect: 37,800 is the whole fee of a 1-year course, divided by 3'),
   ('97c4caca-289f-4801-a473-d52ed821ee22', 'b59c7a28-6ea9-49fe-bc22-fc954a3c4f20', 10333.33, 2026, 'fc51526019ebc583910336e97279420e', 'units defect: 24 credit points read as 3 years of 8 units'),
   ('9318d94a-9a1e-46d8-8ca8-5e79193aad52', '7eb95c94-4a79-4e5c-aea0-92b82cb1ec26', 10333.33, 2026, '80f05cbe820c8ec008f091cd3a963095', 'units defect: 24 credit points read as 3 years of 8 units'),
   ('00b40eeb-a95c-4af0-88a3-10ef3afec9c8', '811083ae-8e64-4989-895f-d9ccc1069aca', 10500.00, 2026, '165f393ca12611b10e48777ed5297199', 'units defect: 24 credit points read as 3 years of 8 units'),
   ('b6e2f56c-2a90-4b8c-b972-626b19bf25df', 'cfc791c8-fe3a-4c86-b74c-14f5a93f2670', 10333.33, 2026, 'fd1ad000032826763477c226dd26f0db', 'units defect: 24 credit points read as 3 years of 8 units'),
   ('c5d7d256-f184-4f6a-b272-5f2ea196c6ce', 'cf75c4de-781a-4ccc-bfeb-96d7921629f4', 10166.67, 2026, '9f664c6272359305867ba84554e6e210', 'units defect: 24 credit points read as 3 years of 8 units'),
   ('6417579c-267d-4dc7-89be-d4b2991b10b2', '401b9db3-0917-4376-b331-f352165fb922', 10333.33, 2026, '79a658fd136b57e797da425092a45a1d', 'units defect: 24 credit points read as 3 years of 8 units'),
   ('9fb8be47-9216-46c6-8eb1-e62d47aed529', '9fe78e66-12f1-42b3-ab56-c65fb99fbfd7', 32800.00, 2025, '835efcf533be727fb4b1955d40b12351', 'units defect: 49,200 for a 2-year course read as 1.5 years (12 units / 8)'),
   ('2bc5fcb3-cb11-4b2e-a0dd-8365a56571cf', 'c72ffb06-2984-4d6f-af44-a47a5224119a', 18000.00, 2026, '9b35ce297f2f7b4a78fbc2d92a9cf3b5', 'units defect: 27,000 for a 2-year course read as 1.5 years (12 units of competency / 8)'),
   ('ad9be016-adeb-4ea1-b100-4dda9455cef0', 'fe671861-eb69-4036-8acb-70ccde02d535', 12000.00, 2025, 'e475b6bd8b7004662ed944d1c8e584d3', 'audience: lowest row (36,000, also read as domestic) kept; international 51,000 = CRICOS total'),
   ('99acde0e-293b-41d8-8e93-f9c07bc8b1b6', '72598a16-d3f7-4332-9fb1-259125edfdd9', 18000.00, 2025, '76a4a66b540498cdd475017665fcdb0a', 'audience: lowest row (36,000, also read as domestic) kept; international 48,000 = CRICOS total'),
   ('f5c95962-f1c1-4ce4-bb49-c368210077d1', 'f4746111-4c26-4eb8-927c-c6088b66edeb', 14000.00, 2025, '183ae67c612a59df87825fd28e6ab4b5', 'audience: lowest row (28,000, also read as domestic) kept; international 48,000 = CRICOS total'),
   ('0e01cb0c-2f78-45e8-b188-cf29751f8df9', '011c9c63-e756-4ff0-957e-e6cbc5880bcf', 37141.00, 2027, '707ff75f2669efb0c35fb89b888f73c2', 'hold bypass: admitted 2 minutes after fee_crosscheck hold 6496144 was raised; the hold decides');

  -- guard 1: all 13 still exactly as measured (active AI fee reader rows, same amount, year and notes)
  select count(*) into v_n from catalogue.course_fees f join _iq111 t on t.id = f.id
   where f.course_id = t.course_id and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.status = 'active'
     and f.amount = t.amount and f.fee_year = t.fee_year and md5(f.notes) = t.notes_md5 and f.notes like '%AI fee reader (%';
  if v_n <> 13 then raise exception 'guard: % of the 13 rows are as measured on 3 Nov 2026; nothing changed', v_n; end if;
  -- guard 2: no manual value is involved
  select count(*) into v_n from pipeline.manual_locks m join _iq111 t on t.course_id = m.entity_id where m.entity = 'course';
  if v_n <> 0 then raise exception 'guard: % manual locks on these courses; nothing changed', v_n; end if;

  -- before-state, one event per row (the rollback restores from these)
  for r in select f.*, t.why from catalogue.course_fees f join _iq111 t on t.id = f.id loop
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('fees', 'withdraw_paste', 'catalogue.course_fees ' || left(r.id::text, 8),
            jsonb_build_object('issue', 'IQ-00111', 'batch', 'IQ111-CONTAIN-20261104', 'reason', r.why,
                               'before', to_jsonb(r) - 'why'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
  end loop;

  update catalogue.course_fees f set status = 'inactive', valid_to = current_date, updated_at = now(),
         notes = coalesce(f.notes, '') || ' | ' || v_reason || t.why || '.'
    from _iq111 t where t.id = f.id and f.status = 'active';
  get diagnostics v_upd = row_count;
  if v_upd <> 13 then raise exception 'withdrew %, expected 13; rolled back', v_upd; end if;
  select count(*) into v_n from catalogue.course_fees f join _iq111 t on t.id = f.id where f.status = 'inactive' and f.valid_to = current_date;
  if v_n <> 13 then raise exception 'read-back: % of 13 inactive; rolled back', v_n; end if;

  -- scholarship savings built on these fees, recomputed now; the search projection refreshes on its next run
  select array_agg(course_id) into v_courses from _iq111;
  for r in select unnest(v_courses) course_id loop
    perform scholarship.refresh_course_financial_calculations(r.course_id, null);
  end loop;
  select count(*) into v_n from scholarship.course_financial_calculations fc join _iq111 t on t.id = fc.course_fee_id;
  if v_n <> 0 then raise exception 'read-back: % scholarship savings still use a withdrawn fee; rolled back', v_n; end if;
  insert into search.refresh_requests(requested_by) values ('IQ-00111 containment');

  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fees', 'withdraw_paste', 'catalogue.course_fees (13 AI fee reader rows)',
          jsonb_build_object('issue', 'IQ-00111', 'batch', 'IQ111-CONTAIN-20261104', 'fees', 13, 'units_defect', 9, 'audience', 3, 'hold_bypass', 1,
                             'kept', jsonb_build_array('67e4ceca', '51ebae9d', 'a805b998'), 'fallback', 'CRICOS registered fee a year (Rule 2)'),
          '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
end $paste$;
commit;
