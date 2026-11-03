-- CF-247 P0 autonomous operations: the shared operations contract, owned by workstream A (migration 20261104010000_cf247_ops_controller.sql).
-- Workstreams B, C, D, E, F and G load this file into their scratch fixture database (after their stubs of pipeline.integration_issues,
-- pipeline.admin_jobs and pipeline.platform_toolset_settings) to code against the exact names. Everything below the marker is the migration's
-- contract section byte for byte (tests/fixtures/ops-controller/run.sh and spec s244 check it). Scratch PostgreSQL only; never a Supabase project.
-- >>> contract (tests/fixtures/ops-controller/stub-ops-contract.sql is this section, byte for byte) ------------------------------------------
-- The authority boundary (mandate §2, §6, §15 "the AI must never grant itself broader permissions"): while the controller runs a remedy it sets
-- cf247.ops_remedy to on for that call only. Writes that a remedy may never make are refused in data (triggers in part 2) while it is on.
create or replace function security.ops_remedy_guard_active_v1() returns boolean
language sql stable set search_path to '' as $function$
  select coalesce(current_setting('cf247.ops_remedy', true), '') = 'on'
$function$;
revoke all on function security.ops_remedy_guard_active_v1() from public, anon, authenticated;

create table if not exists pipeline.ops_root_causes (
  code text primary key check (code ~ '^[a-z][a-z0-9_]*$'),
  class text not null check (class in ('transient', 'data', 'rule', 'policy', 'dependency', 'capacity')),
  title text not null,
  description text,
  detect jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
comment on table pipeline.ops_root_causes is 'CF-247 P0 autonomous operations (mandate 3 Nov 2026 15:37 §3): the root-cause taxonomy. One row per cause: its class (transient, data, rule, policy, dependency, capacity), a plain description and detect, the deterministic rule the controller''s classifier evaluates (security.ops_diagnose_v1; grammar in that function''s comment). Written only through security.ops_root_cause_register_v1, by a release; never by a remedy (refused in data). Never read by the consumer API.';
alter table pipeline.ops_root_causes enable row level security;
revoke all on pipeline.ops_root_causes from public, anon, authenticated;

create table if not exists pipeline.ops_remedies (
  code text primary key check (code ~ '^[a-z][a-z0-9_]*$'),
  title text not null,
  treats text[] not null default '{}',
  authority text not null check (authority in ('auto', 'release', 'admin')),
  action_fn regprocedure,
  verify_fn regprocedure,
  max_attempts_key text,
  cooldown_key text,
  active boolean not null default true,
  notes text
);
comment on table pipeline.ops_remedies is 'CF-247 P0 autonomous operations (mandate §3, §15): the remedy registry. treats names the root causes (pipeline.ops_root_causes) a remedy applies to; authority auto is executed by the controller (job ops-controller), release means a code change through the release gates and admin a Platform Admin decision (both only route the issue). action_fn(p_issue bigint) returns jsonb {ok, changed, evidence}; verify_fn(p_issue bigint) returns jsonb {passed, measure, evidence}, called on a later controller run than the action. max_attempts_key and cooldown_key name pipeline settings. Written only through security.ops_remedy_register_v1, by a release; never by a remedy (refused in data). Never read by the consumer API.';
alter table pipeline.ops_remedies enable row level security;
revoke all on pipeline.ops_remedies from public, anon, authenticated;

create table if not exists pipeline.ops_remedy_runs (
  id bigserial primary key,
  issue_id bigint not null references pipeline.integration_issues(id),
  remedy_code text not null references pipeline.ops_remedies(code),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  before jsonb,
  after jsonb,
  result text,
  evidence jsonb not null default '{}'::jsonb
);
comment on table pipeline.ops_remedy_runs is 'CF-247 P0 autonomous operations (mandate §3, §13): every remedy execution by the controller: the issue, the remedy, the measure before the action, the measure after verification, the result (running, acted, action_failed, refused_guard, verified, verify_failed) and the evidence (the action''s answer, then the verification''s). A run is verified only on a later controller run than its action. Never read by the consumer API.';
create index if not exists ops_remedy_runs_issue_idx on pipeline.ops_remedy_runs (issue_id, started_at desc);
create index if not exists ops_remedy_runs_open_idx on pipeline.ops_remedy_runs (result) where result in ('running', 'acted');
alter table pipeline.ops_remedy_runs enable row level security;
revoke all on pipeline.ops_remedy_runs from public, anon, authenticated;
revoke all on sequence pipeline.ops_remedy_runs_id_seq from public, anon, authenticated;

create table if not exists pipeline.ops_outcome_codes (
  code text primary key,
  title text not null,
  counts_as_movement boolean not null default false
);
comment on table pipeline.ops_outcome_codes is 'CF-247 P0 autonomous operations (mandate §7): the explicit outcome of a job or task, beside its state (pipeline.admin_jobs.outcome). Only succeeded_with_result counts as data movement; a cancellation is never read as success or as not needed. Never read by the consumer API.';
alter table pipeline.ops_outcome_codes enable row level security;
revoke all on pipeline.ops_outcome_codes from public, anon, authenticated;
insert into pipeline.ops_outcome_codes(code, title, counts_as_movement) values
 ('succeeded_with_result', 'Succeeded with a measurable result', true),
 ('succeeded_no_movement', 'Succeeded without data movement', false),
 ('not_needed', 'Not needed', false),
 ('deferred_dependency', 'Deferred for a dependency', false),
 ('blocked_policy', 'Blocked by policy', false),
 ('blocked_evidence', 'Blocked by evidence', false),
 ('failed_retryable', 'Failed and retryable', false),
 ('failed_remediation', 'Failed and requiring remediation', false)
on conflict (code) do nothing;

-- the job outcome beside the job state (backwards compatible: nullable, the state check is unchanged, nothing is rewritten)
alter table pipeline.admin_jobs add column if not exists outcome text references pipeline.ops_outcome_codes(code);
alter table pipeline.admin_jobs add column if not exists outcome_detail jsonb;
comment on column pipeline.admin_jobs.outcome is 'CF-247 P0 (mandate §7): the explicit outcome (pipeline.ops_outcome_codes), set through security.job_outcome_set_v1. Null for history recorded before it existed.';

-- the controller's columns on the existing queue
alter table pipeline.integration_issues add column if not exists correlation_key text;
alter table pipeline.integration_issues add column if not exists diagnosis jsonb;
alter table pipeline.integration_issues add column if not exists remedy_code text;
alter table pipeline.integration_issues add column if not exists remedy_attempts int not null default 0;
alter table pipeline.integration_issues add column if not exists next_action_at timestamptz;
comment on column pipeline.integration_issues.diagnosis is 'CF-247 P0 (mandate §3): {root_cause, confidence 0..1, evidence[], method, at}, written by the controller''s classifier (security.ops_diagnose_v1).';
comment on column pipeline.integration_issues.correlation_key is 'CF-247 P0 (mandate §3): issues that share an upstream cause share this key (security.ops_correlation_key_v1); one open issue per key owns its remedies.';

create or replace function security.ops_root_cause_register_v1(p_code text, p_spec jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 P0 (mandate §3): add or replace a root cause by code (B, C, D, E, F and G register theirs in their own migrations). Spec keys mirror
-- the columns: class, title, description, detect. Refused while a remedy runs (a remedy never changes the taxonomy).
declare v_new boolean;
begin
  if security.ops_remedy_guard_active_v1() then raise exception 'ops guard: a remedy cannot change the root-cause register' using errcode = '42501'; end if;
  if coalesce(p_code, '') !~ '^[a-z][a-z0-9_]*$' then raise exception 'a root cause code is lower case letters, digits and underscores' using errcode = '22023'; end if;
  if p_spec is null or jsonb_typeof(p_spec) <> 'object' or coalesce(p_spec->>'class', '') not in ('transient', 'data', 'rule', 'policy', 'dependency', 'capacity') then
    raise exception 'root cause %: class must be transient, data, rule, policy, dependency or capacity', p_code using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_spec->>'title', ''))) < 3 then raise exception 'root cause %: give it a title', p_code using errcode = '22023'; end if;
  if p_spec ? 'detect' and jsonb_typeof(p_spec->'detect') <> 'object' then raise exception 'root cause %: detect is an object', p_code using errcode = '22023'; end if;
  v_new := not exists (select 1 from pipeline.ops_root_causes where code = p_code);
  insert into pipeline.ops_root_causes as r(code, class, title, description, detect)
  values (p_code, p_spec->>'class', btrim(p_spec->>'title'), p_spec->>'description', coalesce(p_spec->'detect', '{}'::jsonb))
  on conflict (code) do update set class = excluded.class, title = excluded.title, description = excluded.description, detect = excluded.detect;
  return jsonb_build_object('code', p_code, 'action', case when v_new then 'created' else 'replaced' end);
end $function$;
revoke all on function security.ops_root_cause_register_v1(text, jsonb) from public, anon, authenticated;

create or replace function security.ops_remedy_register_v1(p_code text, p_spec jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 P0 (mandate §3, §15): add or replace a remedy by code. Spec keys mirror the columns: title, treats (root-cause codes), authority
-- (auto, release, admin), action_fn and verify_fn (text such as 'security.x_v1(bigint)'), max_attempts_key, cooldown_key, active, notes.
-- Refused: a function that does not exist, or that is not (bigint) returning jsonb, or is not SQL or PL/pgSQL; an auto remedy without both an
-- action and a verification; a root cause that is not registered; a settings key that does not exist; a function whose text reaches the
-- authority boundary (the guard switch, trigger switches, the remedy or root-cause registers, settings ceilings); a call made by a remedy.
declare v_auth text := p_spec->>'authority'; v_treats text[]; v_fn regprocedure; v_vf regprocedure; v_tmp regprocedure; v_k text; v_new boolean; v_bad text;
begin
  if security.ops_remedy_guard_active_v1() then raise exception 'ops guard: a remedy cannot change the remedy register' using errcode = '42501'; end if;
  if coalesce(p_code, '') !~ '^[a-z][a-z0-9_]*$' then raise exception 'a remedy code is lower case letters, digits and underscores' using errcode = '22023'; end if;
  if p_spec is null or jsonb_typeof(p_spec) <> 'object' then raise exception 'remedy %: give a spec object', p_code using errcode = '22023'; end if;
  if coalesce(v_auth, '') not in ('auto', 'release', 'admin') then raise exception 'remedy %: authority must be auto, release or admin', p_code using errcode = '22023'; end if;
  if length(btrim(coalesce(p_spec->>'title', ''))) < 3 then raise exception 'remedy %: give it a title', p_code using errcode = '22023'; end if;
  v_treats := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_spec->'treats', '[]'::jsonb)) x), '{}');
  if cardinality(v_treats) = 0 then raise exception 'remedy %: name the root causes it treats', p_code using errcode = '22023'; end if;
  select string_agg(t, ', ') into v_bad from unnest(v_treats) t where not exists (select 1 from pipeline.ops_root_causes r where r.code = t);
  if v_bad is not null then raise exception 'remedy %: unknown root cause(s) %', p_code, v_bad using errcode = '22023'; end if;
  foreach v_k in array array['action_fn', 'verify_fn'] loop
    if nullif(p_spec->>v_k, '') is not null then
      v_tmp := to_regprocedure(p_spec->>v_k);
      if v_tmp is null then raise exception 'remedy %: % % does not exist', p_code, v_k, p_spec->>v_k using errcode = '42883'; end if;
      if not exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                      where p.oid = v_tmp and p.pronargs = 1 and p.proargtypes[0] = 'bigint'::regtype and p.prorettype = 'jsonb'::regtype and l.lanname in ('sql', 'plpgsql')) then
        raise exception 'remedy %: % must be an SQL or PL/pgSQL function (p_issue bigint) returning jsonb', p_code, v_k using errcode = '22023';
      end if;
      if pg_get_functiondef(v_tmp) ~* '(set_config|cf247\.ops_remedy|session_replication_role|disable\s+trigger|ops_remedies|ops_root_causes|ops_remedy_register|ops_root_cause_register|max_value|min_value)' then
        raise exception 'remedy %: % reaches the authority boundary (guard switch, triggers, registers or settings ceilings); that is a release change, not a remedy', p_code, v_k using errcode = '42501';
      end if;
      if v_k = 'action_fn' then v_fn := v_tmp; else v_vf := v_tmp; end if;
    end if;
  end loop;
  if v_auth = 'auto' and (v_fn is null or v_vf is null) then raise exception 'remedy %: an auto remedy needs an action and a verification', p_code using errcode = '22023'; end if;
  foreach v_k in array array['max_attempts_key', 'cooldown_key'] loop
    if nullif(p_spec->>v_k, '') is not null and not exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_spec->>v_k) then
      raise exception 'remedy %: setting % (%) does not exist', p_code, p_spec->>v_k, v_k using errcode = '22023';
    end if;
  end loop;
  v_new := not exists (select 1 from pipeline.ops_remedies where code = p_code);
  insert into pipeline.ops_remedies as r(code, title, treats, authority, action_fn, verify_fn, max_attempts_key, cooldown_key, active, notes)
  values (p_code, btrim(p_spec->>'title'), v_treats, v_auth, v_fn, v_vf, nullif(p_spec->>'max_attempts_key', ''), nullif(p_spec->>'cooldown_key', ''),
          coalesce((p_spec->>'active')::boolean, true), p_spec->>'notes')
  on conflict (code) do update set title = excluded.title, treats = excluded.treats, authority = excluded.authority, action_fn = excluded.action_fn,
     verify_fn = excluded.verify_fn, max_attempts_key = excluded.max_attempts_key, cooldown_key = excluded.cooldown_key, active = excluded.active, notes = excluded.notes;
  return jsonb_build_object('code', p_code, 'action', case when v_new then 'created' else 'replaced' end, 'authority', v_auth);
end $function$;
revoke all on function security.ops_remedy_register_v1(text, jsonb) from public, anon, authenticated;

create or replace function security.job_outcome_set_v1(p_job uuid, p_outcome text, p_detail jsonb) returns void
language plpgsql security definer set search_path to '' as $function$
-- CF-247 P0 (mandate §7): record a job's explicit outcome beside its state. The state is not changed; history is never rewritten here (a
-- reconciled outcome for an old job is recorded with its basis in p_detail).
begin
  if not exists (select 1 from pipeline.ops_outcome_codes c where c.code = p_outcome) then
    raise exception 'unknown job outcome % (pipeline.ops_outcome_codes)', p_outcome using errcode = '22023';
  end if;
  update pipeline.admin_jobs set outcome = p_outcome, outcome_detail = coalesce(p_detail, '{}'::jsonb) where id = p_job;
  if not found then raise exception 'no job %', p_job using errcode = 'P0002'; end if;
end $function$;
revoke all on function security.job_outcome_set_v1(uuid, text, jsonb) from public, anon, authenticated;
-- <<< contract ----------------------------------------------------------------------------------------------------------------------------
