-- Guards: F-INT (data population mandate, 9 Nov 2026): the two production tables security.intake_progress_repeats_v1 reads, in the production shape (columns it reads),
-- so the function is loaded verbatim from production (md5 4f3d0930). They are empty: the repeat cases below write their own rows.
create table if not exists pipeline.admin_control_events (id bigserial primary key, area text, action text, target text, created_at timestamptz not null default now());
create table if not exists pipeline.integration_deploy_checks (id bigserial primary key, since timestamptz not null default now(), result jsonb);
