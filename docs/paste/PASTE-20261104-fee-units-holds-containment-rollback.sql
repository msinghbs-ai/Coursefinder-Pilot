-- CF-247 IQ-00111 rollback of PASTE-20261104-fee-units-holds-containment.sql. PASTE FILE, Platform Admin only, fxcwkweaxjtknorudmwp.
-- Restores status, valid_to, notes and updated_at of the 13 withdrawn rows from the before-state recorded in pipeline.admin_control_events
-- (batch IQ111-CONTAIN-20261104), then recomputes the scholarship savings and asks for a search refresh. Guards: exactly 13 recorded rows,
-- each still inactive with the containment note; exactly 13 restored. Nothing is deleted.
begin;
do $rb$
declare v_n int; r record;
begin
  select count(*) into v_n from pipeline.admin_control_events e
   where e.area = 'fees' and e.action = 'withdraw_paste' and e.detail->>'batch' = 'IQ111-CONTAIN-20261104' and e.detail ? 'before';
  if v_n <> 13 then raise exception 'guard: % recorded rows, expected 13; nothing changed', v_n; end if;
  select count(*) into v_n from pipeline.admin_control_events e join catalogue.course_fees f on f.id = (e.detail->'before'->>'id')::uuid
   where e.detail->>'batch' = 'IQ111-CONTAIN-20261104' and e.detail ? 'before' and f.status = 'inactive' and f.notes like '%IQ-00111 P0 containment%';
  if v_n <> 13 then raise exception 'guard: % of 13 rows are still in the contained state; nothing changed', v_n; end if;
  update catalogue.course_fees f set status = e.detail->'before'->>'status', valid_to = (e.detail->'before'->>'valid_to')::date,
         notes = e.detail->'before'->>'notes', updated_at = now()
    from pipeline.admin_control_events e
   where e.detail->>'batch' = 'IQ111-CONTAIN-20261104' and e.detail ? 'before' and f.id = (e.detail->'before'->>'id')::uuid and f.status = 'inactive';
  get diagnostics v_n = row_count;
  if v_n <> 13 then raise exception 'restored %, expected 13; rolled back', v_n; end if;
  for r in select distinct (e.detail->'before'->>'course_id')::uuid course_id from pipeline.admin_control_events e
            where e.detail->>'batch' = 'IQ111-CONTAIN-20261104' and e.detail ? 'before' loop
    perform scholarship.refresh_course_financial_calculations(r.course_id, null);
  end loop;
  insert into search.refresh_requests(requested_by) values ('IQ-00111 containment rollback');
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fees', 'withdraw_paste_rollback', 'catalogue.course_fees (13 AI fee reader rows)',
          jsonb_build_object('issue', 'IQ-00111', 'batch', 'IQ111-CONTAIN-20261104', 'restored', 13), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
end $rb$;
commit;
