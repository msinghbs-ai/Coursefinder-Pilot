-- Guards: Platform Admin mandate 5 Nov 2026 12:44 §11 (production-parity DB tests): production shapes this change reads that the base
-- fixture lacks, copied from the live catalogue (information_schema and pg_constraint, read 5 Nov 2026 13:10).
create table if not exists pipeline.firecrawl_calls (
  id bigserial primary key,
  at timestamp with time zone not null default now(),
  run_id uuid,
  item_id uuid,
  use_case text not null,
  endpoint text not null,
  provider_id uuid,
  course_id uuid,
  url text,
  request jsonb not null default '{}'::jsonb,
  http integer,
  success boolean not null default false,
  error text,
  scrape_id text,
  credits_used numeric,
  proxy_used text,
  page_status integer,
  duration_ms integer,
  outcome text,
  meta jsonb not null default '{}'::jsonb);
