-- Guards: Provider Description autonomy production-representative parity; isolated-only external boundaries.
-- auth identity uses explicit fixture settings. All admission/reader code is captured live, not simulated.
create table search.enrichment_gates(projection_code text,domain_code text,gate_status text);
create table catalogue.provider_outcomes(provider_id uuid,metric_id uuid,survey_id uuid,external_study_area_id uuid,status text,source_cohort_code text,national_benchmark numeric,metric_value numeric,confidence_low numeric,confidence_high numeric,collection_year_to int,response_count int);
create table ref.outcome_metrics(id uuid,code text,name text,unit text);
create table ref.outcome_surveys(id uuid,code text,name text);
create function security.entry_matrix_payload_v1(uuid,text) returns jsonb language sql stable as $$select '[]'::jsonb$$;
create function public.website_v2_provider_rankings(uuid) returns jsonb language sql stable as $$select '[]'::jsonb$$;
-- The full consumer provider projection is loaded live above. Its unrelated ranking/AER sections are empty fixtures.
create schema ranking;
create table ranking.observation_provider_links(provider_id uuid,observation_id uuid);
create table ranking.observations(id uuid,edition_id uuid,rank_low int,rank_exact int);
create table ranking.editions(id uuid,system_id uuid,edition_year int,status text);
create table ranking.systems(id uuid,code text);
create table search.course_documents(provider_id uuid,provider_stable_key text,provider_name text,country_code text,has_scholarship boolean,study_level_code text,primary_field_code text,primary_field_name text,subdivision_codes text[]);
create view security.layer4_search_blocked_providers as select id provider_id from catalogue.providers where publication_status<>'published';
create table catalogue.provider_assets(provider_id uuid,asset_type text,status text,is_primary boolean);
alter table scholarship.scholarships add column lifecycle_status text,add column publication_status text;
create table catalogue.provider_collection_memberships(provider_id uuid,collection_id uuid,status text,valid_to date);
create table ref.institution_collections(id uuid,collection_type text,status text,code text);
create table catalogue.campuses(id uuid,provider_id uuid,city text);
create table pipeline.campus_regional_class(campus_id uuid,metro_area text,category int);
create table ref.study_levels(code text,name text);
create function api.website_text_array(jsonb) returns text[] language sql immutable as $$select case when $1 is null then null when jsonb_typeof($1)='array' then array(select jsonb_array_elements_text($1)) else array[$1#>>'{}'] end$$;
create function security.provider_presentable_name(text) returns text language sql immutable as $$select $1$$;
create function security.provider_university_groups(uuid) returns jsonb language sql stable as $$select '[]'::jsonb$$;
create function api.website_v2_institution_type_code(uuid) returns text language sql stable as $$select t.code from catalogue.providers p join ref.provider_types t on t.id=p.provider_type_id where p.id=$1$$;
create function api.website_v2_institution_type(uuid) returns jsonb language sql stable as $$select to_jsonb(api.website_v2_institution_type_code($1))$$;
create function api.website_v2_provider_campuses(uuid) returns jsonb language sql stable as $$select '[]'::jsonb$$;
create function api.website_v2_ranking_summary(uuid) returns jsonb language sql stable as $$select '{}'::jsonb$$;
create function api.website_v2_provider_logo(uuid) returns jsonb language sql stable as $$select null::jsonb$$;
create table pipeline.layer2_run_items(job_id uuid,batch_id uuid,entity_id uuid);
create table pipeline.layer2_scope_wave_requests(id uuid,metadata jsonb,scope_type text,scope_id uuid,country_code text,route_mode text);
-- Existing live helper dispatch tables are empty because no unrelated provider lifecycle work is requested in this fixture.
create table pipeline.provider_home_queue(provider_id uuid);
create table pipeline.provider_page_queue(provider_id uuid);
alter table pipeline.provider_central_search add column state text,add column requested_at timestamptz,add column leased_until timestamptz,add column updated_at timestamptz;
create table pipeline.provider_onboarding_settings(id int,auto_start_new boolean);
create table pipeline.coverage_provider_discovery(provider_id uuid primary key,status text,requested_at timestamptz,updated_at timestamptz);
-- Use the authoritative hidden-provider predicate in both reader and consumer projection.
create or replace view security.provider_hidden_v1 as select p.id provider_id from catalogue.providers p where p.publication_status is distinct from 'published' or p.lifecycle_status is distinct from 'active';
create table security.layer4_active_blocks(entity_id uuid,block_scope text,entity_type text);
create or replace view security.layer4_search_blocked_providers as select entity_id provider_id from security.layer4_active_blocks where block_scope='search' and entity_type='provider' union select provider_id from security.provider_hidden_v1;
