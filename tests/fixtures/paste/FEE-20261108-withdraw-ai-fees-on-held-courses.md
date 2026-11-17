# FEE-20261108 paste 2 of 3: withdraw 4 AI fee reader fees still active on courses whose page fee a fee check excluded (IQ-00111 verification)

PASTE FILE, same rules as paste 1. Closes the gap the 4 Nov containment left: `security.fee_integrity_measure_v1()->>'ai_active_on_held'` = 5 on 8 Nov 2026 (it must be 0 for IQ-00111 to verify).
Written 26-27 Oct, before the 4 Nov hold fix, on courses with an active fee-check exclusion ("the fee read ... is more than 25% from the CRICOS registered course total; held back for review").
Consumers return them today (search.course_documents.provider_tuition_options). After the paste they fall back to the CRICOS registered fee a year (Rule 2), as the 13 contained rows did.

| fee id | course | provider | amount | exclusion text (set) |
|---|---|---|---|---|
| 5d897b64-1f04-4171-8321-228ff54f2388 | 072350D Graduate Diploma of Applied Buddhist Studies | Nan Tien Institute | AUD 23,800 (2027) | read 24,800 a year vs CRICOS 19,200 (18 Oct) |
| 04b4c75e-f020-4d17-a9c4-3310156d8b76 | 107010J Advanced Diploma of IT | Adelaide Institute of Health (AIBT) | AUD 15,000 (2026) | read 7,500 a year, 24 months vs CRICOS 44,000 (18 Oct) |
| 0f7d0c66-05d9-413d-bdde-15d08ac2d30f | 114382M Master of Health Service Management | UTas | AUD 27,338 (2027) | 27,338 a year, 24 months vs CRICOS 74,722.50 (14 Oct) |
| a4f9c399-8194-4b58-bcec-62df728c98af | 093282D Advanced Diploma of Applied Science (Marine Engineering) | UTas | AUD 18,167 (2027) | 18,167 a year, 36 months vs CRICOS 85,905.63 (14 Oct) |

NOT included: `51ebae9d` Reach 105389A AUD 11,500 (2026): the 4 Nov paste recorded it as checked and kept (23,000 whole course over 104 weeks). The measure and the new guard still count it, so
either release its exclusion (a person's ruling) or accept 1 permanent flag. Controller's call.

Before running: open the stored page of each course (evidence on the fee row) and confirm the figure is not the page's international annual fee; if one is right, delete its line from the list and change the count to 3 / recompute the hash.

```sql
begin;
do $paste$
declare v_n int; v_h text; r record;
  v_reason text := 'Withdrawn 8 Nov 2026 (IQ-00111 verification, FEE lane): AI fee active on a course whose page fee a fee check excludes. ';
begin
  create temporary table _ai4 on commit drop as select f.* from catalogue.course_fees f
   where f.id in ('5d897b64-1f04-4171-8321-228ff54f2388', '04b4c75e-f020-4d17-a9c4-3310156d8b76', '0f7d0c66-05d9-413d-bdde-15d08ac2d30f', 'a4f9c399-8194-4b58-bcec-62df728c98af')
     and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.notes like '%AI fee reader (%';
  select count(*), md5(string_agg(id::text || ':' || amount::text || ':' || fee_year::text || ':' || md5(notes), ',' order by id)) into v_n, v_h from _ai4;
  if v_n <> 4 or v_h <> 'e29c033acb86c3904897ffc2677d100a' then raise exception 'guard: % rows, hash %; expected 4 rows as measured on 8 Nov 2026; nothing changed', v_n, v_h; end if;
  select count(*) into v_n from pipeline.manual_locks m join _ai4 t on t.course_id = m.entity_id where m.entity = 'course';
  if v_n <> 0 then raise exception 'guard: % manual locks; nothing changed', v_n; end if;
  for r in select * from _ai4 loop
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('fees', 'withdraw_paste', 'catalogue.course_fees ' || left(r.id::text, 8), jsonb_build_object('batch', 'FEE-20261108-AIHELD', 'reason', 'AI fee on a held course', 'before', to_jsonb(r)), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
  end loop;
  update catalogue.course_fees f set status = 'inactive', valid_to = current_date, updated_at = now(), notes = coalesce(f.notes, '') || ' | ' || v_reason
    from _ai4 t where t.id = f.id and f.status = 'active';
  get diagnostics v_n = row_count;
  if v_n <> 4 then raise exception 'withdrew %, expected 4; rolled back', v_n; end if;
  for r in select course_id from _ai4 loop perform scholarship.refresh_course_financial_calculations(r.course_id, null); end loop;
  select count(*) into v_n from scholarship.course_financial_calculations fc join _ai4 t on t.id = fc.course_fee_id;
  if v_n <> 0 then raise exception 'read-back: % savings still use a withdrawn fee; rolled back', v_n; end if;
  insert into search.refresh_requests(requested_by) values ('FEE-20261108 AI fees on held courses');
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fees', 'withdraw_paste', 'catalogue.course_fees (4 AI fee reader rows)', jsonb_build_object('batch', 'FEE-20261108-AIHELD', 'fees', 4, 'kept', jsonb_build_array('51ebae9d')), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
end $paste$;
commit;
```

Read-back: `select security.fee_integrity_measure_v1()->>'ai_active_on_held';` expect 1 (Reach, kept) or 0 after its exclusion is released; consumers: the four courses return the CRICOS fee a year.

Rollback: restore `status`, `valid_to`, `notes` from `pipeline.admin_control_events` where `detail->>'batch' = 'FEE-20261108-AIHELD'` and `detail ? 'before'` (4 rows), then a `search.refresh_requests` row; same shape as `PASTE-20261104-fee-units-holds-containment-rollback.sql`.
