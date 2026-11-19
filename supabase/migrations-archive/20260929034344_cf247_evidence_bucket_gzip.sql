-- CF-247 coverage sweep: course pages are kept as gzipped HTML evidence, but the evidence bucket did not allow the
-- application/gzip type, so every upload was refused and no page evidence was registered (985 verified reads).
-- The type is added (additive). Pages read without evidence are read again: direct reads now; pages that needed
-- Firecrawl after the monthly budget resets (1 Oct 2026), so credits are not spent twice this month.
update storage.buckets set allowed_mime_types=array_append(allowed_mime_types,'application/gzip')
 where id='evidence' and not ('application/gzip'=any(allowed_mime_types));
update pipeline.coverage_course_pages
   set read_status=null, next_read_at=case when fetched_via='firecrawl' then date_trunc('month',now())+interval '1 month 1 hour' else now() end,
       read_attempts=0, leased_until=null
 where read_status='read' and evidence_id is null;
