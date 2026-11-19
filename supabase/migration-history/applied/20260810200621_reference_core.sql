create table ref.regions (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  region_type text not null check (region_type in ('world','region','subregion','intermediate_region')),
  parent_id uuid references ref.regions(id),
  display_order integer not null default 0,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index regions_parent_idx on ref.regions(parent_id);
create index regions_type_status_idx on ref.regions(region_type,status);

create table ref.currencies (
  code char(3) primary key,
  name text not null,
  numeric_code char(3),
  minor_unit smallint,
  status text not null default 'active'
);

create table ref.languages (
  code text primary key,
  name text not null,
  status text not null default 'active'
);

create table ref.countries (
  id uuid primary key default extensions.gen_random_uuid(),
  iso_alpha2 char(2) not null unique,
  iso_alpha3 char(3) not null unique,
  iso_numeric char(3),
  name text not null,
  official_name text,
  region_id uuid references ref.regions(id),
  subregion_id uuid references ref.regions(id),
  default_currency_code char(3) references ref.currencies(code),
  default_locale text,
  catalogue_status text not null default 'seed_only',
  student_search_enabled boolean not null default false,
  provider_ingestion_enabled boolean not null default false,
  course_ingestion_enabled boolean not null default false,
  scholarship_ingestion_enabled boolean not null default false,
  valid_from date,
  valid_to date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index countries_catalogue_status_idx on ref.countries(catalogue_status);
create index countries_region_idx on ref.countries(region_id);
create index countries_subregion_idx on ref.countries(subregion_id);

create table ref.subdivisions (
  id uuid primary key default extensions.gen_random_uuid(),
  country_id uuid not null references ref.countries(id),
  code text not null unique,
  name text not null,
  subdivision_type text,
  parent_id uuid references ref.subdivisions(id),
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index subdivisions_country_name_idx on ref.subdivisions(country_id,name);
create index subdivisions_parent_idx on ref.subdivisions(parent_id);

create table ref.study_levels (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  parent_id uuid references ref.study_levels(id),
  sort_order integer not null default 0,
  status text not null default 'active'
);

create table ref.fields_of_study (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  parent_id uuid references ref.fields_of_study(id),
  path text,
  depth smallint not null default 0,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index fields_of_study_parent_idx on ref.fields_of_study(parent_id);

create table ref.provider_types (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  status text not null default 'active'
);

create table ref.english_tests (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  score_scale jsonb not null default '{}'::jsonb,
  status text not null default 'active'
);

create table ref.institution_collections (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  collection_type text not null,
  scope_type text not null,
  country_id uuid references ref.countries(id),
  region_id uuid references ref.regions(id),
  official_url text,
  description text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table ref.ranking_sources (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  ranking_type text,
  publisher_name text,
  source_url text,
  licence_status text,
  licence_notes text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
