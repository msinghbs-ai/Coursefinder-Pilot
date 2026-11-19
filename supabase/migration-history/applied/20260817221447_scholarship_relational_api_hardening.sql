create table if not exists scholarship.identifiers (
  id uuid primary key default gen_random_uuid(),
  scholarship_id uuid not null references scholarship.scholarships(id) on delete cascade,
  scheme text not null,
  identifier_value text not null,
  source_id uuid references pipeline.sources(id) on delete set null,
  evidence_id uuid references pipeline.evidence_artifacts(id) on delete set null,
  is_primary boolean not null default false,
  status text not null default 'active' check (status in ('active','inactive','superseded','unverified')),
  valid_from timestamptz,
  valid_to timestamptz,
  created_at timestamptz not null default now(),
  unique (scholarship_id, scheme, identifier_value),
  unique (source_id, scheme, identifier_value)
);

create table if not exists scholarship.offering_cycles (
  id uuid primary key default gen_random_uuid(),
  scholarship_id uuid not null references scholarship.scholarships(id) on delete cascade,
  cycle_code text not null,
  academic_year integer,
  intake_label text,
  valid_from date,
  valid_to date,
  status text not null default 'active' check (status in ('planned','active','closed','archived','cancelled')),
  source_id uuid references pipeline.sources(id) on delete set null,
  evidence_id uuid references pipeline.evidence_artifacts(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (scholarship_id, cycle_code),
  check (valid_to is null or valid_from is null or valid_to >= valid_from)
);

create table if not exists scholarship.application_windows (
  id uuid primary key default gen_random_uuid(),
  scholarship_id uuid not null references scholarship.scholarships(id) on delete cascade,
  cycle_id uuid references scholarship.offering_cycles(id) on delete cascade,
  round_code text,
  label text,
  opens_at timestamptz,
  closes_at timestamptz,
  application_method text,
  application_url text,
  status text not null default 'active' check (status in ('planned','active','closed','cancelled','unknown')),
  source_id uuid references pipeline.sources(id) on delete set null,
  evidence_id uuid references pipeline.evidence_artifacts(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (closes_at is null or opens_at is null or closes_at >= opens_at)
);

create table if not exists scholarship.criterion_groups (
  id uuid primary key default gen_random_uuid(),
  scholarship_id uuid not null references scholarship.scholarships(id) on delete cascade,
  cycle_id uuid references scholarship.offering_cycles(id) on delete cascade,
  parent_group_id uuid references scholarship.criterion_groups(id) on delete cascade,
  group_code text,
  label text,
  conjunction text not null default 'all' check (conjunction in ('all','any')),
  is_mandatory boolean not null default true,
  display_order integer not null default 0,
  source_id uuid references pipeline.sources(id) on delete set null,
  evidence_id uuid references pipeline.evidence_artifacts(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (scholarship_id, group_code)
);

alter table scholarship.scopes add column if not exists cycle_id uuid references scholarship.offering_cycles(id) on delete cascade;
alter table scholarship.criteria add column if not exists cycle_id uuid references scholarship.offering_cycles(id) on delete cascade;
alter table scholarship.criteria add column if not exists criterion_group_id uuid references scholarship.criterion_groups(id) on delete set null;
alter table scholarship.award_tiers add column if not exists cycle_id uuid references scholarship.offering_cycles(id) on delete cascade;
alter table scholarship.award_tiers add column if not exists source_id uuid references pipeline.sources(id) on delete set null;
alter table scholarship.award_tiers add column if not exists evidence_id uuid references pipeline.evidence_artifacts(id) on delete set null;
alter table scholarship.coverage add column if not exists cycle_id uuid references scholarship.offering_cycles(id) on delete cascade;

alter table scholarship.scopes drop constraint if exists scopes_target_shape_check;
alter table scholarship.scopes add constraint scopes_target_shape_check check (
  (scope_type = 'global' and provider_id is null and course_id is null and course_collection_id is null and study_level_id is null and field_id is null and country_id is null and campus_id is null)
  or (scope_type = 'provider' and provider_id is not null and course_id is null and course_collection_id is null and study_level_id is null and field_id is null and country_id is null and campus_id is null)
  or (scope_type = 'course' and provider_id is null and course_id is not null and course_collection_id is null and study_level_id is null and field_id is null and country_id is null and campus_id is null)
  or (scope_type = 'course_collection' and provider_id is null and course_id is null and course_collection_id is not null and study_level_id is null and field_id is null and country_id is null and campus_id is null)
  or (scope_type = 'study_level' and provider_id is null and course_id is null and course_collection_id is null and study_level_id is not null and field_id is null and country_id is null and campus_id is null)
  or (scope_type = 'field_of_study' and provider_id is null and course_id is null and course_collection_id is null and study_level_id is null and field_id is not null and country_id is null and campus_id is null)
  or (scope_type = 'country' and provider_id is null and course_id is null and course_collection_id is null and study_level_id is null and field_id is null and country_id is not null and campus_id is null)
  or (scope_type = 'campus' and provider_id is null and course_id is null and course_collection_id is null and study_level_id is null and field_id is null and country_id is null and campus_id is not null)
);

create index if not exists scholarship_identifiers_scholarship_idx on scholarship.identifiers(scholarship_id);
create index if not exists scholarship_identifiers_source_idx on scholarship.identifiers(source_id);
create index if not exists scholarship_identifiers_evidence_idx on scholarship.identifiers(evidence_id);
create index if not exists scholarship_cycles_scholarship_idx on scholarship.offering_cycles(scholarship_id, status, academic_year);
create index if not exists scholarship_cycles_source_idx on scholarship.offering_cycles(source_id);
create index if not exists scholarship_cycles_evidence_idx on scholarship.offering_cycles(evidence_id);
create index if not exists scholarship_windows_scholarship_idx on scholarship.application_windows(scholarship_id, status, closes_at);
create index if not exists scholarship_windows_cycle_idx on scholarship.application_windows(cycle_id);
create index if not exists scholarship_windows_source_idx on scholarship.application_windows(source_id);
create index if not exists scholarship_windows_evidence_idx on scholarship.application_windows(evidence_id);
create index if not exists scholarship_criterion_groups_scholarship_idx on scholarship.criterion_groups(scholarship_id, display_order);
create index if not exists scholarship_criterion_groups_cycle_idx on scholarship.criterion_groups(cycle_id);
create index if not exists scholarship_criterion_groups_parent_idx on scholarship.criterion_groups(parent_group_id);
create index if not exists scholarship_criterion_groups_source_idx on scholarship.criterion_groups(source_id);
create index if not exists scholarship_criterion_groups_evidence_idx on scholarship.criterion_groups(evidence_id);
create index if not exists scholarship_scopes_cycle_idx on scholarship.scopes(cycle_id);
create index if not exists scholarship_criteria_cycle_idx on scholarship.criteria(cycle_id);
create index if not exists scholarship_criteria_group_idx on scholarship.criteria(criterion_group_id);
create index if not exists scholarship_award_tiers_cycle_idx on scholarship.award_tiers(cycle_id);
create index if not exists scholarship_award_tiers_source_idx on scholarship.award_tiers(source_id);
create index if not exists scholarship_award_tiers_evidence_idx on scholarship.award_tiers(evidence_id);
create index if not exists scholarship_coverage_cycle_idx on scholarship.coverage(cycle_id);

alter table scholarship.identifiers enable row level security;
alter table scholarship.offering_cycles enable row level security;
alter table scholarship.application_windows enable row level security;
alter table scholarship.criterion_groups enable row level security;

revoke all on scholarship.identifiers, scholarship.offering_cycles, scholarship.application_windows, scholarship.criterion_groups from anon, authenticated;
grant select, insert, update, delete on scholarship.identifiers, scholarship.offering_cycles, scholarship.application_windows, scholarship.criterion_groups to service_role;
