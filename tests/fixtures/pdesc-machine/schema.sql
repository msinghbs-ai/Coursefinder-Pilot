-- Guards: F-PDESC (Platform Admin decision 9 Nov 2026): the production-shaped columns the register-fact profile reads, added to the scratch database's minimal stubs
-- (read from the live schema 9 Nov 2026: ref.countries.name, ref.study_levels.id, ref.fields_of_study, catalogue.courses.study_level_id and primary_field_id). Scratch database only.
alter table ref.countries add column if not exists name text;
alter table ref.study_levels add column if not exists id uuid default gen_random_uuid();
create table if not exists ref.fields_of_study (id uuid primary key default gen_random_uuid(), name text not null);
alter table catalogue.courses add column if not exists study_level_id uuid;
alter table catalogue.courses add column if not exists primary_field_id uuid;
create table if not exists pipeline.platform_toolsets(key text primary key, enforcement text, reason text, updated_by uuid, updated_at timestamptz);
create table if not exists pipeline.platform_job_layers(jobname text primary key, layer int, updated_at timestamptz);
create table if not exists pipeline.platform_notice_acks(notice_key text primary key, acknowledged_at timestamptz, acknowledged_by uuid, reason text);
update ref.countries set name = case iso_alpha2 when 'AU' then 'Australia' when 'NZ' then 'New Zealand' when 'CA' then 'Canada' end where name is null;
