-- CF-247 (3 Oct 2026, 23:40 AEST). Decision 247, part 3 — how changes on the provider's page reach counsellors.
-- Scholarship pages were re-read about every 90 days. A scholarship that is published, or ready to publish, is now
-- re-read at least every 30 days (held ones stay at the reader's own cadence). A re-read that finds a new value,
-- percentage, close date or criteria updates the record (logged in pipeline.scholarship_sweep_changes, never over a
-- value set by hand); the record change reaches the course within 15 minutes (job scholarship-course-attribute), the
-- saving is worked out again at 06:41 AEST, and the 06:17 review withdraws one that no longer passes a check.
-- Job scholarship-reread-cadence (daily 05:37 AEST) brings each such page's next read forward when it is later.
create or replace function security.scholarship_reread_cadence_v1()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'pipeline', 'scholarship', 'security' as $f$
declare v_n int := 0;
begin
  update pipeline.scholarship_pages sp set next_read_at = sp.read_at + interval '30 days' from scholarship.scholarships s where s.id = sp.scholarship_id and s.lifecycle_status = 'active' and sp.read_at is not null and (sp.next_read_at is null or sp.next_read_at > sp.read_at + interval '30 days') and (s.publication_status = 'published' or exists (select 1 from security.scholarship_publishability_v1() p where p.scholarship_id = s.id and p.publishable));
  get diagnostics v_n = row_count;
  return jsonb_build_object('brought_forward', v_n);
end $f$;
revoke all on function security.scholarship_reread_cadence_v1() from public, anon, authenticated;

select cron.schedule('scholarship-reread-cadence', '37 19 * * *', $$select security.scholarship_reread_cadence_v1()$$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('scholarship-reread-cadence', 'Scholarships', 76, 'Re-read published scholarships monthly',
        'Daily at 05:37 AEST: a published or ready-to-publish scholarship''s page is re-read at least every 30 days, so a changed value, percentage or closing date reaches courses and Zoho (Decision 247).', 5, false)
on conflict (jobname) do nothing;

select security.scholarship_reread_cadence_v1();
