-- Live shapes for the verification-measures fixtures (CF-247, 4 Nov 2026), read from production 11:08-11:16 AEDT (information_schema and the
-- migrations that created them: 20261104120000 readiness, 20261104450000 interventions). Only the tables and helpers the change reads, and the
-- helpers the classifier calls (security.scholarship_coverage_items_v1 and security.work_item_report_v1 are stubs the cases control). Never a Supabase project.
set check_function_bodies = off;
create table if not exists pipeline.coverage_provider_reconciliation (provider_id uuid not null, domain text not null, disposition text not null, issue_fingerprint text,
  primary key (provider_id, domain));
create table if not exists pipeline.layer4_intervention_classes (code text primary key);
insert into pipeline.layer4_intervention_classes values ('official_source') on conflict do nothing;
create table if not exists pipeline.layer4_interventions (id bigserial primary key, lane text not null, entity text not null, missing_fact text not null references pipeline.layer4_intervention_classes(code),
  provider_id uuid, course_id uuid, field text, subject text not null default 's', status text not null default 'awaiting_input', fingerprint text not null default 'f',
  verified_at timestamptz, last_seen_at timestamptz not null default now(), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (lane, entity, missing_fact));
create table if not exists pipeline.layer4_intervention_events (id bigserial primary key, intervention_id bigint not null references pipeline.layer4_interventions(id), at timestamptz not null default now(),
  actor uuid, actor_label text not null default 'system', action text not null, payload jsonb not null default '{}', result jsonb not null default '{}', status_before text, status_after text);
create table if not exists pipeline.layer4_item_readiness (item_id uuid primary key, entity_type text, entity_id uuid, field_code text not null, item_created_at timestamptz not null,
  item_status text, readiness text not null, classified_at timestamptz not null default now());
create table if not exists pipeline.layer4_readiness_runs (id bigserial primary key, at timestamptz not null default now(), ms int, result jsonb not null);
create table if not exists pipeline.layer4_supersessions (id bigserial primary key, item_id uuid not null, field_code text not null, entity_type text, entity_id uuid, reason text,
  at timestamptz not null default now(), reversed_at timestamptz);
create table if not exists pipeline.field_enrich_items (id bigserial primary key, provider_id uuid, course_id uuid, state text, leased_until timestamptz);
alter table pipeline.field_enrich_items add column if not exists field text;
alter table pipeline.field_enrich_items add column if not exists reason text;
alter table pipeline.scholarship_ai_queue add column if not exists skip_reason text;
alter table pipeline.scholarship_ai_reviews alter column status set default 'pending';

-- the classifier's callees, controlled by the cases
create table if not exists fx.sch_items (provider_id uuid, item_key text, state text, reason text, evidence jsonb, recovery text);
create table if not exists fx.report_fail (code text primary key);
create or replace function security.scholarship_coverage_items_v1(p_providers uuid[]) returns table(provider_id uuid, item_key text, state text, reason text, evidence jsonb, recovery text)
language sql stable set search_path to '' as $$ select * from fx.sch_items where provider_id = any (p_providers) $$;
create or replace function security.work_item_report_v1(p_lane text, p_entity text, p_kind text, p_event text, p jsonb) returns jsonb
language plpgsql set search_path to '' as $$
begin
  if exists (select 1 from fx.report_fail f where p_kind = 'state:' || f.code) then raise exception 'work item report refused for %', p_kind; end if;
  return '{}'::jsonb;
end $$;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values ('pipeline', 'sch_cov.classify_on', 'x', 'number', '1'),
  ('pipeline', 'layer4.readiness_on', 'x', 'number', '1'), ('pipeline', 'har.generate_aer_on', 'x', 'number', '1'), ('pipeline', 'har.generate_sch_on', 'x', 'number', '1')
on conflict do nothing;
