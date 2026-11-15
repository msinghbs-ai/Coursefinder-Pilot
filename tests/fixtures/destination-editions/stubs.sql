-- Minimal tables that 20261115190000_api_v3_additive_schema.sql builds on (fixtures only, never a Supabase project).
create schema if not exists catalogue; create schema if not exists ref; create schema if not exists pipeline; create schema if not exists security;
create table ref.countries (id uuid primary key default gen_random_uuid(), iso_alpha2 char(2) not null unique, name text not null);
insert into ref.countries(iso_alpha2, name) values ('AU', 'Australia'), ('NZ', 'New Zealand');
create table catalogue.providers (id uuid primary key default gen_random_uuid(), stable_key text, canonical_name text);
create table catalogue.courses (id uuid primary key default gen_random_uuid(), provider_id uuid);
create table catalogue.campuses (id uuid primary key default gen_random_uuid(), provider_id uuid references catalogue.providers(id), name text, city text);
create table catalogue.course_english_requirements (id uuid primary key default gen_random_uuid(), course_id uuid, overall_score numeric, component_scores jsonb);
create table pipeline.component_register (kind text, name text, layer text, area text, purpose text, status text, replaces text[], introduced_in text, unique (kind, name));
