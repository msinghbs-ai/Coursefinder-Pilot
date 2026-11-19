-- CF-247 (Decision 204): switch course-link search to the coverage-sweep worker. Verified live on 1 Oct 2026 after the
-- worker was deployed (Pilot PR #224): one run of mode "link_search" searched 12 courses in 5.3 seconds with no failures.
-- The job course-link-search-worker runs every minute with 60 searches (changeable in Automations); the old tick keeps
-- collecting any in-flight pg_net searches and moving candidates, and stops sending (send_via = 'worker').

select cron.unschedule(jobid) from cron.job where jobname = 'course-link-search-worker';
select cron.schedule('course-link-search-worker', '* * * * *',
  $$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"link_search","limit":60}'::jsonb)$$);

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('course-link-search-worker', 'Course pages', 23, 'Search for course pages',
        'Searches each provider''s site for a course''s own page (CRICOS code, then title), several at a time; a found page is used only after the reader confirms it.', 5, true)
on conflict (jobname) do update set area = excluded.area, sort = excluded.sort, label = excluded.label, description = excluded.description,
       control_rank = excluded.control_rank, batch_editable = excluded.batch_editable;

update pipeline.course_link_search_settings set send_via = 'worker', updated_at = now() where id = 1;
