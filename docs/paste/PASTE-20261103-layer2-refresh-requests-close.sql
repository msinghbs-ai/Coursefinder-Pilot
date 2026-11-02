-- PASTE (Platform Admin, SQL editor of production fxcwkweaxjtknorudmwp): close the stale Layer 2 refresh requests and switch off the
-- Layer 2 refresh schedules. CF-247 Workstream E, 3 Nov 2026 (Platform Admin direction 09:32; acceptance report engineering plan item 6;
-- controls audit defect 3). Migration 20261103120000 marks Scheduled jobs › Refresh schedules (Layer 2) and its Run on demand retiring.
--
-- Why: no function processes Layer 2 refresh requests. 206 were queued (1 Sep to 15 Oct 2026; 202 Layer 4 returns, 3 freshness, 1 important
-- date); the last Layer 2 request completed on 28 Sep. The hourly job coursefinder-m2-3-refresh-intelligence-tick keeps writing a new Layer 2
-- request whenever an enabled Layer 2 schedule falls due and none is queued, so closing the requests alone would refill the queue: the 9
-- enabled Layer 2 schedules are switched off in the same step. The enrichment engines (standing gap queue, enrichment plans, course-link
-- search, scholarship discovery) do this work today.
--
-- What it does (nothing is deleted):
--   1. Refuses unless the set is exactly the one measured read-only on 3 Nov 2026 10:35 AEDT:
--        205 queued Layer 2 requests other than the important-date one, id md5 af2e4ea5b84921f67b4ee7bdbbaf0382;
--        9 enabled Layer 2 schedules, id md5 de1f728ba4f8e6ca04420ea1e5ac2f42.
--   2. Records both id lists in pipeline.admin_control_events (action layer2_refresh_close), for the rollback.
--   3. Sets the 205 requests to cancelled (completed_at now, schedule_error says why) and the 9 schedules to enabled = false.
-- Left alone on purpose: the one queued important-date request (a337ac2f-...): the tick writes a new important-date request whenever none
-- is queued, running or completed, so cancelling it would only make a new one. Layer 1 and Layer 3/4 requests and schedules are untouched.
-- A second run is refused (the measured set no longer matches). Rollback: PASTE-20261103-layer2-refresh-requests-close-rollback.sql.
begin;

do $$
declare n_r int; m_r text; n_p int; m_p text;
begin
  select count(*), md5(string_agg(id::text, ',' order by id)) into n_r, m_r
    from pipeline.refresh_requests where requested_layer = 2 and status = 'queued' and trigger_type <> 'important_date';
  select count(*), md5(string_agg(id::text, ',' order by id)) into n_p, m_p
    from pipeline.refresh_policies where layer = 2 and enabled;
  if n_r <> 205 or m_r is distinct from 'af2e4ea5b84921f67b4ee7bdbbaf0382' then
    raise exception 'refused: the queued Layer 2 requests are not the measured set (% rows, id md5 %); measure again', n_r, m_r; end if;
  if n_p <> 9 or m_p is distinct from 'de1f728ba4f8e6ca04420ea1e5ac2f42' then
    raise exception 'refused: the enabled Layer 2 schedules are not the measured set (% rows, id md5 %); measure again', n_p, m_p; end if;
end $$;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'scheduler', 'layer2_refresh_close', 'pipeline.refresh_requests',
       jsonb_build_object(
         'requests', (select jsonb_agg(id order by id) from pipeline.refresh_requests where requested_layer = 2 and status = 'queued' and trigger_type <> 'important_date'),
         'policies', (select jsonb_agg(id order by id) from pipeline.refresh_policies where layer = 2 and enabled),
         'count_requests', 205, 'count_policies', 9,
         'reason', 'No function processes Layer 2 refresh requests; Scheduled jobs Layer 2 schedules retiring (migration 20261103120000; Platform Admin direction 3 Nov 2026 09:32)'),
       auth.uid();

update pipeline.refresh_requests
   set status = 'cancelled', completed_at = now(),
       schedule_error = 'Closed 3 Nov 2026: no engine processes Layer 2 refresh requests; the Layer 2/3 enrichment engines do this work (paste PASTE-20261103-layer2-refresh-requests-close)'
 where requested_layer = 2 and status = 'queued' and trigger_type <> 'important_date';

update pipeline.refresh_policies set enabled = false, updated_at = now() where layer = 2 and enabled;

do $$
begin
  if exists (select 1 from pipeline.refresh_requests where requested_layer = 2 and status = 'queued' and trigger_type <> 'important_date') then raise exception 'post-check: a Layer 2 request is still queued'; end if;
  if exists (select 1 from pipeline.refresh_policies where layer = 2 and enabled) then raise exception 'post-check: a Layer 2 schedule is still enabled'; end if;
end $$;

commit;

select (select count(*) from pipeline.refresh_requests where requested_layer = 2 and status = 'queued') layer2_queued_left,
       (select count(*) from pipeline.refresh_policies where layer = 2 and enabled) layer2_schedules_enabled;
