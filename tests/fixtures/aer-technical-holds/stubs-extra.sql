-- Stand-ins for objects the AER technical holds migrations need beyond the E13 / D-R2 chain (shape only; no live data).
create schema if not exists cron;
create table if not exists cron.job (jobname text primary key, schedule text, command text);
create or replace function cron.schedule(p_name text, p_schedule text, p_cmd text) returns bigint language sql as $$ insert into cron.job values (p_name, p_schedule, p_cmd) on conflict (jobname) do nothing; select 1::bigint $$;
create table if not exists pipeline.automation_catalogue (jobname text primary key, area text, sort int, label text, description text, control_rank int, batch_editable boolean, layer23_stage text);
alter table pipeline.admin_jobs add column if not exists kind text, add column if not exists lane text, add column if not exists state text, add column if not exists title text, add column if not exists args jsonb,
  add column if not exists progress jsonb, add column if not exists requested_by uuid, add column if not exists reason text, add column if not exists scope text;
alter table pipeline.layer4_review_items alter column id set default gen_random_uuid();
create table if not exists pipeline.layer4_item_readiness (item_id uuid primary key, gate jsonb, gate_checked_at timestamptz, readiness text);
alter table catalogue.courses add column if not exists lifecycle_status text default 'active';
