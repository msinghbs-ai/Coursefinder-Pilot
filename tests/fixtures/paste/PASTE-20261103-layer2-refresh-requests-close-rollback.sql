-- ROLLBACK of PASTE-20261103-layer2-refresh-requests-close.sql (Platform Admin, SQL editor of production fxcwkweaxjtknorudmwp).
-- Puts back exactly what the paste changed, from the id lists it recorded in pipeline.admin_control_events (action layer2_refresh_close):
-- those requests become queued again (completed_at and schedule_error cleared, only while they are still the cancelled rows the paste made)
-- and those schedules are enabled again. Refuses when the paste was not run, or was already rolled back. Nothing is deleted.
begin;

do $$
declare e record; n_r int; n_p int;
begin
  select * into e from pipeline.admin_control_events where area = 'scheduler' and action = 'layer2_refresh_close' order by id desc limit 1;
  if e.id is null then raise exception 'refused: the close paste has not been run'; end if;
  if exists (select 1 from pipeline.admin_control_events where area = 'scheduler' and action = 'layer2_refresh_close_rollback' and (detail->>'close_event')::bigint = e.id) then
    raise exception 'refused: already rolled back (event %)', e.id; end if;
  update pipeline.refresh_requests r set status = 'queued', completed_at = null, schedule_error = null
   where r.id in (select x::uuid from jsonb_array_elements_text(e.detail->'requests') x)
     and r.status = 'cancelled' and r.schedule_error like 'Closed 3 Nov 2026: no engine processes Layer 2 refresh requests%';
  get diagnostics n_r = row_count;
  update pipeline.refresh_policies p set enabled = true, updated_at = now()
   where p.id in (select x::uuid from jsonb_array_elements_text(e.detail->'policies') x) and not p.enabled;
  get diagnostics n_p = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('scheduler', 'layer2_refresh_close_rollback', 'pipeline.refresh_requests', jsonb_build_object('close_event', e.id, 'requests', n_r, 'policies', n_p), auth.uid());
  raise notice 'rolled back: % requests queued again, % schedules enabled again', n_r, n_p;
end $$;

commit;
