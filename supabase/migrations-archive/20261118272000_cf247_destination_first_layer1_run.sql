-- CF-247 s695: the first run of the destination sources through the standard Layer 1 schedule (S2-Build; Platform Admin 18 Nov 2026 22:04).
-- Pilot #1318 (20261118262000) registered the five Australian destination sources in the Layer 1 Register; their first monthly run is due in
-- December. This change makes the Home Affairs and JSA sources due now, so the next hourly tick of coursefinder-layer1-regulatory-scheduler
-- queues them and layer1-operations-scheduled loads them through layer1-destination-geo-loader: the rendered Home Affairs pages and the JSA
-- workbook go to Supabase Storage, their evidence records name the source, and the facts go into the destination editions (a published
-- edition with a new fact opens a successor edition, 20261118256000 and 20261118265000). After the run each source's next run is 30 days on.
-- ABS and BOM keep their December dates (their editions are published and their files are read monthly). Fair Work stays paused.
-- Nothing is dropped or deleted. G3 untouched.
-- Replaces: nothing.
-- Retires: nothing.

update pipeline.layer1_source_operations o
   set next_verification_at = now(), change_reason = 'First run through the standard Layer 1 schedule (20261118272000, s695)', updated_at = now()
  from pipeline.sources s
 where s.id = o.source_id and s.metadata->>'source_system' = 'DESTINATION' and not o.paused
   and s.label in ('Department of Home Affairs Student & Graduate Visa Rules', 'Jobs and Skills Australia (JSA) OSCA & Table 1');

do $$
begin
  if (select count(*) from pipeline.layer1_source_operations o join pipeline.sources s on s.id = o.source_id
       where s.metadata->>'source_system' = 'DESTINATION' and o.next_verification_at <= now()) <> 2 then
    raise exception 'post-check: two destination sources are due';
  end if;
  if not (select o.paused from pipeline.layer1_source_operations o join pipeline.sources s on s.id = o.source_id where s.label = 'Fair Work Ombudsman National Minimum Wage') then
    raise exception 'post-check: Fair Work stays paused';
  end if;
  if (select count(*) from cron.job where jobname = 'coursefinder-layer1-regulatory-scheduler' and active) <> 1 then raise exception 'post-check: the Layer 1 scheduler is active'; end if;
end $$;
