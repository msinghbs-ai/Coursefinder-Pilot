create table catalogue.providers (
  id uuid primary key references pim.entity_registry(id) on delete cascade,
  stable_key text not null unique,
  canonical_name text not null,
  display_name text,
  short_name text,
  country_id uuid not null references ref.countries(id),
  subdivision_id uuid references ref.subdivisions(id),
  provider_type_id uuid references ref.provider_types(id),
  website text,
  description text,
  primary_city text,
  address_line1 text,
  address_line2 text,
  postcode text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  phone text,
  email text,
  logo_url text,
  established_year smallint,
  lifecycle_status text not null default 'active',
  publication_status text not null default 'unpublished',
  canonical_source_id uuid,
  last_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index providers_country_pub_idx on catalogue.providers(country_id,publication_status);
create index providers_type_idx on catalogue.providers(provider_type_id);

create table catalogue.provider_identifiers (
  id uuid primary key default extensions.gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  scheme text not null,
  identifier text not null,
  country_id uuid references ref.countries(id),
  issuing_authority text,
  is_primary boolean not null default false,
  valid_from date,
  valid_to date,
  source_id uuid,
  evidence_id uuid,
  verified_at timestamptz,
  unique(provider_id,scheme,identifier)
);
create index provider_identifiers_lookup_idx on catalogue.provider_identifiers(scheme,identifier);

create table catalogue.provider_aliases (
  id uuid primary key default extensions.gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  alias text not null,
  alias_type text,
  locale text,
  valid_from date,
  valid_to date,
  source_id uuid
);
create unique index provider_aliases_unique_idx on catalogue.provider_aliases(provider_id,alias,coalesce(locale,''));

create table catalogue.campuses (
  id uuid primary key default extensions.gen_random_uuid(),
  stable_key text not null unique,
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  name text not null,
  campus_code text,
  country_id uuid not null references ref.countries(id),
  subdivision_id uuid references ref.subdivisions(id),
  city text,
  address_line1 text,
  address_line2 text,
  postcode text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  phone text,
  website text,
  status text not null default 'active',
  publication_status text not null default 'unpublished',
  valid_from date,
  valid_to date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index campuses_provider_status_idx on catalogue.campuses(provider_id,status);
create index campuses_geo_idx on catalogue.campuses(country_id,subdivision_id,city);

create table catalogue.provider_registrations (
  id uuid primary key default extensions.gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  source_id uuid,
  registration_scheme text not null,
  registration_code text not null,
  provider_classification text,
  status text not null default 'active',
  valid_from date,
  valid_to date,
  checked_at timestamptz,
  evidence_id uuid,
  unique(registration_scheme,registration_code,provider_id)
);
create index provider_registrations_provider_idx on catalogue.provider_registrations(provider_id);

create table catalogue.provider_collection_memberships (
  id uuid primary key default extensions.gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  collection_id uuid not null references ref.institution_collections(id),
  membership_type text,
  status text not null default 'active',
  valid_from date,
  valid_to date,
  source_id uuid,
  evidence_id uuid,
  verified_at timestamptz
);
create unique index provider_collection_memberships_unique_idx on catalogue.provider_collection_memberships(provider_id,collection_id,coalesce(valid_from,'0001-01-01'::date));

create table catalogue.provider_rankings (
  id uuid primary key default extensions.gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  ranking_source_id uuid not null references ref.ranking_sources(id),
  ranking_year int not null,
  subject_field_id uuid references ref.fields_of_study(id),
  rank_exact int,
  rank_band_min int,
  rank_band_max int,
  percentile numeric(6,3),
  score numeric,
  display_label text,
  source_id uuid,
  evidence_id uuid,
  verified_at timestamptz
);
create unique index provider_rankings_unique_idx on catalogue.provider_rankings(provider_id,ranking_source_id,ranking_year,coalesce(subject_field_id,'00000000-0000-0000-0000-000000000000'::uuid));

create table catalogue.course_collections (
  id uuid primary key default extensions.gen_random_uuid(),
  stable_key text not null unique,
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  name text not null,
  code text,
  description text,
  parent_id uuid references catalogue.course_collections(id),
  source_url text,
  lifecycle_status text not null default 'active',
  publication_status text not null default 'unpublished',
  display_order int not null default 0,
  valid_from date,
  valid_to date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index course_collections_provider_code_idx on catalogue.course_collections(provider_id,coalesce(code,stable_key));
create index course_collections_provider_parent_idx on catalogue.course_collections(provider_id,parent_id);

create table catalogue.courses (
  id uuid primary key references pim.entity_registry(id) on delete cascade,
  stable_key text not null unique,
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  canonical_title text not null,
  display_title text,
  course_code text,
  source_version text,
  study_level_id uuid references ref.study_levels(id),
  primary_field_id uuid references ref.fields_of_study(id),
  description text,
  course_url text,
  duration_value numeric(8,2),
  duration_unit text,
  delivery_mode text,
  lifecycle_status text not null default 'active',
  publication_status text not null default 'unpublished',
  canonical_source_id uuid,
  last_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index courses_provider_code_version_idx on catalogue.courses(provider_id,coalesce(course_code,stable_key),coalesce(source_version,''));
create index courses_provider_pub_idx on catalogue.courses(provider_id,publication_status);
create index courses_level_field_idx on catalogue.courses(study_level_id,primary_field_id);

create table catalogue.course_collection_memberships (
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  collection_id uuid not null references catalogue.course_collections(id) on delete cascade,
  is_primary boolean not null default false,
  display_order int not null default 0,
  relationship_type text not null default 'member',
  source_id uuid,
  evidence_id uuid,
  primary key(course_id,collection_id)
);
create index course_collection_memberships_collection_idx on catalogue.course_collection_memberships(collection_id);

create table catalogue.course_registrations (
  id uuid primary key default extensions.gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  scheme text not null,
  registration_code text not null,
  country_id uuid references ref.countries(id),
  status text not null default 'active',
  valid_from date,
  valid_to date,
  source_id uuid,
  evidence_id uuid,
  unique(course_id,scheme,registration_code)
);
create index course_registrations_lookup_idx on catalogue.course_registrations(scheme,registration_code);

create table catalogue.course_campuses (
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  campus_id uuid not null references catalogue.campuses(id) on delete cascade,
  delivery_mode text not null default '',
  is_primary boolean not null default false,
  source_id uuid,
  evidence_id uuid,
  primary key(course_id,campus_id,delivery_mode)
);

create table catalogue.course_fees (
  id uuid primary key default extensions.gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  fee_year int,
  audience text not null default 'international',
  fee_type text not null,
  amount numeric(14,2),
  currency_code char(3) references ref.currencies(code),
  basis text,
  load_basis text,
  is_csp boolean,
  notes text,
  valid_from date,
  valid_to date,
  source_id uuid,
  evidence_id uuid,
  confidence numeric(5,4),
  created_at timestamptz not null default now()
);
create index course_fees_course_year_idx on catalogue.course_fees(course_id,fee_year,audience);

create table catalogue.course_intakes (
  id uuid primary key default extensions.gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  intake_year int,
  intake_label text not null,
  start_date date,
  application_deadline date,
  campus_id uuid references catalogue.campuses(id),
  status text not null default 'active',
  source_id uuid,
  evidence_id uuid,
  confidence numeric(5,4)
);
create index course_intakes_course_idx on catalogue.course_intakes(course_id,intake_year,status);

create table catalogue.course_english_requirements (
  id uuid primary key default extensions.gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  english_test_id uuid not null references ref.english_tests(id),
  overall_score numeric(8,2),
  component_scores jsonb not null default '{}'::jsonb,
  notes text,
  source_id uuid,
  evidence_id uuid,
  confidence numeric(5,4),
  unique(course_id,english_test_id)
);
create index course_english_course_idx on catalogue.course_english_requirements(course_id);

revoke all on all tables in schema catalogue from anon, authenticated;
revoke usage on schema catalogue from anon, authenticated;
grant usage on schema catalogue to service_role;
grant all on all tables in schema catalogue to service_role;
