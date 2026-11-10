-- Stubs: the tables and helpers the AER source recovery migration reads, in the shape live has them (only the columns it touches).
create schema if not exists security; create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists ref; create schema if not exists cron;
create table ref.countries (id int primary key, iso_alpha2 text, name text);
create table ref.study_levels (id int primary key, short_code text);
create table catalogue.providers (id uuid primary key default gen_random_uuid(), canonical_name text, website text, lifecycle_status text default 'active', publication_status text default 'published', enrols_international boolean default true, country_id int);
create table catalogue.courses (id uuid primary key default gen_random_uuid(), provider_id uuid, lifecycle_status text default 'active', canonical_title text, study_level_id int);
create table catalogue.provider_entry_matrix (id uuid primary key default gen_random_uuid(), provider_id uuid, status text, evidence_id uuid, quote text, run_id uuid, provenance jsonb default '{}', min_value numeric, grade_scale text);
create table catalogue.course_entry_requirements (id uuid primary key default gen_random_uuid(), course_id uuid, status text, evidence_id uuid, quote text, provenance jsonb default '{}', min_value numeric, grade_scale text);
create table pipeline.platform_toolset_settings (toolset_key text, key text, value jsonb, primary key (toolset_key, key));
create table pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), storage_path text);
create table pipeline.coverage_course_pages (course_id uuid primary key, status text, evidence_id uuid, identity_basis text);
create table pipeline.coverage_provider_urls (provider_id uuid, url text, title text, primary key (provider_id, url));
create table pipeline.provider_discovery_links (provider_id uuid, url text, anchor_text text, pages int default 1, primary key (provider_id, url));
create table pipeline.entry_matrix_sources (id uuid primary key default gen_random_uuid(), provider_id uuid, url text, title text, rank int, found_via text, status text default 'found', error text, content_hash text, read_via text, read_at timestamptz, attempts int default 0, updated_at timestamptz default now(), unique (provider_id, url));
create table pipeline.entry_matrix_runs (id uuid primary key default gen_random_uuid(), source_id uuid, state text, error text, result jsonb, content_hash text, review_item_id uuid, created_at timestamptz default now());
create table pipeline.layer4_review_items (id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, field_code text, status text default 'pending');
create table pipeline.field_enrich_items (id uuid primary key default gen_random_uuid(), course_id uuid, field text, state text, updated_at timestamptz default now());
create table pipeline.field_gap_queue_control (id int primary key, owner uuid);
create table security.roles (code text primary key, rank int, status text);
create table security.user_roles (user_id uuid, role_code text, expires_at timestamptz);
create table pipeline.layer3_openrouter_observations (kind text, remaining_usd numeric, observed_at timestamptz);
create table pipeline.aer_schedule_runs (id bigserial primary key, ran_at timestamptz default now(), course_reads int default 0, corrections int default 0, matrix_pages int default 0, layer4_waiting int, in_progress int, back_pressure boolean, used_before int, room int, refusal text, estimate_usd numeric, detail jsonb);
create table pipeline.aer_schedule_checks (item_id uuid primary key, checked_at timestamptz, outcome text);
create table pipeline.aer_source_stored_find (provider_id uuid primary key, checked_at timestamptz default now(), outcome text, attached int default 0);
create table pipeline.aer_review_readiness (review_item_id uuid primary key, provider_id uuid, readiness text, root_cause text, settled_at timestamptz);
create table pipeline.aer_course_outcomes (course_id uuid, provider_id uuid, outcome text, read_reason text);
create table pipeline.aer_gap_findings (id bigserial primary key, fingerprint text unique, root_cause text, provider_id uuid, state text default 'open', evidence jsonb, last_seen timestamptz default now());
create table pipeline.aer_provider_coverage (provider_id uuid primary key, country text, eligible boolean default true, disposition text, sources int default 0, sources_read int default 0, matrix_active int default 0, course_req_active int default 0, course_req_proposed int default 0, layer4 jsonb default '{}', updated_at timestamptz default now());
create table pipeline.work_items (id bigserial primary key, lane text, entity text, work_kind text, provider_id uuid, stage text, failure_class text, first_blocked_at timestamptz default now(), unresolved_blocker jsonb);
create table pipeline.enrich_reads_log (course_id uuid, at timestamptz default now());
create table cron.job (jobid serial primary key, jobname text, schedule text, active boolean default true);
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$ select coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = p_key), p_default) $$;
create function security.toolset_setting(p_tool text, p_key text) returns jsonb language sql stable as $$ select value from pipeline.platform_toolset_settings where toolset_key = p_tool and key = p_key $$;
create function security.site_host_v1(p text) returns text language sql immutable as $$ select nullif(lower(regexp_replace(substring(p from '^https?://([^/?#]+)'), '^www\.', '')), '') $$;
create function security.aer_eligible_v1() returns table(provider_id uuid, country text) language sql stable as $$ select p.id, k.iso_alpha2 from catalogue.providers p join ref.countries k on k.id = p.country_id where p.lifecycle_status = 'active' and p.publication_status = 'published' and p.enrols_international is true $$;
create function security.coverage_identity_allowed(p_provider uuid, p_basis text, p_field text) returns boolean language sql stable as $$ select coalesce(p_basis, '') not in ('exact_title', 'title_level', 'degree_name', 'adapter_title', '') $$;
create function security.aer_schedule_courses_v1(p_limit int, p_all boolean default false) returns table(course_id uuid, provider_id uuid, country text, provider_name text, tier int, turn bigint) language sql stable as $$
  select c.id, c.provider_id, e.country, p.canonical_name, 1, row_number() over (partition by c.provider_id order by c.id)
    from catalogue.courses c join security.aer_eligible_v1() e on e.provider_id = c.provider_id join catalogue.providers p on p.id = c.provider_id
    join pipeline.coverage_course_pages g on g.course_id = c.id and g.status = 'bound' join pipeline.evidence_artifacts a on a.id = g.evidence_id and a.storage_path is not null
   where c.lifecycle_status = 'active' and security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements')
     and not exists (select 1 from pipeline.layer4_review_items r where r.entity_id = c.id and r.field_code = 'course_entry_first_read' and r.status = 'pending')
   order by 6, c.id limit p_limit $$;
create function security.cron_next_run_v1(p text, t timestamptz) returns timestamptz language sql immutable as $$ select t + interval '1 hour' $$;
create function security.course_entry_cost_v1() returns numeric language sql stable as $$ select 0.005::numeric $$;
create function security.ai_use_refusal_v1(p text) returns text language sql stable as $$ select null::text $$;
create function security.work_review_room_v1(p text) returns jsonb language sql stable as $$ select jsonb_build_object('room', 0) $$;
create function security.aer_schedule_held_v1(p_limit int) returns table(item_id uuid, course_id uuid, provider_id uuid, country text, eligible boolean, outcome text) language sql stable as $$ select null::uuid, null::uuid, null::uuid, null::text, false, null::text where false $$;
create function security.aer_fair_courses_v1(p_room int) returns table(course_id uuid, provider_id uuid, country text, provider_name text, tier int, turn bigint) language sql stable as $$ select * from security.aer_schedule_courses_v1(p_room) $$;
create function security.enrich_item_held_v1(p_course uuid, p_field text) returns boolean language sql stable as $$ select false $$;
create function security.course_entry_read_enqueue_v1(p_course uuid, p_owner uuid, p_why text) returns uuid language plpgsql as $$ begin insert into pipeline.enrich_reads_log(course_id) values (p_course); return gen_random_uuid(); end $$;
create function security.course_entry_correction_v1(p_item uuid, p_owner uuid, p_why text) returns jsonb language sql as $$ select '{}'::jsonb $$;
create function security.work_item_report_v1(a text, b text, c text, d text, e jsonb) returns void language sql as $$ select $$;
create function security.entry_matrix_enabled_v1(p uuid) returns boolean language sql stable as $$ select true $$;
create function security.aer_technical_recovery_v1() returns jsonb language sql as $$ select '{}'::jsonb $$;
create function security.aer_run_cause_v1(a text, b text, c text) returns text language sql as $$ select null::text $$;
create function security.aer_fingerprint_v1(p uuid, s uuid, k text, kk text, l text, c text) returns text language sql immutable as $$ select md5(coalesce(p::text,'') || coalesce(s::text,'') || coalesce(k,'') || coalesce(kk,'') || coalesce(l,'') || coalesce(c,'')) $$;
create function security.data_delivery_pdesc_v1() returns jsonb language sql as $$ select '{}'::jsonb $$;
create function security.data_delivery_cdesc_stages_v1() returns jsonb language sql as $$ select '{}'::jsonb $$;
create table pipeline.component_register (kind text not null check (kind in ('job', 'table', 'view', 'edge_function', 'screen', 'function')), name text not null, layer text not null, area text, purpose text, status text not null default 'active', replaces text[] not null default '{}', replaced_by text, introduced_in text, primary key (kind, name));
