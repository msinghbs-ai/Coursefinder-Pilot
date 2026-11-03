-- CF-247 IQ-00111 D12 (Platform Admin decision D12, 3 Nov 2026 21:59): send the older AI fee rows admitted on courses with a released fee check
-- decision to Layer 4, with their evidence and the earlier decisions attached. PASTE FILE: Platform Admin, SQL editor of fxcwkweaxjtknorudmwp
-- (NOT coursefinder-demo). Run only after migration 20261104300000 is released. Changes no fee and no decided item: it raises 5 new "Fee fails
-- the check" items (pipeline.enrichment_flags, field fee_ai_recheck) through security.fee_admitted_recheck_v1. No rollback is needed beyond a
-- person deciding each item; an item raised in error is released on the card with "Keep" only after reading it (that withdraws the AI fee).
-- The six rows of D12 (live 3 Nov 2026 22:0x AEDT; active AI fee, fee_crosscheck flag released by a person, fee exclusion active):
--   0f7d0c66 UTas 114382M Master of Health Service Management  27,338 (2027)  decision 18 Oct "Split by group": the page figure is not an annual fee
--   a4f9c399 UTas 093282D Adv Dip Applied Science (Marine Eng)  18,167 (2027)  decision 18 Oct "Split by group"
--   5d897b64 NTI 072350D Graduate Diploma, Applied Buddhist St. 23,800 (2027)  decision 18 Oct "Split by group"
--   51ebae9d Reach 105389A Advanced Diploma of IT              11,500 (2026)  decision 18 Oct "Split by group"
--   04b4c75e AIH 107010J Advanced Diploma of IT                15,000 (2026)  decision 29 Oct L4B-20261029-2007 "Keep the CRICOS total"
--   2bc5fcb3 Reach 106655B (sixth): already withdrawn by the IQ-00111 containment paste; not raised (its re-read goes to Layer 4 by the fixed reader).
-- Guards: exactly these 5 rows, each still active, with the md5 of their ids and notes as measured (ccc44c30f3bf04340cdc7a2ec11223b2); none has
-- a manual lock; none already has a re-check item; exactly 5 raised.
begin;
do $paste$
declare v_ids uuid[] := array['04b4c75e-f020-4d17-a9c4-3310156d8b76', '0f7d0c66-05d9-413d-bdde-15d08ac2d30f', '51ebae9d-67d3-4221-9cb3-1308260f4801',
                              '5d897b64-1f04-4171-8321-228ff54f2388', 'a4f9c399-8194-4b58-bcec-62df728c98af']::uuid[];
        v_n int; v_md5 text; v_r jsonb; v_raised int := 0; v_id uuid;
begin
  if to_regprocedure('security.fee_admitted_recheck_v1(uuid,text,text)') is null then raise exception 'migration 20261104300000 is not released; nothing changed'; end if;
  select count(*), md5(string_agg(f.id::text || ':' || md5(f.notes), ',' order by f.id)) into v_n, v_md5
    from catalogue.course_fees f where f.id = any (v_ids) and f.status = 'active' and f.fee_type = 'provider_current_tuition';
  if v_n <> 5 or v_md5 <> 'ccc44c30f3bf04340cdc7a2ec11223b2' then
    raise exception 'guard: % of 5 rows active, notes md5 % (expected ccc44c30f3bf04340cdc7a2ec11223b2); nothing changed', v_n, v_md5; end if;
  select count(*) into v_n from pipeline.manual_locks m join catalogue.course_fees f on f.course_id = m.entity_id where f.id = any (v_ids) and m.entity = 'course';
  if v_n <> 0 then raise exception 'guard: % manual locks; nothing changed', v_n; end if;
  select count(*) into v_n from pipeline.enrichment_flags x join catalogue.course_fees f on x.entity_key = f.course_id::text where f.id = any (v_ids) and x.field = 'fee_ai_recheck';
  if v_n <> 0 then raise exception 'guard: % re-check items already exist; nothing changed', v_n; end if;
  foreach v_id in array v_ids loop
    v_r := security.fee_admitted_recheck_v1(v_id, 'IQ-00111 D12 (Platform Admin 3 Nov 2026 21:59): admitted by the AI fee reader after this course''s fee check decision, before the reader respected fee holds (fixed in 20261104140000).',
                                           'Platform Admin (paste IQ-00111 D12)');
    if not coalesce((v_r->>'raised')::boolean, false) then raise exception 'fee % was not raised (%); rolled back', v_id, v_r->>'why'; end if;
    v_raised := v_raised + 1;
  end loop;
  if v_raised <> 5 then raise exception 'raised %, expected 5; rolled back', v_raised; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fees', 'recheck_paste', 'pipeline.enrichment_flags (5 fee re-check items)',
          jsonb_build_object('issue', 'IQ-00111', 'decision', 'D12', 'fees', to_jsonb(v_ids), 'raised', v_raised, 'not_raised', '2bc5fcb3 (already withdrawn by the containment)'),
          '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
end $paste$;
commit;
-- Read-back (read only): the 5 items as the Layer 4 inbox shows them
-- select kind, ref, subject, left(why, 140) why, detail->>'evidence_id' stored_copy, jsonb_array_length(detail->'recheck'->'earlier_decisions') decisions
--   from security.layer4_inbox_items_v1() where detail ? 'recheck' order by subject;
