-- Live column shapes (3 Nov 2026, read-only information_schema on the live project) for what the two edited definitions read; only the
-- columns they use. security.layer4_search_blocked_courses is the live view text (its md5 is checked by the migration's step 1).
create schema catalogue; create schema ref; create schema pipeline; create schema security; create schema search; create schema scholarship; create schema api;
create table ref.countries (id uuid primary key default gen_random_uuid(), iso_alpha2 char(2));
create table ref.subdivisions (id uuid primary key default gen_random_uuid(), code text);
create table catalogue.providers (id uuid primary key default gen_random_uuid(), stable_key text, display_name text, canonical_name text, country_id uuid, primary_city text);
create table catalogue.courses (id uuid primary key default gen_random_uuid(), provider_id uuid, lifecycle_status text default 'active');
create table catalogue.campuses (id uuid primary key default gen_random_uuid(), stable_key text, provider_id uuid, name text, city text, postcode text, subdivision_id uuid, status text, publication_status text);
create table catalogue.course_campuses (course_id uuid, campus_id uuid, delivery_mode text, is_primary boolean);
create table pipeline.campus_regional_class (campus_id uuid, metro_area text, category int, category_name text);
create table search.course_documents (course_id uuid, provider_id uuid, study_level_code text, primary_field_code text);
create table security.layer4_active_blocks (entity_id uuid, block_scope text, entity_type text);
create table security.provider_hidden_v1 (provider_id uuid);
create view security.layer4_search_blocked_courses as
 SELECT layer4_active_blocks.entity_id AS course_id
   FROM security.layer4_active_blocks
  WHERE ((layer4_active_blocks.block_scope = 'search'::text) AND (layer4_active_blocks.entity_type = 'course'::text))
UNION
 SELECT c.id AS course_id
   FROM (security.layer4_active_blocks b
     JOIN catalogue.courses c ON ((c.provider_id = b.entity_id)))
  WHERE ((b.block_scope = 'search'::text) AND (b.entity_type = 'provider'::text))
UNION
 SELECT c.id AS course_id
   FROM (security.provider_hidden_v1 h
     JOIN catalogue.courses c ON ((c.provider_id = h.provider_id)))
UNION
 SELECT c.id AS course_id
   FROM catalogue.courses c
  WHERE (c.lifecycle_status IS DISTINCT FROM 'active'::text);
create table scholarship.scholarships (id uuid primary key default gen_random_uuid(), stable_key text, provider_id uuid, name text, scholarship_type text, description text,
  award_value_text text, application_required boolean, application_open_date date, application_close_date date, source_url text, lifecycle_status text default 'active',
  publication_status text default 'published', updated_at timestamptz default now(), award_value_type text, award_percentage numeric, award_amount numeric,
  award_currency_code text, award_duration_basis text, award_value_is_maximum boolean, nationalities text[]);
create table scholarship.criteria (id uuid primary key default gen_random_uuid(), scholarship_id uuid, criterion_type text, value_text text, value_number numeric,
  value_codes text[], value_json jsonb, human_text text, status text default 'active', confidence numeric);
create table scholarship.nationality_readings (scholarship_id uuid primary key, codes text[], phrases jsonb, reader_version text, read_at timestamptz default now());
create table scholarship.course_mappings (scholarship_id uuid, course_id uuid, mapping_state text);
create table pipeline.layer4_review_items (id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, field_code text, status text);
create table pipeline.scholarship_ai_reviews (id bigserial primary key, scholarship_id uuid, reason text, status text);
create table pipeline.platform_toolset_settings (toolset_key text, key text, label text, kind text, value jsonb, min_value numeric, max_value numeric, unit text, used_by text, primary key (toolset_key, key));
-- live security.pipeline_num_v1 (3 Nov 2026)
CREATE OR REPLACE FUNCTION security.pipeline_num_v1(p_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default)
$function$;
-- stubs: not read by the change (shapes only)
create function security.provider_presentable_name(text) returns text language sql immutable as $$ select $1 $$;
create function api.website_v2_provider_logo(uuid) returns jsonb language sql stable as $$ select null::jsonb $$;
