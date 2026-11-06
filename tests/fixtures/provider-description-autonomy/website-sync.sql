-- Guards: Integration Controller decision 5 Nov 2026 (PR #877 item 3): the existing website-sync-check scan is the only writer of
-- pipeline.website_sync_items. Its live functions (live/security.website_sync_check_v1.sql, live/security.website_sync_candidates_v1.sql)
-- run here unchanged; this file adds the production scan-state table and the columns their candidate query reads (production-website-sync.json).
create table if not exists pipeline.website_sync_scan(
  entity text not null,
  after_key text,
  done boolean not null default false,
  cycles integer not null default 0,
  last_cycle_at timestamptz,
  last_run_at timestamptz,
  last_result jsonb,
  constraint website_sync_scan_pkey primary key (entity));
insert into pipeline.website_sync_scan(entity) values ('course'),('logo'),('provider'),('rankings'),('reference'),('scholarship') on conflict do nothing;
alter table search.course_documents add column if not exists course_id uuid, add column if not exists course_stable_key text;
alter table scholarship.scholarships add column if not exists stable_key text;
