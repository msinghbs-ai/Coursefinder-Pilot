-- CF-247 (Decision 205): schedule the institution-level reader. Verified live on 1 Oct 2026 after the worker was deployed
-- (Pilot PR #227): one run of mode "provider_facts" searched 12 providers, found 24 documents, read 6 fee pages and
-- queued 4 linked fee schedules (PDFs). The job runs every 10 minutes with 12 searches and 8 documents (about 50
-- Firecrawl credits a run, about 7,000 for the 450 queued searches); the Firecrawl reserve guard still applies.
-- Nothing is written to the catalogue by this job: fee schedules wait for a Platform Admin's approval.

select cron.unschedule(jobid) from cron.job where jobname = 'provider-facts';
select cron.schedule('provider-facts', '*/10 * * * *',
  $$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"provider_facts","search_limit":12,"read_limit":8}'::jsonb)$$);

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('provider-facts', 'Course pages', 24, 'Find and read fee schedules',
        'Finds each university''s international fee schedule (and its English policy and academic calendar) on its own site, follows linked fee PDFs and reads them as evidence. Fees are added only after a Platform Admin approves each schedule.', 5, false)
on conflict (jobname) do update set area = excluded.area, sort = excluded.sort, label = excluded.label, description = excluded.description,
       control_rank = excluded.control_rank, batch_editable = excluded.batch_editable;
