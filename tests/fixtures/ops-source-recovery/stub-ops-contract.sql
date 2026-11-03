-- Workstream A's shared contract (ops brief 3 Nov 2026 15:45; A's migration 20261104010000), stubbed with exactly the names other workstreams code
-- against, so this fixture runs before A's branch lands. Never a Supabase project.
create table if not exists pipeline.ops_root_causes (code text primary key, class text not null check (class in ('transient', 'data', 'rule', 'policy', 'dependency', 'capacity')),
  title text, description text, detect jsonb, created_at timestamptz not null default now());
create table if not exists pipeline.ops_remedies (code text primary key, title text, treats text[], authority text not null check (authority in ('auto', 'release', 'admin')),
  action_fn regprocedure, verify_fn regprocedure, max_attempts_key text, cooldown_key text, active boolean default true, notes text);
create table if not exists pipeline.ops_remedy_runs (id bigserial primary key, issue_id bigint, remedy_code text, started_at timestamptz default now(), finished_at timestamptz,
  before jsonb, after jsonb, result text, evidence jsonb);
create table if not exists pipeline.ops_outcome_codes (code text primary key, title text, counts_as_movement boolean);
create or replace function security.ops_root_cause_register_v1(p_code text, p_spec jsonb) returns jsonb language plpgsql as $$
begin
  insert into pipeline.ops_root_causes(code, class, title, description, detect) values (p_code, p_spec->>'class', p_spec->>'title', p_spec->>'description', p_spec->'detect')
  on conflict (code) do update set class = excluded.class, title = excluded.title, description = excluded.description, detect = excluded.detect;
  return jsonb_build_object('code', p_code);
end $$;
create or replace function security.ops_remedy_register_v1(p_code text, p_spec jsonb) returns jsonb language plpgsql as $$
begin
  if p_spec->>'action_fn' is not null and to_regprocedure(p_spec->>'action_fn') is null then raise exception 'remedy %: action_fn % does not exist', p_code, p_spec->>'action_fn'; end if;
  if p_spec->>'verify_fn' is not null and to_regprocedure(p_spec->>'verify_fn') is null then raise exception 'remedy %: verify_fn % does not exist', p_code, p_spec->>'verify_fn'; end if;
  insert into pipeline.ops_remedies(code, title, treats, authority, action_fn, verify_fn, max_attempts_key, cooldown_key, active, notes)
  values (p_code, p_spec->>'title', array(select jsonb_array_elements_text(coalesce(p_spec->'treats', '[]'))), p_spec->>'authority',
          to_regprocedure(p_spec->>'action_fn'), to_regprocedure(p_spec->>'verify_fn'), p_spec->>'max_attempts_key', p_spec->>'cooldown_key', coalesce((p_spec->>'active')::boolean, true), p_spec->>'notes')
  on conflict (code) do update set title = excluded.title, treats = excluded.treats, authority = excluded.authority, action_fn = excluded.action_fn, verify_fn = excluded.verify_fn,
         max_attempts_key = excluded.max_attempts_key, cooldown_key = excluded.cooldown_key, active = excluded.active, notes = excluded.notes;
  return jsonb_build_object('code', p_code);
end $$;
