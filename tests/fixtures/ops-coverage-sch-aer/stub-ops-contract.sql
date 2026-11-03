-- Workstream A's shared contract (migration 20261104010000), as a minimal stub of exactly the names workstream C codes against
-- (Integration Controller brief, 3 Nov 2026 15:45). Used only on the isolated fixture database until A's branch is pushed.
create table if not exists pipeline.ops_root_causes(code text primary key, class text not null check (class in ('transient', 'data', 'rule', 'policy', 'dependency', 'capacity')),
  title text not null, description text, detect jsonb, created_at timestamptz not null default now());
create table if not exists pipeline.ops_remedies(code text primary key, title text not null, treats text[] not null default '{}',
  authority text not null check (authority in ('auto', 'release', 'admin')), action_fn regprocedure, verify_fn regprocedure, max_attempts_key text, cooldown_key text,
  active boolean not null default true, notes text);
create table if not exists pipeline.ops_remedy_runs(id bigserial primary key, issue_id bigint, remedy_code text, started_at timestamptz, finished_at timestamptz,
  before jsonb, after jsonb, result text, evidence jsonb);
create table if not exists pipeline.ops_outcome_codes(code text primary key, title text, counts_as_movement boolean);
insert into pipeline.ops_outcome_codes values ('succeeded_with_result', 'Succeeded with result', true), ('succeeded_no_movement', 'Succeeded, no movement', false),
  ('not_needed', 'Not needed', false), ('deferred_dependency', 'Deferred for dependency', false), ('blocked_policy', 'Blocked by policy', false),
  ('blocked_evidence', 'Blocked by evidence', false), ('failed_retryable', 'Failed, retryable', false), ('failed_remediation', 'Failed, needs remediation', false)
on conflict do nothing;
create table if not exists pipeline.admin_jobs(id uuid primary key default gen_random_uuid(), state text);
alter table pipeline.admin_jobs add column if not exists outcome text references pipeline.ops_outcome_codes(code);
alter table pipeline.admin_jobs add column if not exists outcome_detail jsonb;
alter table pipeline.integration_issues add column if not exists correlation_key text;
alter table pipeline.integration_issues add column if not exists diagnosis jsonb;
alter table pipeline.integration_issues add column if not exists remedy_code text;
alter table pipeline.integration_issues add column if not exists remedy_attempts int default 0;
alter table pipeline.integration_issues add column if not exists next_action_at timestamptz;

create or replace function security.ops_root_cause_register_v1(p_code text, p_spec jsonb) returns jsonb language plpgsql as $f$
begin
  insert into pipeline.ops_root_causes(code, class, title, description, detect) values (p_code, p_spec->>'class', p_spec->>'title', p_spec->>'description', p_spec->'detect')
  on conflict (code) do update set class = excluded.class, title = excluded.title, description = excluded.description, detect = excluded.detect;
  return jsonb_build_object('code', p_code);
end $f$;
create or replace function security.ops_remedy_register_v1(p_code text, p_spec jsonb) returns jsonb language plpgsql as $f$
begin
  if p_spec ? 'action_fn' and to_regprocedure(p_spec->>'action_fn') is null then raise exception 'action_fn % does not exist', p_spec->>'action_fn'; end if;
  insert into pipeline.ops_remedies(code, title, treats, authority, action_fn, verify_fn, max_attempts_key, cooldown_key, active, notes)
  values (p_code, p_spec->>'title', array(select jsonb_array_elements_text(coalesce(p_spec->'treats', '[]'::jsonb))), p_spec->>'authority',
          to_regprocedure(p_spec->>'action_fn'), to_regprocedure(p_spec->>'verify_fn'), p_spec->>'max_attempts_key', p_spec->>'cooldown_key',
          coalesce((p_spec->>'active')::boolean, true), p_spec->>'notes')
  on conflict (code) do update set title = excluded.title, treats = excluded.treats, authority = excluded.authority, action_fn = excluded.action_fn,
         verify_fn = excluded.verify_fn, max_attempts_key = excluded.max_attempts_key, cooldown_key = excluded.cooldown_key, active = excluded.active, notes = excluded.notes;
  return jsonb_build_object('code', p_code);
end $f$;
create or replace function security.job_outcome_set_v1(p_job uuid, p_outcome text, p_detail jsonb) returns void language sql as
  $f$ update pipeline.admin_jobs set outcome = p_outcome, outcome_detail = p_detail where id = p_job $f$;
