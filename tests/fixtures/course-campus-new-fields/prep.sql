-- Fixture only: the columns and tables migration 20261118073000 reads, which the course-catalogue-columns fixture (built 5 Nov 2026) predates. Invented shapes that
-- match the live columns the migration names; every row is invented.
alter table catalogue.courses add column if not exists study_load text check (study_load is null or study_load in ('full_time', 'part_time', 'both')), add column if not exists empty_reason_code text;
alter table catalogue.campuses add column if not exists is_primary boolean, add column if not exists primary_basis text;
create schema if not exists destination;
create table if not exists destination.localities (id uuid primary key default gen_random_uuid(), country_code character(2), name text, geography_type text, status text default 'draft');
create table if not exists destination.locality_postcodes (id uuid primary key default gen_random_uuid(), locality_id uuid references destination.localities(id), country_code character(2), postcode text,
  containment_share numeric, is_primary_match boolean, boundary_vintage text);
create index if not exists idx_destination_locality_postcodes_lookup on destination.locality_postcodes (country_code, postcode);
grant usage on schema destination to authenticated;
create table if not exists pipeline.layer1_source_inductions (id uuid primary key default gen_random_uuid(), status text default 'draft', country_code text, payload jsonb, mappings jsonb default '[]', updated_at timestamptz default now());
insert into pipeline.layer1_source_inductions(country_code, payload)
select 'IE', '{"source_label":"Interim List of Eligible Programmes (ILEP)","notes":"Wave 2 draft, pre-staged 17 Nov 2026. Programmes a non-EEA student may enrol in. The ILEP is closed."}'
 where not exists (select 1 from pipeline.layer1_source_inductions);
