-- CF-247 (22 Oct 2026). Platform Admin 22:32 (website review): "Intakes: The intake information and graphs are not accurate. All
-- information must match the official university website without alterations or discrepancies." Choice 22:40: "Page-only months, no API
-- change".
-- Found: intake months came from three places: the course's own page (current read), an older read of the same page, and the
-- university's academic calendar (a page saying "Semester 1", or nothing, turned into months by the calendar: 1,168 AU, NZ and CA courses).
-- 1 Intakes made from a calendar are withdrawn (status withdrawn, kept for the record), and the two jobs that make them are switched off
--   and marked retiring: provider-calendar-intakes (security.semester_intake_apply_v1) and provider-calendar-defaults
--   (security.calendar_default_intakes_apply_v1).
-- 2 Where the course's current page read gave its intakes, months from an older read of that page are withdrawn (the page changed).
-- 3 Months from an older read of the official page stay until the page is read again (they are what the page said); the website search
--   copy is asked to refresh. The API shape is unchanged.
-- Replaces: calendar-derived intakes (jobs provider-calendar-intakes and provider-calendar-defaults switched off)
-- Retires: security.semester_intake_apply_v1, security.calendar_default_intakes_apply_v1 (retiring; dropped later by a paste file)
do $fix$
declare v_cal int; v_old int;
begin
  update catalogue.course_intakes i set status = 'withdrawn'
   where i.status = 'active' and coalesce(i.source_intake_key, '') like 'calendar%';
  get diagnostics v_cal = row_count;
  with cur as (select distinct i.course_id from catalogue.course_intakes i join pipeline.coverage_course_pages pg on pg.course_id = i.course_id
                where i.status = 'active' and pg.evidence_id is not null and i.evidence_id = pg.evidence_id)
  update catalogue.course_intakes i set status = 'withdrawn'
    from cur, pipeline.coverage_course_pages pg
   where i.course_id = cur.course_id and pg.course_id = i.course_id and i.status = 'active' and i.evidence_id is distinct from pg.evidence_id;
  get diagnostics v_old = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('course_intakes', 'page_only', 'all', jsonb_build_object('calendar_withdrawn', v_cal, 'older_read_withdrawn', v_old,
          'reason', 'Platform Admin 22 Oct 2026 "Page-only months, no API change": intakes must match the official university website'));
  insert into search.refresh_requests(requested_by) values ('intakes page only: ' || v_cal || ' calendar and ' || v_old || ' older-read months withdrawn');
end $fix$;

select cron.alter_job((select jobid from cron.job where jobname = 'provider-calendar-intakes'), active := false);
select cron.alter_job((select jobid from cron.job where jobname = 'provider-calendar-defaults'), active := false);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.semester_intake_apply_v1', 'Admission', 'Semester-only intakes turned into months by the calendar', 'retiring', '{}', '20261022042000'),
 ('function', 'security.calendar_default_intakes_apply_v1', 'Admission', 'College intakes from the approved calendar', 'retiring', '{}', '20261022042000')
on conflict (kind, name) do update set status = 'retiring', note = 'Platform Admin 22 Oct 2026: intakes only from the course''s own page (20261022042000)', updated_at = now();
do $dry$ begin raise exception 'DRYRUN OK %', (select detail from pipeline.admin_control_events where area='course_intakes' order by id desc limit 1); end $dry$;
