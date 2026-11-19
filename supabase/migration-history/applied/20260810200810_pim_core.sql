create table pim.attribute_families (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  entity_type text not null,
  description text,
  is_default boolean not null default false,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table pim.attribute_groups (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  entity_type text not null,
  description text,
  display_order integer not null default 0,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table pim.family_groups (
  family_id uuid not null references pim.attribute_families(id) on delete cascade,
  group_id uuid not null references pim.attribute_groups(id) on delete cascade,
  display_order integer not null default 0,
  is_collapsed_default boolean not null default false,
  primary key (family_id, group_id)
);

create table pim.attribute_definitions (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  entity_type text not null,
  group_id uuid references pim.attribute_groups(id),
  data_type text not null check (data_type in ('text','number','boolean','date','datetime','url','richtext','select','multiselect','reference','json')),
  unit_code text,
  validation_rules jsonb not null default '{}'::jsonb,
  is_required_default boolean not null default false,
  is_unique boolean not null default false,
  is_filterable boolean not null default false,
  is_searchable boolean not null default false,
  include_in_vector boolean not null default false,
  vector_weight numeric(5,2) not null default 1,
  is_localisable boolean not null default false,
  is_channel_scoped boolean not null default false,
  is_multivalue boolean not null default false,
  is_bulk_editable boolean not null default true,
  display_order integer not null default 0,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index attribute_definitions_entity_status_idx on pim.attribute_definitions(entity_type,status);
create index attribute_definitions_group_idx on pim.attribute_definitions(group_id);
create index attribute_definitions_filterable_idx on pim.attribute_definitions(is_filterable) where is_filterable;
create index attribute_definitions_vector_idx on pim.attribute_definitions(include_in_vector) where include_in_vector;

create table pim.family_attributes (
  family_id uuid not null references pim.attribute_families(id) on delete cascade,
  attribute_id uuid not null references pim.attribute_definitions(id) on delete cascade,
  is_required boolean not null default false,
  is_visible boolean not null default true,
  display_order integer not null default 0,
  validation_override jsonb not null default '{}'::jsonb,
  primary key (family_id, attribute_id)
);

create table pim.attribute_options (
  id uuid primary key default extensions.gen_random_uuid(),
  attribute_id uuid not null references pim.attribute_definitions(id) on delete cascade,
  code text not null,
  label text not null,
  locale text,
  metadata jsonb not null default '{}'::jsonb,
  display_order integer not null default 0,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index attribute_options_attribute_code_locale_uq
  on pim.attribute_options(attribute_id, code, coalesce(locale,''));
create index attribute_options_attribute_idx on pim.attribute_options(attribute_id,display_order);

create table pim.categories (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  category_type text not null,
  parent_id uuid references pim.categories(id),
  path text,
  depth smallint not null default 0,
  description text,
  display_order integer not null default 0,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index categories_parent_idx on pim.categories(parent_id);
create index categories_type_status_idx on pim.categories(category_type,status);

create table pim.entity_registry (
  id uuid primary key default extensions.gen_random_uuid(),
  entity_type text not null,
  stable_key text not null unique,
  family_id uuid references pim.attribute_families(id),
  lifecycle_status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index entity_registry_type_status_idx on pim.entity_registry(entity_type,lifecycle_status);

create table pim.attribute_values (
  id uuid primary key default extensions.gen_random_uuid(),
  entity_id uuid not null references pim.entity_registry(id) on delete cascade,
  attribute_id uuid not null references pim.attribute_definitions(id),
  value_text text,
  value_number numeric,
  value_boolean boolean,
  value_date date,
  value_datetime timestamptz,
  value_code text,
  value_json jsonb,
  locale text,
  channel_code text,
  position integer not null default 0,
  source_id uuid,
  evidence_id uuid,
  confidence numeric(5,4),
  review_status text,
  is_preferred boolean not null default true,
  valid_from date,
  valid_to date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attribute_values_single_scalar_ck check (
    num_nonnulls(value_text,value_number,value_boolean,value_date,value_datetime,value_code,value_json) = 1
  )
);
create index attribute_values_entity_attribute_idx on pim.attribute_values(entity_id,attribute_id);
create index attribute_values_attribute_code_idx on pim.attribute_values(attribute_id,value_code);
create index attribute_values_attribute_number_idx on pim.attribute_values(attribute_id,value_number);
create index attribute_values_preferred_idx on pim.attribute_values(entity_id,attribute_id) where is_preferred;

create table pim.entity_categories (
  entity_id uuid not null references pim.entity_registry(id) on delete cascade,
  category_id uuid not null references pim.categories(id) on delete cascade,
  is_primary boolean not null default false,
  display_order integer not null default 0,
  primary key (entity_id,category_id)
);
create index entity_categories_category_idx on pim.entity_categories(category_id);

create table pim.completeness_profiles (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  entity_type text not null,
  family_id uuid references pim.attribute_families(id),
  country_id uuid references ref.countries(id),
  channel_code text,
  minimum_publish_score numeric(5,2),
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table pim.completeness_requirements (
  id uuid primary key default extensions.gen_random_uuid(),
  profile_id uuid not null references pim.completeness_profiles(id) on delete cascade,
  attribute_id uuid references pim.attribute_definitions(id),
  requirement_code text,
  weight numeric(6,3) not null default 1,
  is_mandatory boolean not null default false,
  rule jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint completeness_requirement_target_ck check (attribute_id is not null or requirement_code is not null)
);
create unique index completeness_requirements_target_uq
  on pim.completeness_requirements(profile_id, coalesce(attribute_id::text,''), coalesce(requirement_code,''));

alter table pim.attribute_families enable row level security;
alter table pim.attribute_groups enable row level security;
alter table pim.family_groups enable row level security;
alter table pim.attribute_definitions enable row level security;
alter table pim.family_attributes enable row level security;
alter table pim.attribute_options enable row level security;
alter table pim.categories enable row level security;
alter table pim.entity_registry enable row level security;
alter table pim.attribute_values enable row level security;
alter table pim.entity_categories enable row level security;
alter table pim.completeness_profiles enable row level security;
alter table pim.completeness_requirements enable row level security;

revoke usage on schema pim from anon, authenticated;
revoke all on all tables in schema pim from anon, authenticated;
grant usage on schema pim to service_role;
grant all on all tables in schema pim to service_role;
