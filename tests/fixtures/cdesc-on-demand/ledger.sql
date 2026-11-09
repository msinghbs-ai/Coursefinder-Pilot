-- The machine-admission ledger exactly as agent D1's migration 20261110060000_cf247_cdesc_machine_policy_shadow.sql (PR #977) defines it (table, comment-free), copied 10 Nov 2026.
-- Scenarios create it (this file) and drop it, so the dependency on the real column names is tested, not assumed.
create table pipeline.course_description_machine_admissions (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id),
  provider_id uuid not null references catalogue.providers(id),
  review_item_id uuid references pipeline.layer4_review_items(id),
  reading_item_id bigint,
  rule text not null,
  outcome text not null check (outcome in ('admitted', 'declined')),
  reason_code text,
  reason text,
  next_action text,
  transient boolean not null default false,
  retry_after timestamptz,
  policy_stamp text,
  before_description text,
  after_description text,
  text_md5 text,
  evidence_id uuid references pipeline.evidence_artifacts(id),
  content_hash text,
  source_url text,
  storage_path text,
  model text,
  prompt_version text,
  worker text,
  checks jsonb not null default '{}'::jsonb,
  recovery text,
  consumer_check text,
  consumer_checked_at timestamptz,
  actor uuid not null,
  created_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  withdrawn_by uuid,
  withdrawn_reason text
);
create unique index course_description_machine_admissions_live_uq on pipeline.course_description_machine_admissions (course_id) where outcome = 'admitted' and withdrawn_at is null;
create unique index course_description_machine_admissions_declined_uq on pipeline.course_description_machine_admissions (review_item_id) where outcome = 'declined';
