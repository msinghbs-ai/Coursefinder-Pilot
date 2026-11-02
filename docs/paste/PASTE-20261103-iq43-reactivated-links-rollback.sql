-- CF-247 IQ-00043 (Workstream E; Platform Admin decision 3 Nov 2026 08:44 §5): ROLLBACK of PASTE-20261103-iq43-reactivated-links.sql (restore the governed state of the course links the link tranche
-- (2 Nov 2026, event #28622) set inactive and a background writer made active again).
-- the 13 La Trobe links "<kept page>#/overview?studentType=int" (the kept page spelled with a fragment) that job exit-awards-apply
--   (security.exit_awards_apply_v2 -> security.coverage_apply_course_v1) set active again at 2 Nov 23:37 AEDT and every hour since:
--   121337B, 121336C, 110604A, 110603B, 104937H, 106469D, 106468E, 107719E, 107718F, 104806H, 111474J, 106834K, 106309J.
-- Measured read-only 3 Nov 2026 08:56-09:07 AEDT (security.course_link_reactivated_v1 logic): 13 links in 13 courses; no other link shows the same
--   cause (E15 repair #28597 0, E16 containment #28603/#28604/#28616 0, Layer 4 rejections 0, open remediation holds 0; the 8 Auckland links
--   matched by the old address comparison are programme pages, not the rejected listing, and are excluded).
-- md5 of the sorted link ids e31aadeeb50cfc3da853d9a20908a3b6; of the sorted course ids 94137008f2b7784a78f806038d587ed1.
-- Consumer: the website shows the kept (primary) page for all 13 before and after; the block refreshes the 13 and rolls back if any shown link differs.
-- PASTE FILE. Not applied by any migration. Run only if the Platform Admin asks to undo the restore.
-- Changes catalogue.course_links status inactive -> active (is_primary stays false) for exactly the same 13 rows. Nothing is deleted.
begin;
do $$
declare
  v_ids uuid[] := array[
    '041158b3-aeac-42a6-8006-cf2017bb5470', '06d3e2ce-54b8-44a6-9476-2684063f619c', '1418d09f-9dbf-4d72-b180-7463758c898f', '42d55182-a0e7-4a62-af44-f96611216ae9',
    '80651f64-b8ad-40e4-bb6c-d8c51580e0af', '8778302e-4ed5-41ea-b92c-293f91355d49', 'b742bbd0-896a-446f-bfdc-04c15d697a54', 'be0436ae-f7b6-4167-a9f3-13f955242f27',
    'c3cecd39-6578-48c3-a24d-d3c81ccee2a5', 'c4a81adb-2fae-4d0f-b3df-fb60cc54f287', 'ce12ebcf-f554-44af-b802-7515ec0680ea', 'd0ef4f13-b9ea-4a34-8701-bb91a518e60a',
    'f26f995c-9566-4b0a-ac59-e2df65566da1'
  ]::uuid[];
  v_n int; v_md5 text; v_upd int; v_courses uuid[]; v_before jsonb; v_after jsonb;
begin
  select count(distinct x), md5(string_agg(x::text, ',' order by x)) into v_n, v_md5 from unnest(v_ids) x;
  if v_n <> 13 or v_md5 <> 'e31aadeeb50cfc3da853d9a20908a3b6' then raise exception 'IQ-00043 rollback guard: id set is % / %', v_n, v_md5; end if;
  select count(*) into v_n from catalogue.course_links where id = any(v_ids) and status = 'inactive' and not is_primary;
  if v_n <> 13 then raise exception 'IQ-00043 rollback guard: % of 13 links are inactive; nothing changed', v_n; end if;
  select array_agg(distinct course_id order by course_id) into v_courses from catalogue.course_links where id = any(v_ids);
  select jsonb_object_agg(d.course_id, d.official_course_url) into v_before from search.course_documents d where d.course_id = any(v_courses);
  perform set_config('cf.manual_edit', 'on', true);  -- fixed: a recorded human decision (the guard lets a person re-activate)
  update catalogue.course_links set status = 'active', updated_at = now() where id = any(v_ids) and status = 'inactive' and not is_primary;
  get diagnostics v_upd = row_count;
  if v_upd <> 13 then raise exception 'IQ-00043 rollback guard: updated %, expected 13; rolled back', v_upd; end if;
  perform search.refresh_course_enrichment_scoped_v1(v_courses, true);
  select jsonb_object_agg(d.course_id, d.official_course_url) into v_after from search.course_documents d where d.course_id = any(v_courses);
  if v_after is distinct from v_before then raise exception 'IQ-00043 rollback guard: a shown course link changed; rolled back'; end if;
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('housekeeping', 'iq43_reactivated_link_restore_rollback', 'catalogue.course_links',
          jsonb_build_object('count', v_upd, 'ids_md5', 'e31aadeeb50cfc3da853d9a20908a3b6', 'reactivated', to_jsonb(v_ids)));
end $$;
commit;
