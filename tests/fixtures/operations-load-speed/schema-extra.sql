-- Guards: CF-247 Operations load speed (Platform Admin P1, 10 Nov 2026): the production shapes the migration 20261110020000 reads or edits beyond the lane-funnels fixture schema. STUB marks a table
-- reduced to the columns the edited functions read; the columns, names and types that matter (cron.job_run_details.job_pid, the evidence columns of the index) are production's.
alter table cron.job_run_details add column if not exists job_pid integer;  -- production column: the backend running the job
-- evidence (the index and its queue count)
create table if not exists pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), source_id uuid, evidence_type text, storage_path text, mime_type text, captured_at timestamptz default now());  -- STUB
create table if not exists pipeline.evidence_link_index_state (evidence_id uuid primary key, status text, indexed_at timestamptz);  -- STUB
-- the intake events and dates the repeat check and the recovery measurement read
alter table pipeline.course_intake_date_events
  add column if not exists intake_id uuid, add column if not exists provider_id uuid, add column if not exists course_id uuid, add column if not exists deterministic boolean default false,
  add column if not exists calendar_set text, add column if not exists calendar_evidence_id uuid, add column if not exists proposal_id uuid, add column if not exists periods jsonb,
  add column if not exists evidence_year integer, add column if not exists page_quote text, add column if not exists reader text, add column if not exists rule text,
  add column if not exists next_revisit_at timestamptz, add column if not exists before_value jsonb, add column if not exists after_value jsonb, add column if not exists start_precision text,
  add column if not exists publication_state text;
create table if not exists pipeline.course_intake_dates (id bigserial primary key, provider_id uuid, intake_id uuid, failure_class text, next_action text, deterministic boolean, reason text, next_revisit_at timestamptz,
  revisit_trigger text, outcome text, publication_state text);  -- STUB
create table if not exists pipeline.admin_control_events (id bigserial primary key, area text, action text, target text, detail jsonb, actor uuid, created_at timestamptz default now());  -- STUB
create table if not exists pipeline.integration_deploy_checks (id bigserial primary key, since timestamptz, result jsonb);  -- STUB
create table if not exists pipeline.calendar_refresh_requests (id bigserial primary key, provider_id uuid, url text, requested_at timestamptz default now(), reason text, status text, credit_estimate numeric, credits_used numeric,
  yield jsonb, next_year_starts jsonb);  -- STUB
create table if not exists pipeline.calendar_reread_state (id bigserial primary key, reader_version text, state text);  -- STUB
create function security.intake_ui_scopes_v1() returns jsonb language sql stable as $$ select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name)), '[]'::jsonb) from (values ('00000000-0000-0000-0000-0000000000a1'::uuid, 'Fixture University')) v(id, name) $$;  -- STUB
-- the inbox read admin_layer23 builds its temporary table from (only its existence matters to the migration's guard)
create function security.layer4_inbox_items_v2(p_provider_id uuid default null, p_kind text default null, p_keys text[] default null, p_detail boolean default true)
  returns table(kind text, ref text, provider_id uuid, subject text, why text, suggestion text, created_at timestamptz, detail jsonb) language sql stable as $$ select null::text, null::text, null::uuid, null::text, null::text, null::text, null::timestamptz, null::jsonb where false $$;  -- STUB
create function security.layer4_inbox_items_v1() returns table(kind text, ref text, provider_id uuid, subject text, why text, suggestion text, created_at timestamptz, detail jsonb) language sql stable as $$ select * from security.layer4_inbox_items_v2(null, null, null, true) $$;  -- STUB
