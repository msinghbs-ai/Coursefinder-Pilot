create table scholarship.scholarships (
  id uuid primary key references pim.entity_registry(id) on delete cascade,
  stable_key text not null unique,
  provider_id uuid references catalogue.providers(id) on delete set null,
  name text not null,
  scholarship_type text,
  description text,
  audience text,
  award_value_text text,
  application_required boolean,
  application_open_date date,
  application_close_date date,
  academic_year int,
  source_url text,
  lifecycle_status text not null default 'active',
  publication_status text not null default 'unpublished',
  source_id uuid,
  evidence_id uuid,
  confidence numeric(5,4),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index scholarships_provider_pub_idx on scholarship.scholarships(provider_id,publication_status);

create table scholarship.award_tiers (
  id uuid primary key default extensions.gen_random_uuid(),
  scholarship_id uuid not null references scholarship.scholarships(id) on delete cascade,
  tier_code text,
  label text,
  amount numeric(14,2),
  currency_code char(3) references ref.currencies(code),
  percentage numeric(6,3),
  basis text,
  maximum_amount numeric(14,2),
  notes text,
  display_order int not null default 0
);
create index scholarship_award_tiers_scholarship_idx on scholarship.award_tiers(scholarship_id);

create table scholarship.scopes (
  id uuid primary key default extensions.gen_random_uuid(),
  scholarship_id uuid not null references scholarship.scholarships(id) on delete cascade,
  scope_type text not null check (scope_type in ('provider','course','course_collection','study_level','field_of_study','country','campus','global')),
  provider_id uuid references catalogue.providers(id),
  course_id uuid references catalogue.courses(id),
  course_collection_id uuid references catalogue.course_collections(id),
  study_level_id uuid references ref.study_levels(id),
  field_id uuid references ref.fields_of_study(id),
  country_id uuid references ref.countries(id),
  campus_id uuid references catalogue.campuses(id),
  include_exclude text not null default 'include' check (include_exclude in ('include','exclude')),
  source_id uuid,
  evidence_id uuid,
  created_at timestamptz not null default now()
);
create index scholarship_scopes_scholarship_idx on scholarship.scopes(scholarship_id,scope_type);
create index scholarship_scopes_collection_idx on scholarship.scopes(course_collection_id) where course_collection_id is not null;

create table scholarship.criteria (
  id uuid primary key default extensions.gen_random_uuid(),
  scholarship_id uuid not null references scholarship.scholarships(id) on delete cascade,
  criterion_type text not null,
  operator text,
  value_text text,
  value_number numeric,
  value_codes text[],
  value_json jsonb,
  human_text text,
  is_mandatory boolean not null default true,
  machine_evaluable boolean not null default false,
  status text not null default 'active',
  source_id uuid,
  evidence_id uuid,
  confidence numeric(5,4),
  created_at timestamptz not null default now()
);
create index scholarship_criteria_scholarship_idx on scholarship.criteria(scholarship_id,criterion_type);

create table scholarship.coverage (
  id uuid primary key default extensions.gen_random_uuid(),
  scholarship_id uuid not null references scholarship.scholarships(id) on delete cascade,
  coverage_type text not null,
  percentage numeric(6,3),
  amount numeric(14,2),
  currency_code char(3) references ref.currencies(code),
  duration_value numeric(8,2),
  duration_unit text,
  notes text,
  source_id uuid,
  evidence_id uuid
);

revoke all on all tables in schema scholarship from anon, authenticated;
revoke usage on schema scholarship from anon, authenticated;
grant usage on schema scholarship to service_role;
grant all on all tables in schema scholarship to service_role;
