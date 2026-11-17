-- CF-247 IQ-00111 (P0 fee integrity), correction. PASTE FILE: Platform Admin only, SQL editor of fxcwkweaxjtknorudmwp (NOT coursefinder-demo).
-- NEEDS PLATFORM ADMIN APPROVAL: it enters a fee by hand and settles a raised fee check hold (Layer 4 ref 6619496), both person decisions.
-- Run only AFTER PASTE-20261104-fee-units-holds-containment.sql. Rollback: PASTE-20261104-fee-units-holds-correction-rollback.sql.
-- Route: the governed route of the Layer 4 "Fee fails the check" card, choice "Open the course: Enter or confirm the fee on the course", i.e.
-- public.admin_course_edit(course, 'set_tuition', ...) (a manual entry from the manual_entry source plus a manual lock 'value'), followed by the
-- hold's release through security.flag_release_v1. admin_course_edit needs a signed-in curator (auth.uid()), so this paste does exactly what it
-- does, with cf.manual_edit on, and adds the stored evidence. The same result by hand: Layer 4 > Fee fails the check > Murdoch 096011C > Open
-- the course > Tuition 37,800, year 2027, per year, reason as below; then release the hold with the reason below.
--
-- The one course whose real annual figure is clear and differs from what consumers show after containment:
--   Murdoch 096011C Graduate Diploma in Australian Migration Law and Practice (course d9dc5bb8, 52 weeks, international). Stored page a58f1c88
--   (https://www.murdoch.edu.au/course/postgraduate/g1104, captured 2 Nov 2026 14:17 UTC): "Full course fee (international) An estimate of the total
--   tuition fees for the entire course, based on standard full-time study. 2027 $37,800". One-year course, so 37,800 a year for 2027. The adapter read
--   the same 37,800 and the fee check held it at 31% over the CRICOS registered total of 28,920 (hold 6619496, raised 2 Nov 14:19 UTC); the page is
--   the newer, provider-stated figure. After containment consumers show 28,920 (CRICOS); after this paste 37,800 (Rule 2: a hand-entered fee for 2027,
--   this year or later). Scholarship savings are recomputed from 37,800 (Murdoch 20% -> 7,560, 15% -> 5,670, 25% -> 9,450).
-- Not corrected here, and why:
--   UNSW 0100702, 0100908, 052690E, 080476A, 108475A, 121321K: the page gives the whole fee of a course shorter than a year (31,000-32,000); there is
--     no clear annual figure, and the CRICOS fallback consumers now show (30,500-31,500) is that whole fee. The fixed reader sends a re-read to Layer 4.
--   HELI 102291B (24,600), VIT 085576A (17,000), VIT 114822C (24,000): the clear annual figure equals the CRICOS fallback consumers now show; nothing
--     to correct. VIT 114579J: its active adapter row (24,000, 2026) is already right.
--   Reach 106655B: onshore 27,000 for 2 years (13,500) disagrees with the CRICOS registered 34,000; not clear; the fixed reader sends it to Layer 4.
--   WSU 121432C: its fee check hold is pending in Layer 4 (the 37,141 sits beside a Commonwealth Supported Places label); a person decides there.
-- Guards: the containment ran (52bc162c inactive with its note); the course holds no active provider fee and no manual lock; hold 6619496 is raised;
-- the stored page is the one quoted; exactly one fee inserted, one lock, one hold released. Nothing is deleted.
begin;
do $paste$
declare
  v_course uuid := 'd9dc5bb8-025b-46ca-ac24-7ca13157599f'; v_ev uuid := 'a58f1c88-e3de-4561-b4f9-0c415b960da0'; v_flag bigint := 6619496;
  v_src uuid; v_n int; v_fee uuid; v_rel jsonb;
  v_reason text := 'IQ-00111 correction (Platform Admin paste, 4 Nov 2026): stored page a58f1c88 states "Full course fee (international) ... entire course ... 2027 $37,800" for the 1-year course; entered as 37,800 a year for 2027';
begin
  select count(*) into v_n from catalogue.course_fees where id = '52bc162c-a1e0-4965-af76-d82b4b1e9839' and status = 'inactive' and notes like '%IQ-00111 P0 containment%';
  if v_n <> 1 then raise exception 'guard: the containment paste has not run (52bc162c is not withdrawn); nothing changed'; end if;
  select count(*) into v_n from catalogue.course_fees where course_id = v_course and fee_type = 'provider_current_tuition' and status = 'active';
  if v_n <> 0 then raise exception 'guard: the course holds % active provider fee(s); nothing changed', v_n; end if;
  select count(*) into v_n from pipeline.manual_locks where entity = 'course' and entity_id = v_course;
  if v_n <> 0 then raise exception 'guard: the course has a manual lock; nothing changed'; end if;
  select count(*) into v_n from pipeline.enrichment_flags where id = v_flag and entity_key = v_course::text and reason_code = 'fee_crosscheck' and state = 'raised';
  if v_n <> 1 then raise exception 'guard: hold 6619496 is not raised for this course; nothing changed'; end if;
  select count(*) into v_n from pipeline.evidence_artifacts where id = v_ev and source_url = 'https://www.murdoch.edu.au/course/postgraduate/g1104' and storage_path is not null;
  if v_n <> 1 then raise exception 'guard: stored page a58f1c88 is not the Murdoch g1104 page; nothing changed'; end if;
  select id into v_src from pipeline.sources where source_type = 'manual_entry' limit 1;
  if v_src is null then raise exception 'guard: no manual_entry source; nothing changed'; end if;

  perform set_config('cf.manual_edit', 'on', true);
  insert into catalogue.course_fees(course_id, fee_year, audience, fee_type, amount, currency_code, basis, notes, source_id, evidence_id, confidence, source_fee_key, status, last_verified_at)
  values (v_course, 2027, 'international', 'provider_current_tuition', 37800, 'AUD', 'annual', 'Manual entry | ' || v_reason, v_src, v_ev, 1,
          'manual:' || extract(epoch from clock_timestamp())::bigint, 'active', now())
  returning id into v_fee;
  if v_fee is null then raise exception 'the fee was not written; rolled back'; end if;
  insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by) values ('course', v_course, 'tuition', 'value', '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
  perform set_config('cf.manual_edit', '', true);

  v_rel := security.flag_release_v1(v_flag, 'Platform Admin (paste IQ-00111)', 'person',
             'Layer 4: Fee fails the check: page fee confirmed on the course. ' || v_reason, jsonb_build_object('evidence_id', v_ev, 'fee_id', v_fee), false);
  if v_rel is null then raise exception 'hold 6619496 was not released; rolled back'; end if;

  select count(*) into v_n from catalogue.course_fees where course_id = v_course and fee_type = 'provider_current_tuition' and status = 'active' and amount = 37800 and fee_year = 2027;
  if v_n <> 1 then raise exception 'read-back: % active 2027 fees of 37,800; rolled back', v_n; end if;
  perform scholarship.refresh_course_financial_calculations(v_course, null);
  insert into search.refresh_requests(requested_by) values ('IQ-00111 correction');
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fees', 'correct_paste', 'catalogue.course_fees ' || left(v_fee::text, 8) || ' (Murdoch 096011C)',
          jsonb_build_object('issue', 'IQ-00111', 'batch', 'IQ111-CORRECT-20261104', 'course_id', v_course, 'fee_id', v_fee, 'amount', 37800, 'fee_year', 2027,
                             'evidence_id', v_ev, 'hold_released', v_flag, 'lock', 'tuition/value', 'replaces_withdrawn', '52bc162c'),
          '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
end $paste$;
commit;
