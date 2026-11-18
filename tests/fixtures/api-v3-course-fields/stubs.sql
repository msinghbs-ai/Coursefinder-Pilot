-- Extra objects the v3 course item functions read (fixtures only, never a Supabase project).
create schema if not exists search;
create table if not exists search.course_documents (course_id uuid, provider_id uuid, course_stable_key text, description text);
create table if not exists catalogue.course_intakes (id uuid primary key default gen_random_uuid(), course_id uuid, status text, intake_label text, intake_year int, start_date date);
create table if not exists catalogue.course_campuses (course_id uuid, campus_id uuid);
create table if not exists ref.subdivisions (id uuid primary key default gen_random_uuid(), code text);
create table if not exists pipeline.campus_regional_class (campus_id uuid, metro_area text, category int, category_name text);
create table if not exists pipeline.scholarship_listing_pages (id uuid primary key default gen_random_uuid(), provider_id uuid, url text, read_at timestamptz, active boolean, status text);
create or replace view security.layer4_search_blocked_courses as select null::uuid course_id where false;
create or replace function security.intake_start_date_status_v1(p_intake uuid) returns text language sql stable as $$ select 'month_only'::text $$;
create or replace function security.place_presentable(p text) returns text language sql immutable as $$ select p $$;
alter table catalogue.providers add column if not exists country_id uuid;
