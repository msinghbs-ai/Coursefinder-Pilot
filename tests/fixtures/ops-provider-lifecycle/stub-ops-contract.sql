-- Workstream A's shared contract (migration 20261104010000), cut to the exact names in the ops brief (3 Nov 2026 15:45 AEDT), so workstream G's
-- migration can be replayed before A lands. Fixture only: never a Supabase project. When A's branch is pushed (git fetch origin cf247-ops-a), load
-- A's migration instead of this file.
create table if not exists pipeline.ops_root_causes (code text primary key, class text not null check (class in ('transient', 'data', 'rule', 'policy', 'dependency', 'capacity')),
  title text not null, description text, detect jsonb not null default '{}', created_at timestamptz not null default now());
create table if not exists pipeline.ops_remedies (code text primary key, title text not null, treats text[] not null default '{}',
  authority text not null check (authority in ('auto', 'release', 'admin')), action_fn regprocedure, verify_fn regprocedure, max_attempts_key text, cooldown_key text,
  active boolean not null default true, notes text);
create table if not exists pipeline.ops_remedy_runs (id bigserial primary key, issue_id bigint, remedy_code text, started_at timestamptz default now(), finished_at timestamptz,
  before jsonb, after jsonb, result text, evidence jsonb);
create table if not exists pipeline.ops_outcome_codes (code text primary key, title text, counts_as_movement boolean);
insert into pipeline.ops_outcome_codes values ('succeeded_with_result', 'Succeeded with a measurable result', true), ('succeeded_no_movement', 'Succeeded without data movement', false),
 ('not_needed', 'Not needed', false), ('deferred_dependency', 'Deferred for a dependency', false), ('blocked_policy', 'Blocked by policy', false),
 ('blocked_evidence', 'Blocked by evidence', false), ('failed_retryable', 'Failed and retryable', false), ('failed_remediation', 'Failed and requiring remediation', false)
on conflict do nothing;
alter table pipeline.integration_issues add column if not exists correlation_key text, add column if not exists diagnosis jsonb, add column if not exists remedy_code text,
  add column if not exists remedy_attempts int default 0, add column if not exists next_action_at timestamptz;

create or replace function security.ops_root_cause_register_v1(p_code text, p_spec jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  insert into pipeline.ops_root_causes(code, class, title, description, detect)
  values (p_code, p_spec->>'class', coalesce(p_spec->>'title', p_code), p_spec->>'description', coalesce(p_spec->'detect', '{}'::jsonb))
  on conflict (code) do update set class = excluded.class, title = excluded.title, description = excluded.description, detect = excluded.detect;
  return jsonb_build_object('code', p_code, 'ok', true);
end $$;

create or replace function security.ops_remedy_register_v1(p_code text, p_spec jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_a regprocedure; v_v regprocedure;
begin
  if nullif(p_spec->>'action_fn', '') is not null then
    v_a := to_regprocedure(p_spec->>'action_fn');
    if v_a is null then raise exception 'remedy %: action function % does not exist', p_code, p_spec->>'action_fn'; end if;
  end if;
  if nullif(p_spec->>'verify_fn', '') is not null then
    v_v := to_regprocedure(p_spec->>'verify_fn');
    if v_v is null then raise exception 'remedy %: verify function % does not exist', p_code, p_spec->>'verify_fn'; end if;
  end if;
  insert into pipeline.ops_remedies(code, title, treats, authority, action_fn, verify_fn, max_attempts_key, cooldown_key, active, notes)
  values (p_code, coalesce(p_spec->>'title', p_code), coalesce(array(select jsonb_array_elements_text(p_spec->'treats')), '{}'), p_spec->>'authority', v_a, v_v,
          p_spec->>'max_attempts_key', p_spec->>'cooldown_key', coalesce((p_spec->>'active')::boolean, true), p_spec->>'notes')
  on conflict (code) do update set title = excluded.title, treats = excluded.treats, authority = excluded.authority, action_fn = excluded.action_fn,
     verify_fn = excluded.verify_fn, max_attempts_key = excluded.max_attempts_key, cooldown_key = excluded.cooldown_key, active = excluded.active, notes = excluded.notes;
  return jsonb_build_object('code', p_code, 'ok', true);
end $$;

create or replace function security.job_outcome_set_v1(p_job uuid, p_outcome text, p_detail jsonb) returns void language sql security definer set search_path = '' as $$
  select null::void $$;
