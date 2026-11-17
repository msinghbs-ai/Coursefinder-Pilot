-- CF-247 IQ-00111 OPTIONAL interim stop, until migration 20261104140000 (fee reader units and holds; worker v0.59.6) is released.
-- PASTE FILE, Platform Admin only, fxcwkweaxjtknorudmwp. Reversible by setting the value back to 1 on Settings > Pipeline settings.
-- Why: the released reader still divides by the AU profile's 8 units and admits course-page fees while a fee hold or exclusion is active
-- (Murdoch and WSU were queued by enqueue path b one minute after their hold, because an excluded adapter fee queues the page). An Enrich
-- fields request (path a) requeues an already-read course page, which would re-admit a contained value or admit 088407E 44,300 / 092696A 50,360.
-- What it does: fees.course_pages 1 -> 0, which stops security.fee_course_pages_enqueue_v1 (paths a and b). Fee schedule pages keep being read.
-- Guard: the setting is 1 now; exactly 1 row changed.
begin;
do $s$
declare v_n int;
begin
  update pipeline.platform_toolset_settings set value = to_jsonb(0), updated_at = now(), updated_by = 'Platform Admin (paste)',
         reason = 'IQ-00111 interim: stop AI fee reads of course pages until the units and holds fix is released (4 Nov 2026)'
   where toolset_key = 'pipeline' and key = 'fees.course_pages' and value = to_jsonb(1);
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'guard: fees.course_pages was not 1 (% rows); nothing changed', v_n; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fees', 'setting_paste', 'pipeline.platform_toolset_settings fees.course_pages',
          jsonb_build_object('issue', 'IQ-00111', 'before', 1, 'after', 0, 'until', 'migration 20261104140000 released'),
          '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
end $s$;
commit;
