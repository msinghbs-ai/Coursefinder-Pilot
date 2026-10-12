-- CF-247 v2.15.255 (12 Oct 2026). Providers › Onboarding took about 9 seconds to load, and the onboarding job counts each university's
-- read course pages every minute: pipeline.coverage_course_pages had no index by provider, so each count read the whole table
-- (about 33,000 rows) once per university. A partial index on read pages by provider. Nothing dropped.
create index if not exists coverage_course_pages_provider_read_idx on pipeline.coverage_course_pages (provider_id) where read_status = 'read';
