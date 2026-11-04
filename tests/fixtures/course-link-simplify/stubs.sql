-- CF-247 Course Link simplification (migration 20261104570000) on isolated fixtures: live shapes beyond ../l4-course-link, which run.sh builds
-- first. Columns read from production information_schema (read-only, 4 Nov 2026 17:11 AEDT). Scratch PostgreSQL only; nothing here is live data.

-- component register columns 20261104280000 writes (live columns)
alter table pipeline.component_register add column if not exists updated_at timestamptz, add column if not exists replaced_by text,
  add column if not exists retire_after date;
-- coverage binding columns the classification reads (live columns)
alter table pipeline.coverage_course_pages add column if not exists bound_at timestamptz;
-- provider column the report reads (live column)
alter table catalogue.providers add column if not exists short_name text;
