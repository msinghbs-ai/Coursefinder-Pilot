-- Planner no-step memory (CF-247 F-OPS, IQ-00355): the tables and helpers security.enrich_plan_auto_v1 uses, cut to the columns it uses (shapes as live, 10 Nov 2026).
-- The helpers that decide WHAT is in the plan (security.enrich_plan_v1, security.enrich_plan_inputs_v1, security.enrich_plan_priority_v1) are STUBS that return what
-- the fixture puts in the fx_ tables; the planner's own selection, ordering, window and recording are the live body, unchanged except by the migration. Nothing here is a Supabase project.
create schema if not exists security; create schema if not exists pipeline; create schema if not exists catalogue;
create table catalogue.providers (id uuid primary key default gen_random_uuid(), name text);
create table pipeline.platform_toolset_settings (toolset_key text not null, key text not null, label text not null default '', help text not null default '', kind text not null default 'number',
  value jsonb not null, min_value numeric, max_value numeric, unit text, sort int not null default 100, reason text, updated_by uuid, updated_at timestamptz not null default now(),
  section text not null default 'Notices', used_by text, control_class text check (control_class in ('human', 'automatic', 'retiring')), primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
-- the settings the planner reads, as live
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values ('pipeline', 'plans.redo_days', '14'), ('pipeline', 'plans.auto_open_max', '40'), ('pipeline', 'plans.auto_per_run', '2'),
  ('pipeline', 'plans.priority_countries', '["NZ"]'), ('pipeline', 'plans.replan_per_hour', '5'), ('pipeline', 'plans.replan_min_new_gaps', '5'), ('pipeline', 'plans.replan_min_days', '2'),
  ('pipeline', 'plans.replan_on_evidence', '1'), ('pipeline', 'plans.replan_on_retry', '1'), ('pipeline', 'plans.fair_order', '1'), ('pipeline', 'plans.run_now_supersedes_auto', '1'),
  ('pipeline', 'plans.retry_ignores_min_days', '1');
create table pipeline.enrich_plan_control (id int primary key, auto_enabled boolean, owner uuid, reason text);
insert into pipeline.enrich_plan_control values (1, true, null, 'fixture');
create table pipeline.enrich_plan_runs (id uuid primary key default gen_random_uuid(), provider_id uuid, mode text, state text default 'queued', steps jsonb, estimate jsonb,
  requested_by uuid, reason text, created_at timestamptz default now());
create unique index enrich_plan_runs_one_open on pipeline.enrich_plan_runs (provider_id) where state in ('queued', 'running');
create table pipeline.enrich_plan_noop (provider_id uuid primary key references catalogue.providers(id) on delete cascade, fingerprint text not null, at timestamptz not null default now());
create table pipeline.enrich_plan_auto_runs (id bigserial primary key, result jsonb, room int, at timestamptz default now());
create table security.fx_hidden (provider_id uuid);
create view security.provider_hidden_v1 as select provider_id from security.fx_hidden;
-- the fixture's universities: the order the priority function returns, and the plan each one has
create table security.fx_priority (provider_id uuid primary key, missing int, country text, best_rank int);
create table security.fx_plan_steps (provider_id uuid primary key, steps jsonb);
create function security.enrich_plan_priority_v1() returns table(provider_id uuid, missing int, country text, best_rank int) language sql stable as $$ select * from security.fx_priority $$;
create function security.enrich_plan_v1(p uuid) returns jsonb language sql stable as $$
  select jsonb_build_object('provider_id', p, 'est_credits', 0, 'est_usd', 0, 'steps', coalesce((select steps from security.fx_plan_steps where provider_id = p), '[]'::jsonb)) $$;
create function security.enrich_plan_inputs_v1(p uuid) returns jsonb language sql stable as $$
  select jsonb_build_object('evidence_at', null, 'central_at', null, 'retry_steps', '[]'::jsonb, 'evidence_new', 0, 'central_new', false) $$;
create function security.enrich_plan_auto_note_v1(p_result jsonb, p_room int default null) returns jsonb language plpgsql as $$
begin insert into pipeline.enrich_plan_auto_runs(result, room) values (p_result, p_room); return p_result; end $$;
