-- Guards: Platform Admin mandate 5 Nov 2026 12:44 §11 (production-parity DB tests): production shapes this change reads that the base
-- (and, from 5 Nov 2026 16:10, the production shape of pipeline.manual_locks: mode not null, set_by, set_at, primary key)
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
alter table pipeline.manual_locks add column if not exists mode text, add column if not exists set_by uuid, add column if not exists set_at timestamptz;
update pipeline.manual_locks set mode = 'value' where mode is null;
alter table pipeline.manual_locks alter column mode set not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'pipeline.manual_locks'::regclass and pg_get_constraintdef(oid) like '%mode%') then
    alter table pipeline.manual_locks add constraint manual_locks_mode_check check (mode in ('value', 'removed'));
  end if;
end $$;
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'pipeline.manual_locks'::regclass and contype = 'p') then
    alter table pipeline.manual_locks add primary key (entity, entity_id, field);
  end if;
end $$;
