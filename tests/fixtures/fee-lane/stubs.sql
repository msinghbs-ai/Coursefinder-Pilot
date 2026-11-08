-- CF-247 FEE lane fixture stand-ins (scratch database only). Live columns used by the two migrations that the IQ-00111 fixture did not carry.
create schema if not exists cron;
create table cron.job(jobname text primary key, schedule text, command text);
create function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as $f$
  insert into cron.job values (p_name, p_schedule, p_command) on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command returning 1::bigint $f$;
create table pipeline.automation_catalogue(jobname text primary key, area text, sort int, label text, description text, control_rank int, batch_editable boolean, layer23_stage text);
-- live enrichment_flags columns and constraints (information_schema, 8 Nov 2026)
alter table pipeline.enrichment_flags add column if not exists kind text check (kind in ('hard', 'soft')), add column if not exists raised_by_kind text check (raised_by_kind in ('auto', 'person')),
  add column if not exists release_kind text check (release_kind in ('auto', 'person')), add column if not exists cleared_at timestamptz, add column if not exists evidence jsonb;
alter table pipeline.enrichment_flags add constraint fx_flag_unique unique (entity, entity_key, field, reason_code);
alter table pipeline.layer4_review_items add column if not exists decided_at timestamptz, add column if not exists created_at timestamptz default now(), add column if not exists claimed_at timestamptz;
alter table catalogue.course_fees add column if not exists audience text default 'international';
alter table pipeline.uni_adapter_exclusions add column if not exists active boolean default true;
