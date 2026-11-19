create table search.profiles (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  channel_code text references publishing.channels(code),
  version text not null,
  config jsonb not null default '{}'::jsonb,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into search.profiles(code,name,channel_code,version,config) values
('website-default','Website Default','website','1',jsonb_build_object('fts_weight',1,'vector_weight',0.55,'rrf_k',60)),
('zoho-default','Zoho Default','zoho','1',jsonb_build_object('fts_weight',0.8,'vector_weight',0.8,'rrf_k',60))
on conflict (code) do nothing;

create table search.intent_aliases (
  id uuid primary key default extensions.gen_random_uuid(),
  profile_id uuid references search.profiles(id) on delete cascade,
  alias text not null,
  canonical_text text not null,
  inferred_level_code text,
  locale text not null default 'en',
  priority int not null default 100,
  status text not null default 'active',
  unique(profile_id,alias,locale)
);

create table search.course_documents (
  course_id uuid primary key references catalogue.courses(id) on delete cascade,
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  country_id uuid not null references ref.countries(id),
  study_level_id uuid references ref.study_levels(id),
  primary_field_id uuid references ref.fields_of_study(id),
  provider_name text not null,
  course_title text not null,
  collection_names text[] not null default '{}',
  academic_option_names text[] not null default '{}',
  description text,
  search_text text not null,
  search_tsv tsvector not null,
  has_fee boolean not null default false,
  has_intake boolean not null default false,
  has_english boolean not null default false,
  has_scholarship boolean not null default false,
  publication_status text not null,
  completeness_score numeric(5,2),
  catalogue_generation bigint not null default 1,
  content_hash text,
  updated_at timestamptz not null default now()
);
create index course_documents_tsv_idx on search.course_documents using gin(search_tsv);
create index course_documents_country_level_idx on search.course_documents(country_id,study_level_id,publication_status);
create index course_documents_field_idx on search.course_documents(primary_field_id,publication_status);
create index course_documents_provider_idx on search.course_documents(provider_id,publication_status);
create index course_documents_flags_idx on search.course_documents(has_scholarship,has_fee,has_intake,has_english);

create table search.projection_state (
  projection_code text primary key,
  generation bigint not null default 1,
  rebuilt_at timestamptz,
  row_count bigint not null default 0,
  content_hash text,
  metadata jsonb not null default '{}'::jsonb
);
insert into search.projection_state(projection_code) values ('courses') on conflict do nothing;

revoke all on all tables in schema search from anon, authenticated;
revoke usage on schema search from anon, authenticated;
grant usage on schema search to service_role;
grant all on all tables in schema search to service_role;
