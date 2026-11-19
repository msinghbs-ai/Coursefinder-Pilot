create table catalogue.course_academic_options (
  id uuid primary key default extensions.gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  option_type text not null check (option_type in ('major','minor','specialisation','stream','program','concentration','research_pathway','sub_major','other')),
  code text,
  name text not null,
  description text,
  parent_id uuid references catalogue.course_academic_options(id),
  source_url text,
  display_order int not null default 0,
  status text not null default 'active',
  source_id uuid,
  evidence_id uuid,
  valid_from date,
  valid_to date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index course_academic_options_unique_idx on catalogue.course_academic_options(course_id,option_type,lower(name));
create index course_academic_options_parent_idx on catalogue.course_academic_options(parent_id);

create table catalogue.provider_associations (
  id uuid primary key default extensions.gen_random_uuid(),
  from_provider_id uuid not null references catalogue.providers(id) on delete cascade,
  to_provider_id uuid not null references catalogue.providers(id) on delete cascade,
  association_type text not null check (association_type in ('foundation_of','successor_of','predecessor_of','merged_into','renamed_to','affiliated_with','member_of','other')),
  valid_from date,
  valid_to date,
  status text not null default 'active',
  source_id uuid,
  evidence_id uuid,
  notes text,
  created_at timestamptz not null default now(),
  check (from_provider_id <> to_provider_id)
);
create unique index provider_associations_unique_idx on catalogue.provider_associations(from_provider_id,to_provider_id,association_type,coalesce(valid_from,'0001-01-01'::date));
create index provider_associations_to_idx on catalogue.provider_associations(to_provider_id,association_type);
