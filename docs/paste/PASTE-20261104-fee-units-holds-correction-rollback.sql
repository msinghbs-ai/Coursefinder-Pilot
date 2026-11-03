-- CF-247 IQ-00111 rollback of PASTE-20261104-fee-units-holds-correction.sql. PASTE FILE, Platform Admin only, fxcwkweaxjtknorudmwp.
-- Withdraws the hand-entered 37,800 (status inactive, note appended) and raises hold 6619496 again. The manual lock is kept: a lock is a person's
-- decision, removed on the course record if the reader should return. Guards: exactly the one fee and hold the correction wrote. Nothing is deleted.
begin;
do $rb$
declare v_n int; v_fee uuid; v_course uuid := 'd9dc5bb8-025b-46ca-ac24-7ca13157599f';
begin
  select (detail->>'fee_id')::uuid into v_fee from pipeline.admin_control_events where detail->>'batch' = 'IQ111-CORRECT-20261104' and action = 'correct_paste' order by id desc limit 1;
  if v_fee is null then raise exception 'guard: the correction was not recorded; nothing changed'; end if;
  perform set_config('cf.manual_edit', 'on', true);
  update catalogue.course_fees set status = 'inactive', valid_to = current_date, updated_at = now(), notes = coalesce(notes, '') || ' | withdrawn by the IQ-00111 correction rollback'
   where id = v_fee and course_id = v_course and status = 'active' and amount = 37800;
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'guard: fee % is not the active 37,800; rolled back', v_fee; end if;
  perform set_config('cf.manual_edit', '', true);
  update pipeline.enrichment_flags set state = 'raised', released_at = null, cleared_at = null, released_by = null, release_kind = null, release_reason = null, updated_at = now()
   where id = 6619496 and state = 'released' and release_reason like 'Layer 4: Fee fails the check: page fee confirmed on the course. IQ-00111%';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'guard: hold 6619496 was not released by the correction; rolled back'; end if;
  perform scholarship.refresh_course_financial_calculations(v_course, null);
  insert into search.refresh_requests(requested_by) values ('IQ-00111 correction rollback');
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fees', 'correct_paste_rollback', 'catalogue.course_fees ' || left(v_fee::text, 8),
          jsonb_build_object('issue', 'IQ-00111', 'batch', 'IQ111-CORRECT-20261104', 'fee_id', v_fee, 'hold_raised_again', 6619496,
                             'lock', 'kept (course d9dc5bb8 tuition/value); remove it on the course record if the reader should return'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
end $rb$;
commit;
