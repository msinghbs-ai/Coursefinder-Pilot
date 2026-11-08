-- Guards: IQ-00313 (Deakin commencement-date contamination, 8 Nov 2026): the production shape of every table this change writes or reads.
-- The release before this one failed because a fixture allowed a null that production forbids. Every table below is brought to the production NOT NULL
-- set and defaults (read from information_schema on production, fxcwkweaxjtknorudmwp, 8 Nov 2026) and the file ends by asserting them, so a fixture
-- that drifts from production fails here, not in the cases.
\set ON_ERROR_STOP on

-- pipeline.manual_locks: entity, entity_id, field, mode, set_at not null (the fixture lacked set_at)
update pipeline.manual_locks set set_at = now() where set_at is null;
alter table pipeline.manual_locks alter column set_at set not null;

-- catalogue.course_intakes: course_id, id, intake_label, status not null (the fixture had only id)
alter table catalogue.course_intakes alter column course_id set not null, alter column intake_label set not null, alter column status set not null;

-- search.course_documents: the production columns (the fixture had eight of them)
create temp table dk_docs_cols as select * from (values
    ('course_id', 'uuid', true, null), ('provider_id', 'uuid', true, null), ('country_id', 'uuid', true, null), ('study_level_id', 'uuid', false, null), ('primary_field_id', 'uuid', false, null),
    ('provider_name', 'text', true, null), ('course_title', 'text', true, null), ('collection_names', 'text[]', true, '''{}''::text[]'), ('academic_option_names', 'text[]', true, '''{}''::text[]'),
    ('description', 'text', false, null), ('search_text', 'text', true, null), ('search_tsv', 'tsvector', true, null), ('has_fee', 'boolean', true, 'false'), ('has_intake', 'boolean', true, 'false'),
    ('has_english', 'boolean', true, 'false'), ('has_scholarship', 'boolean', true, 'false'), ('publication_status', 'text', true, null), ('completeness_score', 'numeric', false, null),
    ('catalogue_generation', 'bigint', true, '1'), ('content_hash', 'text', false, null), ('updated_at', 'timestamptz', true, 'now()'), ('course_stable_key', 'text', false, null),
    ('provider_stable_key', 'text', false, null), ('course_code', 'text', false, null), ('country_code', 'text', false, null), ('study_level_code', 'text', false, null),
    ('primary_field_code', 'text', false, null), ('primary_field_name', 'text', false, null), ('subdivision_codes', 'text[]', true, '''{}''::text[]'), ('delivery_modes', 'text[]', true, '''{}''::text[]'),
    ('has_state', 'boolean', true, 'false'), ('has_link', 'boolean', true, 'false'), ('projection_version', 'text', true, '''course-v2''::text'), ('source_updated_at', 'timestamptz', false, null),
    ('generated_at', 'timestamptz', true, 'now()'), ('semantic_content_hash', 'text', false, null), ('regulatory_tuition_state', 'text', false, null), ('has_regulatory_tuition', 'boolean', true, 'false'),
    ('regulatory_tuition_amount', 'numeric', false, null), ('regulatory_tuition_currency', 'character(3)', false, null), ('regulatory_tuition_basis', 'text', false, null),
    ('has_provider_current_tuition', 'boolean', true, 'false'), ('provider_annual_tuition_amount', 'numeric', false, null), ('provider_annual_tuition_currency', 'character(3)', false, null),
    ('provider_tuition_options', 'jsonb', true, '''[]''::jsonb'), ('official_course_url', 'text', false, null), ('intake_options', 'jsonb', true, '''[]''::jsonb'), ('earliest_intake_date', 'date', false, null),
    ('english_requirement_options', 'jsonb', true, '''[]''::jsonb'), ('scholarship_options', 'jsonb', true, '''[]''::jsonb'), ('enrichment_semantic_text', 'text', false, null), ('enrichment_content_hash', 'text', false, null)
  ) t(name, typ, nn, dflt);
do $$
declare c record;
begin
  for c in select * from dk_docs_cols
  loop
    if not exists (select 1 from information_schema.columns where table_schema = 'search' and table_name = 'course_documents' and column_name = c.name) then
      execute format('alter table search.course_documents add column %I %s%s', c.name, c.typ, case when c.dflt is not null then ' default ' || c.dflt else '' end);
    end if;
    if c.dflt is not null then execute format('alter table search.course_documents alter column %I set default %s', c.name, c.dflt); end if;
  end loop;
  -- values for the rows the fixture already holds, then the production NOT NULL
  update search.course_documents d set provider_id = coalesce(d.provider_id, (select c2.provider_id from catalogue.courses c2 where c2.id = d.course_id)),
         country_id = coalesce(d.country_id, '6cc98ba2-045f-e409-8d24-356d14447085'::uuid),
         provider_name = coalesce(d.provider_name, 'fixture provider'), course_title = coalesce(d.course_title, 'fixture course'),
         search_text = coalesce(d.search_text, ''), search_tsv = coalesce(d.search_tsv, ''::tsvector), publication_status = coalesce(d.publication_status, 'published'),
         has_intake = coalesce(d.has_intake, false);
  for c in select name from dk_docs_cols where nn loop
    execute format('alter table search.course_documents alter column %I set not null', c.name);
  end loop;
end $$;

-- the Website API v2 course item of the fixture carries the keys the stored items are compared on (production: title, intakes, country_code, course_id, publication_status, ...)
create or replace function api.website_v2_course_item(p_course_id uuid, p_cities text[] DEFAULT NULL::text[], p_postcodes text[] DEFAULT NULL::text[]) returns jsonb language sql stable as $f$
  select jsonb_build_object('course_id', d.course_id, 'title', d.course_title, 'country_code', d.country_code, 'publication_status', 'published', 'freshness', jsonb_build_object('generated_at', now()),
           'intakes', coalesce((select jsonb_agg(distinct jsonb_build_object('label', i->>'label', 'month', api.website_v2_label_month(i->>'label'), 'year', i->'year',
                    'start_date', i->'start_date', 'application_deadline', i->'application_deadline'))
                   from jsonb_array_elements(coalesce(d.intake_options, '[]'::jsonb)) i where nullif(i->>'label', '') is not null), '[]'::jsonb))
    from search.course_documents d where d.course_id = p_course_id $f$;

-- the stored Website and Zoho items and their scans, in the production shape (columns, NOT NULL, defaults, checks, keys, sequences)
create sequence if not exists pipeline.website_sync_seq;
create sequence if not exists pipeline.zoho_sync_seq;
create table if not exists pipeline.website_sync_items (
  entity text not null check (entity = any (array['reference', 'provider', 'logo', 'rankings', 'scholarship', 'course'])),
  item_key text not null, ref_id uuid, hash text, seq bigint not null, seq_at timestamptz not null default now(), removed_at timestamptz, item jsonb,
  primary key (entity, item_key));
create table if not exists pipeline.zoho_sync_items (
  entity text not null check (entity = any (array['provider', 'campus', 'contact', 'course'])),
  item_key text not null, ref_id uuid, hash text, seq bigint not null, seq_at timestamptz not null default now(), removed_at timestamptz, item jsonb,
  primary key (entity, item_key));
create table if not exists pipeline.website_sync_scan (
  entity text primary key, after_key text, done boolean not null default false, cycles integer not null default 0, last_cycle_at timestamptz, last_run_at timestamptz, last_result jsonb);
create table if not exists pipeline.zoho_sync_scan (
  entity text primary key, after_key text, done boolean not null default false, cycles integer not null default 0, last_cycle_at timestamptz, last_run_at timestamptz, last_result jsonb);
-- only the course step is left to run in the fixture (the other entities are done), so a scan checks courses exactly as production does
insert into pipeline.website_sync_scan(entity, done) select e, e <> 'course' from unnest(array['reference', 'provider', 'logo', 'rankings', 'scholarship', 'course']) e on conflict (entity) do nothing;
insert into pipeline.zoho_sync_scan(entity, done) select e, e <> 'course' from unnest(array['provider', 'campus', 'contact', 'course']) e on conflict (entity) do nothing;
-- the campus key the Zoho candidate function reads (never filled in these cases)
alter table catalogue.campuses add column if not exists stable_key text;
-- tables the production candidate functions name (never read in these cases)
create table if not exists pipeline.provider_contact_points (id uuid primary key default gen_random_uuid(), provider_id uuid not null, is_current boolean not null default true);
create table if not exists pipeline.provider_contacts (id uuid primary key default gen_random_uuid(), provider_id uuid not null, lifecycle_status text not null default 'active', deleted_at timestamptz);

-- the production change-check functions, verbatim (md5 checked by run.sh)
\i tests/fixtures/deakin-intake-calendar/live-sync-functions.sql

-- assertions: the production NOT NULL sets (information_schema, 8 Nov 2026)
do $$
declare v text;
begin
  select string_agg(column_name, ',' order by column_name collate "C") into v from information_schema.columns where table_schema = 'catalogue' and table_name = 'course_intakes' and is_nullable = 'NO';
  if v <> 'course_id,id,intake_label,status' then raise exception 'catalogue.course_intakes not null set differs from production: %', v; end if;
  select string_agg(column_name, ',' order by column_name collate "C") into v from information_schema.columns where table_schema = 'pipeline' and table_name = 'manual_locks' and is_nullable = 'NO';
  if v <> 'entity,entity_id,field,mode,set_at' then raise exception 'pipeline.manual_locks not null set differs from production: %', v; end if;
  select string_agg(column_name, ',' order by column_name collate "C") into v from information_schema.columns where table_schema = 'pipeline' and table_name = 'admin_control_events' and is_nullable = 'NO';
  if v <> 'action,area,created_at,detail,id' then raise exception 'pipeline.admin_control_events not null set differs from production: %', v; end if;
  select string_agg(column_name, ',' order by column_name collate "C") into v from information_schema.columns where table_schema = 'search' and table_name = 'course_documents' and is_nullable = 'NO';
  if v <> 'academic_option_names,catalogue_generation,collection_names,country_id,course_id,course_title,delivery_modes,english_requirement_options,generated_at,has_english,has_fee,has_intake,has_link,has_provider_current_tuition,has_regulatory_tuition,has_scholarship,has_state,intake_options,projection_version,provider_id,provider_name,provider_tuition_options,publication_status,scholarship_options,search_text,search_tsv,subdivision_codes,updated_at'
    then raise exception 'search.course_documents not null set differs from production: %', v; end if;
  select string_agg(column_name, ',' order by column_name collate "C") into v from information_schema.columns where table_schema = 'pipeline' and table_name = 'website_sync_items' and is_nullable = 'NO';
  if v <> 'entity,item_key,seq,seq_at' then raise exception 'pipeline.website_sync_items not null set differs from production: %', v; end if;
  select string_agg(column_name, ',' order by column_name collate "C") into v from information_schema.columns where table_schema = 'pipeline' and table_name = 'zoho_sync_items' and is_nullable = 'NO';
  if v <> 'entity,item_key,seq,seq_at' then raise exception 'pipeline.zoho_sync_items not null set differs from production: %', v; end if;
end $$;

-- helpers of the Deakin cases: the year of the next 1 November (so no date in the cases ages), and a calendar reading for a named university
create or replace function public.fixture_dk_y0() returns int language sql stable as $f$
  select extract(year from (now() at time zone 'Australia/Melbourne'))::int
         + case when (now() at time zone 'Australia/Melbourne')::date > make_date(extract(year from (now() at time zone 'Australia/Melbourne'))::int, 11, 1) then 1 else 0 end $f$;
create or replace function public.fixture_calendar_for(p_prov uuid, p_url text, p_parser text, p_proposal jsonb, p_status text default 'approved') returns uuid language plpgsql as $f$
declare v_src uuid; v_id uuid;
begin
  insert into pipeline.provider_fact_sources(provider_id, kind, url, status, content_hash) values (p_prov, 'intake_calendar', p_url, 'parsed', md5(p_url))
  on conflict (provider_id, kind, url) do update set updated_at = now() returning id into v_src;
  insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, url, proposal, status, decided_at)
  values (p_prov, v_src, 'intake_calendar', p_parser, md5(p_url || clock_timestamp()::text), p_url, p_proposal, p_status, case when p_status = 'approved' then now() end) returning id into v_id;
  return v_id;
end $f$;

-- one scan pass over courses, as the scheduled jobs run it (the other entities are marked done, as in production between passes)
create or replace function public.fixture_dk_scan() returns jsonb language plpgsql as $f$
declare w jsonb; z jsonb;
begin
  update pipeline.website_sync_scan set done = (entity <> 'course'), after_key = null;
  update pipeline.zoho_sync_scan set done = (entity <> 'course'), after_key = null;
  w := security.website_sync_check_v1(100000);
  z := security.zoho_sync_check_v1(100000);
  return jsonb_build_object('website', w->'course', 'zoho', z->'course');
end $f$;
