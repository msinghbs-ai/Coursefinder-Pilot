-- Guards: Platform Admin decision 5 Nov 2026 16:36 §8 (production-representative constraints) and decision 19:14 §8: the production shape of every
-- table the Automation Progress read layer and its observer read or write, read from production fxcwkweaxjtknorudmwp on 5 Nov 2026 19:20-19:30 AEDT
-- (pg_attribute, pg_constraint, pg_index, pg_trigger, pg_policy, role_table_grants; read only). No production rows are copied.
-- Reduced, and recorded as such in docs/intake-automation-progress.md: catalogue.providers, catalogue.courses, catalogue.course_intakes, ref.countries and
-- ref.provider_types keep only the columns read here (with their live types, NOT NULL, defaults, keys and foreign keys among them); pim.entity_registry,
-- pipeline.platform_toolsets, pipeline.scholarship_layer_settings, pipeline.enrichment_flags and pipeline.provider_policy_proposals keep only the
-- columns a live function here reads. pg_cron and Supabase auth are stubs with the same signatures.
set client_min_messages = warning;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin; end if;
end $$;
create schema if not exists auth; create schema if not exists extensions; create schema if not exists security; create schema if not exists pipeline;
create schema if not exists catalogue; create schema if not exists ref; create schema if not exists cron; create schema if not exists pim; create schema if not exists search;
-- live schema privileges: authenticated has USAGE on security only
revoke all on schema pipeline, catalogue, cron from public; grant usage on schema security to authenticated; grant usage on schema public to authenticated;

-- Supabase auth (stub, same contract as auth.uid())
create table if not exists auth.users (id uuid primary key);
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $$;
create or replace function extensions.gen_random_uuid() returns uuid language sql volatile as $$ select pg_catalog.gen_random_uuid() $$;

-- pg_cron (stub tables with the live columns, keys, RLS policy and the alter_job/schedule signatures)
create sequence if not exists cron.jobid_seq; create sequence if not exists cron.runid_seq;
create table if not exists cron.job (
  jobid bigint not null default nextval('cron.jobid_seq'::regclass),
  schedule text not null,
  command text not null,
  nodename text not null default 'localhost'::text,
  nodeport integer not null default coalesce(inet_server_port(), 5432),  -- live: inet_server_port(); null over a local socket in the fixture
  database text not null default current_database(),
  username text not null default CURRENT_USER,
  active boolean not null default true,
  jobname text,
  constraint job_pkey PRIMARY KEY (jobid),
  constraint jobname_username_uniq UNIQUE (jobname, username));
alter table cron.job enable row level security;
drop policy if exists cron_job_policy on cron.job; create policy cron_job_policy on cron.job using ((username = CURRENT_USER));
create table if not exists cron.job_run_details (
  jobid bigint,
  runid bigint not null default nextval('cron.runid_seq'::regclass),
  job_pid integer,
  database text,
  username text,
  command text,
  status text,
  return_message text,
  start_time timestamp with time zone,
  end_time timestamp with time zone,
  constraint job_run_details_pkey PRIMARY KEY (runid));
alter table cron.job_run_details enable row level security;
drop policy if exists cron_job_run_details_policy on cron.job_run_details; create policy cron_job_run_details_policy on cron.job_run_details using ((username = CURRENT_USER));
create or replace function cron.alter_job(job_id bigint, schedule text default null, command text default null, database text default null, username text default null, active boolean default null)
returns void language sql as $$
  update cron.job j set schedule = coalesce(alter_job.schedule, j.schedule), command = coalesce(alter_job.command, j.command), active = coalesce(alter_job.active, j.active) where j.jobid = job_id $$;
create or replace function cron.schedule(job_name text, schedule text, command text) returns bigint language plpgsql as $$
declare v bigint;
begin
  update cron.job j set schedule = $2, command = $3 where j.jobname = $1 returning j.jobid into v;
  if v is null then insert into cron.job(jobname, schedule, command) values ($1, $2, $3) returning jobid into v; end if;
  return v;
end $$;

-- reduced reference and catalogue shapes (live types, keys and foreign keys among the kept columns)
create table if not exists pim.entity_registry (id uuid primary key);
create table if not exists ref.countries (
  id uuid not null default extensions.gen_random_uuid(),
  iso_alpha2 character(2) not null,
  constraint countries_iso_alpha2_key UNIQUE (iso_alpha2),
  constraint countries_pkey PRIMARY KEY (id));
create table if not exists ref.provider_types (
  id uuid not null default extensions.gen_random_uuid(),
  code text not null,
  constraint provider_types_code_key UNIQUE (code),
  constraint provider_types_pkey PRIMARY KEY (id));
create table if not exists catalogue.providers (
  id uuid not null,
  canonical_name text not null,
  display_name text,
  country_id uuid not null,
  provider_type_id uuid,
  lifecycle_status text not null default 'active'::text,
  constraint providers_country_id_fkey FOREIGN KEY (country_id) REFERENCES ref.countries(id),
  constraint providers_id_fkey FOREIGN KEY (id) REFERENCES pim.entity_registry(id) ON DELETE CASCADE,
  constraint providers_pkey PRIMARY KEY (id),
  constraint providers_provider_type_id_fkey FOREIGN KEY (provider_type_id) REFERENCES ref.provider_types(id));
create table if not exists catalogue.courses (
  id uuid not null,
  provider_id uuid not null,
  canonical_title text not null,
  display_title text,
  course_url text,
  lifecycle_status text not null default 'active'::text,
  constraint courses_id_fkey FOREIGN KEY (id) REFERENCES pim.entity_registry(id) ON DELETE CASCADE,
  constraint courses_pkey PRIMARY KEY (id),
  constraint courses_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES catalogue.providers(id) ON DELETE CASCADE);
create table if not exists catalogue.course_intakes (
  id uuid not null default extensions.gen_random_uuid(),
  course_id uuid not null,
  intake_year integer,
  intake_label text not null,
  start_date date,
  application_deadline date,
  status text not null default 'active'::text,
  constraint course_intakes_course_id_fkey FOREIGN KEY (course_id) REFERENCES catalogue.courses(id) ON DELETE CASCADE,
  constraint course_intakes_pkey PRIMARY KEY (id));
create index if not exists course_intakes_course_idx on catalogue.course_intakes (course_id, intake_year, status);
alter table ref.countries enable row level security; alter table ref.provider_types enable row level security;
alter table catalogue.providers enable row level security; alter table catalogue.courses enable row level security; alter table catalogue.course_intakes enable row level security;

-- security roles (live)
create table if not exists security.roles (
  code text not null,
  name text not null,
  rank smallint not null,
  description text,
  status text not null default 'active'::text,
  constraint roles_pkey PRIMARY KEY (code),
  constraint roles_rank_key UNIQUE (rank));
create table if not exists security.user_roles (
  user_id uuid not null,
  role_code text not null,
  granted_at timestamp with time zone not null default now(),
  granted_by uuid,
  expires_at timestamp with time zone,
  constraint user_roles_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES auth.users(id),
  constraint user_roles_role_code_fkey FOREIGN KEY (role_code) REFERENCES security.roles(code),
  constraint user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  constraint user_roles_pkey PRIMARY KEY (user_id, role_code));
alter table security.roles enable row level security; alter table security.user_roles enable row level security;
revoke all on security.roles, security.user_roles from authenticated, anon;

-- pipeline (live shapes)
create table if not exists pipeline.platform_toolsets (key text primary key);
create table if not exists pipeline.platform_toolset_settings (
  toolset_key text not null,
  key text not null,
  label text not null,
  help text not null default ''::text,
  kind text not null,
  value jsonb not null,
  min_value numeric,
  max_value numeric,
  unit text,
  sort integer not null default 100,
  reason text,
  updated_by uuid,
  updated_at timestamp with time zone not null default now(),
  section text not null default 'Notices'::text,
  used_by text,
  constraint platform_toolset_settings_kind_check CHECK ((kind = ANY (ARRAY['number'::text, 'text'::text, 'boolean'::text, 'list'::text]))),
  constraint platform_toolset_settings_toolset_key_fkey FOREIGN KEY (toolset_key) REFERENCES pipeline.platform_toolsets(key),
  constraint platform_toolset_settings_pkey PRIMARY KEY (toolset_key, key));
create table if not exists pipeline.scholarship_layer_settings (key text primary key, value jsonb);
create table if not exists pipeline.automation_catalogue (
  jobname text not null,
  area text not null,
  sort integer not null default 100,
  label text not null,
  description text not null,
  control_rank integer not null default 5,
  batch_editable boolean not null default false,
  layer23_stage text,
  constraint automation_catalogue_pkey PRIMARY KEY (jobname));
create table if not exists pipeline.admin_control_events (
  id bigint generated always as identity not null,  -- live attidentity = 'a'
  area text not null,
  action text not null,
  target text,
  detail jsonb not null default '{}'::jsonb,
  actor uuid,
  created_at timestamp with time zone not null default now(),
  constraint admin_control_events_pkey PRIMARY KEY (id));
create table if not exists pipeline.component_register (
  kind text not null,
  name text not null,
  layer text not null,
  area text,
  purpose text,
  status text not null default 'active'::text,
  replaces text[] not null default '{}'::text[],
  replaced_by text,
  introduced_in text,
  retire_after date,
  last_used_at timestamp with time zone,
  usage jsonb not null default '{}'::jsonb,
  size_bytes bigint,
  note text,
  registered_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint component_register_kind_check CHECK ((kind = ANY (ARRAY['job'::text, 'table'::text, 'view'::text, 'edge_function'::text, 'screen'::text, 'function'::text]))),
  constraint component_register_status_check CHECK ((status = ANY (ARRAY['active'::text, 'retiring'::text, 'retired'::text]))),
  constraint component_register_pkey PRIMARY KEY (kind, name));
create table if not exists pipeline.enrichment_flags (id bigserial primary key, entity text not null, entity_key text not null, field text not null default '',
  reason_code text not null, provider_id uuid, state text default 'raised', cleared_at timestamptz);
create table if not exists pipeline.provider_policy_proposals (id uuid primary key, parser text);
create table if not exists pipeline.course_intake_dates (
  intake_id uuid not null,
  course_id uuid not null,
  provider_id uuid not null,
  proposal_id uuid,
  outcome text not null,
  reason text,
  periods text[],
  start_precision text,
  deadline_kind text,
  deadline_text text,
  start_quote text,
  deadline_quote text,
  before_value jsonb,
  after_value jsonb,
  applied_at timestamp with time zone not null default now(),
  page_quote text,
  calendar_evidence_id uuid,
  calendar_url text,
  rule text,
  calendar_set text,
  inputs_fp text,
  next_action text,
  next_revisit_at timestamp with time zone,
  failure_class text,
  deterministic boolean,
  revisit_trigger text,
  evidence_year integer,
  reader text,
  related_case text,
  publication_state text,
  publication_checked_at timestamp with time zone,
  publication_attempts integer not null default 0,
  constraint course_intake_dates_deadline_kind_check CHECK ((deadline_kind = ANY (ARRAY['date'::text, 'rolling'::text, 'not_stated'::text]))),
  constraint course_intake_dates_outcome_check CHECK ((outcome = ANY (ARRAY['filled'::text, 'nothing_new'::text, 'skipped'::text]))),
  constraint course_intake_dates_start_precision_check CHECK ((start_precision = ANY (ARRAY['day'::text, 'year'::text, 'month'::text]))),
  constraint course_intake_dates_intake_id_fkey FOREIGN KEY (intake_id) REFERENCES catalogue.course_intakes(id),
  constraint course_intake_dates_pkey PRIMARY KEY (intake_id));
create index if not exists course_intake_dates_publication_idx on pipeline.course_intake_dates USING btree (publication_checked_at) WHERE (outcome = 'filled'::text);
create index if not exists course_intake_dates_course_idx on pipeline.course_intake_dates USING btree (course_id);
create index if not exists course_intake_dates_provider_idx on pipeline.course_intake_dates USING btree (provider_id, next_action);
create table if not exists pipeline.course_intake_date_events (
  id bigserial not null,
  intake_id uuid not null,
  course_id uuid not null,
  provider_id uuid not null,
  run_at timestamp with time zone not null default now(),
  rule text,
  outcome text not null,
  reason text,
  next_action text,
  next_revisit_at timestamp with time zone,
  calendar_set text,
  proposal_id uuid,
  periods text[],
  start_precision text,
  deadline_kind text,
  before_value jsonb,
  after_value jsonb,
  page_quote text,
  start_quote text,
  deadline_quote text,
  calendar_url text,
  calendar_evidence_id uuid,
  bounded boolean not null default false,
  failure_class text,
  deterministic boolean,
  revisit_trigger text,
  evidence_year integer,
  reader text,
  related_case text,
  publication_state text,
  publication_checked_at timestamp with time zone,
  constraint course_intake_date_events_pkey PRIMARY KEY (id));
create index if not exists course_intake_date_events_intake_idx on pipeline.course_intake_date_events USING btree (intake_id, run_at DESC);
create index if not exists course_intake_date_events_provider_idx on pipeline.course_intake_date_events USING btree (provider_id, run_at DESC);
create table if not exists pipeline.process_results (
  id bigserial not null,
  process_key text not null,
  scope_key text not null,
  measured_at timestamp with time zone not null default now(),
  summary jsonb not null,
  markdown text,
  measured_by text,
  constraint process_results_pkey PRIMARY KEY (id));
create index if not exists process_results_key_idx on pipeline.process_results USING btree (process_key, scope_key, measured_at DESC);
create table if not exists pipeline.integration_issues (
  id bigserial not null,
  issue_ref text generated always as (('IQ-'::text || lpad((id)::text, 5, '0'::text))) stored,  -- live attgenerated = 's'
  fingerprint text not null,
  title text not null,
  layer text not null,
  subsystem text,
  provider_ids uuid[] not null default '{}'::uuid[],
  course_ids uuid[] not null default '{}'::uuid[],
  country_codes text[] not null default '{}'::text[],
  entities_truncated boolean not null default false,
  detected_at timestamp with time zone not null default now(),
  failure text not null,
  expected text not null,
  detection_source text not null,
  validation_layer text not null default 'manual'::text,
  evidence jsonb not null default '{}'::jsonb,
  evidence_refs text[] not null default '{}'::text[],
  root_cause_class text not null default 'unclassified'::text,
  severity text not null,
  impact text,
  workstream text not null,
  blocked_by bigint[] not null default '{}'::bigint[],
  depends_on text[] not null default '{}'::text[],
  fix_commit text,
  fix_migration text,
  deployed_version text,
  verification_outcome text,
  verification_evidence jsonb,
  verified_at timestamp with time zone,
  verified_by text,
  retry_count integer not null default 0,
  last_observed_at timestamp with time zone not null default now(),
  condition_cleared_at timestamp with time zone,
  status text not null default 'detected'::text,
  assignee text,
  regression_count integer not null default 0,
  reopened_at timestamp with time zone,
  closed_at timestamp with time zone,
  aer_root_cause_ref text,
  alert_check_key text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  correlation_key text,
  diagnosis jsonb,
  remedy_code text,
  remedy_attempts integer not null default 0,
  next_action_at timestamp with time zone,
  ops_state text,
  superseded_by bigint,
  supersedes bigint[] not null default '{}'::bigint[],
  blocker jsonb,
  ops_plan jsonb,
  remediation_owner text,
  remediation_status text,
  remediation_checkpoint_at timestamp with time zone,
  remediation_evidence jsonb,
  severity_decided_at timestamp with time zone,
  severity_decided_by text,
  severity_decision jsonb,
  constraint integration_issues_fingerprint_check CHECK ((length(btrim(fingerprint)) > 0)),
  constraint integration_issues_ops_state_check CHECK (((ops_state IS NULL) OR (ops_state = ANY (ARRAY['diagnosed'::text, 'remedying'::text, 'verifying'::text, 'verified'::text, 'superseded'::text, 'needs_release'::text, 'needs_decision'::text])))),
  constraint integration_issues_remediation_status_check CHECK (((remediation_status IS NULL) OR (remediation_status = ANY (ARRAY['engineering_open'::text, 'fix_released'::text, 'awaiting_first_run'::text, 'verified'::text, 'returned'::text])))),
  constraint integration_issues_root_cause_class_check CHECK ((root_cause_class = ANY (ARRAY['unclassified'::text, 'code_defect'::text, 'data_drift'::text, 'job_config'::text, 'lifecycle_leak'::text, 'queue_or_lease'::text, 'missing_dependency'::text, 'governance_gap'::text, 'external'::text, 'budget'::text, 'human_decision'::text, 'deployment_drift'::text]))),
  constraint integration_issues_severity_check CHECK ((severity = ANY (ARRAY['P0'::text, 'P1'::text, 'P2'::text]))),
  constraint integration_issues_status_check CHECK ((status = ANY (ARRAY['detected'::text, 'triaged'::text, 'assigned'::text, 'in_progress'::text, 'code_ready'::text, 'integration_testing'::text, 'deployed'::text, 'production_verification'::text, 'closed'::text, 'reopened'::text]))),
  constraint integration_issues_validation_layer_check CHECK ((validation_layer = ANY (ARRAY['V1'::text, 'V2'::text, 'V3'::text, 'V4'::text, 'manual'::text]))),
  constraint integration_issues_verification_outcome_check CHECK ((verification_outcome = ANY (ARRAY['passed'::text, 'failed'::text, 'regressed'::text]))),
  constraint integration_issues_workstream_check CHECK ((workstream = ANY (ARRAY['A1'::text, 'A2'::text, 'A3'::text, 'A4'::text, 'A5'::text, 'A6'::text, 'A7'::text, 'A8'::text, 'A9'::text, 'A10'::text]))),
  constraint integration_issues_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES pipeline.integration_issues(id),
  constraint integration_issues_pkey PRIMARY KEY (id),
  constraint integration_issues_fingerprint_key UNIQUE (fingerprint));
create index if not exists integration_issues_open_idx on pipeline.integration_issues USING btree (status, severity) WHERE (status <> 'closed'::text);
create index if not exists integration_issues_observed_idx on pipeline.integration_issues USING btree (last_observed_at DESC);
create table if not exists pipeline.integration_issue_events (
  id bigserial not null,
  issue_id bigint not null,
  at timestamp with time zone not null default now(),
  kind text not null,
  from_status text,
  to_status text,
  actor text not null,
  note text,
  detail jsonb not null default '{}'::jsonb,
  constraint integration_issue_events_kind_check CHECK ((kind = ANY (ARRAY['detected'::text, 'observed'::text, 'not_observed'::text, 'observed_again'::text, 'escalated'::text, 'status'::text, 'reopened_regression'::text, 'closed'::text, 'updated'::text, 'alert_opened'::text, 'alert_resolved'::text]))),
  constraint integration_issue_events_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES pipeline.integration_issues(id),
  constraint integration_issue_events_pkey PRIMARY KEY (id));
do $$ declare t text; begin
  foreach t in array array['pipeline.platform_toolset_settings','pipeline.automation_catalogue','pipeline.admin_control_events','pipeline.component_register','pipeline.course_intake_dates',
                           'pipeline.course_intake_date_events','pipeline.process_results','pipeline.integration_issues','pipeline.integration_issue_events'] loop
    execute format('alter table %s enable row level security', t);
    execute format('revoke all on %s from authenticated, anon', t);  -- live: no grants to authenticated or anon, no policies
  end loop;
end $$;
