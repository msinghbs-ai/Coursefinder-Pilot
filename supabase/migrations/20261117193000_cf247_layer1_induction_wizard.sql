-- CF-247 Parallel Wave 2 (Platform Admin 17 Nov 2026 17:59 and decisions 18:10, S1-RM-Design): country and register induction wizard, and the
-- Country & category completeness report.
--   1. ref.enrichment_categories and ref.enrichment_category_fields: the eight enrichment categories and which of the 32 coverage fields belongs
--      to each (editable by the Platform Admin with a reason; shared with the Layer 1 loaders). The list is the one the Platform Admin chose at
--      18:10. The Boost matrix of 18:02 (migration 20261117183000) uses eight other keys; each field carries its Boost category beside it.
--   2. pipeline.layer1_source_inductions: one row per wizard draft (country and scheme, source and licence, field mappings, cadence and retention,
--      dry-run result, activation). Drafting is Pipeline Operator and above (who can open Layer 1); activation is the Platform Admin's, with a
--      reason, and creates the source through the existing public.admin_layer1_add_source, which saves it paused.
--   3. Per-source retention values are recorded only. No retention policy, prune job or stored row is changed here.
--   4. Service functions for the loaders: read an induction, and record its dry-run result. Nothing here calls an AI model or loads data.
--   5. public.admin_completeness_report(): field fill by country and category (pipeline.field_coverage_daily), Layer 1 edition and retention
--      status, and how long Layer 4 items have waited.
-- A passing dry run never switches anything on: activation stays a person's step and the source stays paused until it is resumed.
-- G1: no job. G2: sizes and thresholds are settings (layer1.induction_*, health.layer4_age_*); input-safety bounds are marked fixed.
-- G3: no consumer API object is touched.
-- Replaces: the single-form Add a source panel on Layer 1 › Sources (screen only, removed in the same release; public.admin_layer1_add_source is kept and called by the wizard).
-- Retires: nothing.

set local lock_timeout = '5s'; -- fixed: deploy-time safety

do $$ begin
  if to_regclass('pipeline.field_coverage_daily') is null or to_regclass('pipeline.layer1_source_operations') is null or to_regclass('pipeline.sources') is null
     or to_regclass('pipeline.layer1_dataset_editions') is null or to_regclass('pipeline.layer4_review_items') is null or to_regclass('pipeline.retention_class_policies') is null
     or to_regclass('ref.registration_schemes') is null or to_regclass('ref.countries') is null or to_regclass('pipeline.admin_control_events') is null
     or to_regclass('pipeline.platform_toolset_settings') is null or to_regprocedure('security.pipeline_num_v1(text,numeric)') is null
     or to_regprocedure('public.admin_layer1_add_source(jsonb)') is null or to_regprocedure('security.current_role_rank()') is null then
    raise exception 'an object this change builds on is missing';
  end if;
end $$;

-- 1. The eight enrichment categories and their fields
create table if not exists ref.enrichment_categories (
  category_key text primary key check (category_key ~ '^[a-z_]{3,40}$'),
  label text not null,
  description text not null,
  sort_order integer not null,
  active boolean not null default true,
  updated_at timestamptz not null default now());
comment on table ref.enrichment_categories is 'The enrichment categories a course or provider value belongs to (Platform Admin 17 Nov 2026: eight categories). Used by the Layer 1 induction wizard, the loaders'' category routing and the Country & category completeness report.';

create table if not exists ref.enrichment_category_fields (
  field text primary key check (field ~ '^[a-z0-9_]{2,60}$'),
  category_key text not null references ref.enrichment_categories(category_key),
  label text not null,
  boost_category text check (boost_category is null or boost_category ~ '^[a-z_]{3,40}$'),
  updated_by uuid,
  updated_at timestamptz not null default now());
comment on table ref.enrichment_category_fields is 'Which enrichment category each coverage field (pipeline.field_coverage_daily.field) belongs to. One category per field; changed by the Platform Admin with a reason (public.admin_enrichment_category_field_set). boost_category is the Layer 2/3 Boost category of the same field (setting country_category_boost, migration 20261117183000), so the report''s categories and the Boost matrix are tied field by field.';

alter table ref.enrichment_categories enable row level security;
alter table ref.enrichment_category_fields enable row level security;
revoke all on table ref.enrichment_categories, ref.enrichment_category_fields from public, anon, authenticated;
grant select on table ref.enrichment_categories, ref.enrichment_category_fields to service_role;

insert into ref.enrichment_categories(category_key, label, description, sort_order) values
 ('course_basics', 'Course basics', 'What the course is: level, length, delivery, field of study, description and its official page.', 10),
 ('fees', 'Fees', 'Tuition as the register lists it and as the provider publishes it.', 20),
 ('entry_requirements', 'Entry requirements', 'Academic and English entry requirements and the provider entry matrix.', 30),
 ('intakes_deadlines', 'Intakes & deadlines', 'When the course starts and when applications close.', 40),
 ('campus_location', 'Campus & location', 'Where the course is taught and where the provider is.', 50),
 ('provider_profile', 'Provider profile', 'The provider''s description, logo, type, website and contact.', 60),
 ('recognition_registration', 'Recognition & registration', 'Registrations, accreditations and whether international students can enrol.', 70),
 ('scholarships', 'Scholarships', 'Scholarships the provider offers.', 80)
on conflict (category_key) do nothing;

insert into ref.enrichment_category_fields(field, category_key, label, boost_category) values
 ('level', 'course_basics', 'Level', 'identity_registers'), ('duration', 'course_basics', 'Duration', 'intakes_delivery'), ('delivery', 'course_basics', 'Delivery mode', 'intakes_delivery'), ('field_of_study', 'course_basics', 'Field of study', 'identity_registers'),
 ('description', 'course_basics', 'Course description', 'identity_registers'), ('official_url', 'course_basics', 'Official course page', 'identity_registers'), ('v3_study_load', 'course_basics', 'Study load (API v3)', 'intakes_delivery'),
 ('v3_empty_reason', 'course_basics', 'Reason a value is empty (API v3)', 'identity_registers'),
 ('provider_tuition', 'fees', 'Tuition published by the provider', 'tuition_fees'), ('registered_tuition', 'fees', 'Tuition on the register', 'tuition_fees'),
 ('academic_entry', 'entry_requirements', 'Academic entry', 'admissions_entry'), ('english', 'entry_requirements', 'English requirement', 'admissions_entry'), ('p_entry_matrix', 'entry_requirements', 'Provider entry matrix', 'admissions_entry'),
 ('v3_grade_normalised', 'entry_requirements', 'Normalised grade (API v3)', 'admissions_entry'),
 ('intakes', 'intakes_deadlines', 'Intakes', 'intakes_delivery'), ('deadline', 'intakes_deadlines', 'Application deadline', 'intakes_delivery'),
 ('campus', 'campus_location', 'Campus', 'geo_localities'), ('campus_city', 'campus_location', 'Campus city', 'geo_localities'), ('p_campuses', 'campus_location', 'Provider campuses', 'geo_localities'), ('p_address', 'campus_location', 'Provider address', 'geo_localities'),
 ('v3_campus_primary', 'campus_location', 'Primary campus (API v3)', 'geo_localities'), ('v3_destination', 'campus_location', 'Destination data (API v3)', 'geo_localities'),
 ('p_description', 'provider_profile', 'Provider description', 'identity_registers'), ('p_logo', 'provider_profile', 'Provider logo', 'identity_registers'), ('p_type', 'provider_profile', 'Provider type', 'identity_registers'),
 ('p_website', 'provider_profile', 'Provider website', 'identity_registers'), ('p_contact', 'provider_profile', 'Provider contact', 'identity_registers'),
 ('p_registrations', 'recognition_registration', 'Provider registrations', 'identity_registers'), ('v3_accreditations', 'recognition_registration', 'Accreditations (API v3)', 'scholarships_accred'),
 ('international', 'recognition_registration', 'Open to international students', 'identity_registers'), ('p_international', 'recognition_registration', 'Provider takes international students', 'identity_registers'),
 ('p_scholarships', 'scholarships', 'Provider scholarships', 'scholarships_accred')
on conflict (field) do nothing;

-- 2. Settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'layer1.induction_dry_run_rows', 'Source induction: dry-run rows',
  'How many rows of a new source a dry run reads before activation.',
  'number', to_jsonb(100), 10, 1000, 'rows', 3260, 'Induction wizard (Platform Admin 17 Nov 2026 17:59)', 'Layer 1 induction', 'public.admin_layer1_induction_read; the loaders'' dry run'),
 ('pipeline', 'layer1.induction_sample_rows', 'Source induction: sample rows kept',
  'The most rows of an uploaded sample kept with a draft and shown for mapping.',
  'number', to_jsonb(20), 5, 100, 'rows', 3261, 'Induction wizard (Platform Admin 17 Nov 2026 17:59)', 'Layer 1 induction', 'public.admin_layer1_induction_save'),
 ('pipeline', 'health.layer4_age_warn_days', 'Layer 4 queue: waiting',
  'A Layer 4 item waiting longer than this is counted as waiting on the Country & category completeness report.',
  'number', to_jsonb(7), 1, 60, 'days', 3262, 'Completeness report (Platform Admin 17 Nov 2026 17:59)', 'Platform health', 'public.admin_completeness_report'),
 ('pipeline', 'health.layer4_age_old_days', 'Layer 4 queue: old',
  'A Layer 4 item waiting longer than this is counted as old on the Country & category completeness report.',
  'number', to_jsonb(30), 2, 365, 'days', 3263, 'Completeness report (Platform Admin 17 Nov 2026 17:59)', 'Platform health', 'public.admin_completeness_report')
on conflict do nothing;

-- 3. Wizard drafts
create table if not exists pipeline.layer1_source_inductions (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'draft' check (status in ('draft', 'activated', 'cancelled')),
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  mappings jsonb not null default '[]'::jsonb check (jsonb_typeof(mappings) = 'array'),
  dry_run jsonb,
  source_id uuid,
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now(),
  activated_by uuid, activated_at timestamptz, activation_reason text, status_reason text);
comment on table pipeline.layer1_source_inductions is 'Layer 1 induction wizard: one row per new country or register source being set up (scheme, source and licence, field and category mappings, cadence, per-source retention values, dry-run result, activation). Activation creates the source paused through admin_layer1_add_source. Retention values here are recorded, not enforced.';
create index if not exists layer1_source_inductions_source_idx on pipeline.layer1_source_inductions(source_id) where source_id is not null;
alter table pipeline.layer1_source_inductions enable row level security;
revoke all on table pipeline.layer1_source_inductions from public, anon, authenticated;

-- which of the six steps a draft has finished, and what is missing
create or replace function security.layer1_induction_steps_v1(p_row pipeline.layer1_source_inductions) returns jsonb
language sql stable set search_path = '' as $fn$
  select jsonb_build_object(
    'scheme', p_row.country_code is not null and coalesce(p_row.payload->>'scheme', '') <> '' and coalesce(p_row.payload->>'scheme_kind', '') <> '',
    'source', coalesce(p_row.payload->>'source_label', '') <> '' and coalesce(p_row.payload->>'source_url', '') ~* '^https://' and coalesce(p_row.payload->>'authority_name', '') <> ''
              and coalesce(p_row.payload->>'connector_type', '') <> '' and coalesce(p_row.payload->>'terms_status', '') <> ''
              and (p_row.payload->>'terms_status' = 'not_required' or coalesce(p_row.payload->>'licence_name', '') <> ''),
    'mapping', jsonb_array_length(p_row.mappings) > 0,
    'cadence', coalesce(p_row.payload->>'cadence', '') in ('weekly', 'monthly', 'annual'),
    'dry_run', coalesce(p_row.dry_run->>'status', '') = 'passed',
    'dry_run_state', coalesce(p_row.dry_run->>'status', 'waiting_for_reader'),
    'activated', p_row.status = 'activated')
$fn$;
revoke all on function security.layer1_induction_steps_v1(pipeline.layer1_source_inductions) from public, anon, authenticated;

create or replace function security.layer1_induction_item_v1(p_row pipeline.layer1_source_inductions) returns jsonb
language sql stable set search_path = '' as $fn$
  select jsonb_build_object('id', p_row.id, 'status', p_row.status, 'country_code', p_row.country_code, 'payload', p_row.payload, 'mappings', p_row.mappings, 'dry_run', p_row.dry_run,
    'source_id', p_row.source_id, 'created_at', p_row.created_at, 'updated_at', p_row.updated_at, 'activated_at', p_row.activated_at, 'activation_reason', p_row.activation_reason,
    'status_reason', p_row.status_reason, 'steps', security.layer1_induction_steps_v1(p_row))
$fn$;
revoke all on function security.layer1_induction_item_v1(pipeline.layer1_source_inductions) from public, anon, authenticated;

create or replace function public.admin_layer1_induction_read(p_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 4 then raise exception 'Pipeline Operator (rank 4) or above is needed for Layer 1' using errcode = '42501'; end if; -- fixed: who opens Layer 1
  return jsonb_build_object(
    'rank', security.current_role_rank(),
    'options', jsonb_build_object(
      'countries', (select coalesce(jsonb_agg(jsonb_build_object('code', c.iso_alpha2, 'name', c.name) order by c.name), '[]'::jsonb) from ref.countries c where c.iso_alpha2 is not null),
      'schemes', (select coalesce(jsonb_agg(jsonb_build_object('scheme', s.scheme, 'kind', s.kind, 'country_code', s.country_code, 'label', s.label, 'authority', s.authority) order by s.country_code, s.kind, s.scheme), '[]'::jsonb) from ref.registration_schemes s),
      'categories', (select coalesce(jsonb_agg(jsonb_build_object('key', k.category_key, 'label', k.label, 'description', k.description,
                       'fields', (select coalesce(jsonb_agg(jsonb_build_object('field', f.field, 'label', f.label, 'boost_category', f.boost_category) order by f.label), '[]'::jsonb) from ref.enrichment_category_fields f where f.category_key = k.category_key)) order by k.sort_order), '[]'::jsonb)
                     from ref.enrichment_categories k where k.active),
      'connector_types', jsonb_build_array('csv_file', 'xlsx_file', 'json_api', 'html_pages', 'pdf_document', 'manual_upload'),
      'cadences', jsonb_build_array('weekly', 'monthly', 'annual'),
      'terms_statuses', jsonb_build_array('approved', 'pending', 'not_required'),
      'retention_defaults', jsonb_build_object(
        'staging_retention_days', (select p.default_retention_days from pipeline.retention_class_policies p where p.class_key = 'temporary_staging'),
        'raw_retention_days', (select p.default_retention_days from pipeline.retention_class_policies p where p.class_key = 'accepted_source_versions')),
      'dry_run_rows', security.pipeline_num_v1('layer1.induction_dry_run_rows', 100),
      'sample_rows', security.pipeline_num_v1('layer1.induction_sample_rows', 20),
      'postcode_min_share', security.pipeline_num_v1('destination.postcode_primary_min_share', 0.9)),
    'drafts', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'status', i.status, 'country_code', i.country_code, 'label', i.payload->>'source_label', 'updated_at', i.updated_at,
                 'steps', security.layer1_induction_steps_v1(i)) order by i.updated_at desc), '[]'::jsonb)
               from pipeline.layer1_source_inductions i
              where i.id in (select x.id from pipeline.layer1_source_inductions x where x.status = 'draft' or x.updated_at > now() - interval '30 days' order by x.updated_at desc limit 50)), -- fixed: list length of one screen
    'item', (select security.layer1_induction_item_v1(i) from pipeline.layer1_source_inductions i where i.id = p_id));
end $$;

create or replace function public.admin_layer1_induction_save(p_id uuid, p_payload jsonb, p_mappings jsonb default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare p jsonb := coalesce(p_payload, '{}'::jsonb); v_row pipeline.layer1_source_inductions; v_cc text; v_clean jsonb := '{}'::jsonb; k text; v text; m jsonb; v_maps jsonb;
        v_max_sample int := security.pipeline_num_v1('layer1.induction_sample_rows', 20)::int; v_n numeric;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 4 then raise exception 'Pipeline Operator (rank 4) or above is needed for Layer 1' using errcode = '42501'; end if; -- fixed: who opens Layer 1
  if jsonb_typeof(p) <> 'object' then raise exception 'the draft must be an object' using errcode = '22023'; end if;
  if p_id is not null then
    select * into v_row from pipeline.layer1_source_inductions i where i.id = p_id for update;
    if v_row.id is null then raise exception 'draft not found' using errcode = '22023'; end if;
    if v_row.status <> 'draft' then raise exception 'this induction is % and can no longer be changed', v_row.status using errcode = '22023'; end if;
  end if;
  v_cc := upper(btrim(coalesce(p->>'country_code', v_row.country_code, '')));
  if v_cc !~ '^[A-Z]{2}$' or not exists (select 1 from ref.countries c where c.iso_alpha2 = v_cc) then raise exception 'choose a country (two-letter ISO code)' using errcode = '22023'; end if;
  -- plain text values: trimmed, bounded
  foreach k in array array['scheme', 'scheme_kind', 'field_scheme', 'source_label', 'source_url', 'authority_name', 'dataset_class', 'connector_type', 'expected_format',
                           'licence_name', 'licence_url', 'attribution_text', 'terms_status', 'cadence', 'notes', 'sample_file_name'] loop
    v := btrim(coalesce(p->>k, v_row.payload->>k, ''));
    if length(v) > 600 then raise exception '% is too long (600 characters at most)', k using errcode = '22023'; end if; -- fixed: input-safety bound
    v_clean := v_clean || jsonb_build_object(k, v);
  end loop;
  if v_clean->>'scheme' <> '' and not exists (select 1 from ref.registration_schemes s where s.scheme = v_clean->>'scheme' and s.kind = v_clean->>'scheme_kind' and s.country_code = v_cc) then
    raise exception 'scheme % (%) is not registered for %; register it in ref.registration_schemes first', v_clean->>'scheme', v_clean->>'scheme_kind', v_cc using errcode = '22023';
  end if;
  if v_clean->>'source_url' <> '' and v_clean->>'source_url' !~* '^https://[^[:space:]/]+\.[^[:space:]]+$' then raise exception 'the source address must be an https address' using errcode = '22023'; end if;
  if v_clean->>'licence_url' <> '' and v_clean->>'licence_url' !~* '^https://[^[:space:]]+$' then raise exception 'the licence address must be an https address' using errcode = '22023'; end if;
  if v_clean->>'connector_type' not in ('', 'csv_file', 'xlsx_file', 'json_api', 'html_pages', 'pdf_document', 'manual_upload') then raise exception 'unknown connector type' using errcode = '22023'; end if;
  if v_clean->>'terms_status' not in ('', 'approved', 'pending', 'not_required') then raise exception 'terms of use are approved, pending or not required' using errcode = '22023'; end if;
  if v_clean->>'cadence' not in ('', 'weekly', 'monthly', 'annual') then raise exception 'the cadence is weekly, monthly or annual' using errcode = '22023'; end if;
  if v_clean->>'dataset_class' not in ('', 'register', 'statistics') then raise exception 'the type is register or statistics' using errcode = '22023'; end if;
  v_clean := v_clean || jsonb_build_object('edition_archiving', coalesce((p->>'edition_archiving')::boolean, (v_row.payload->>'edition_archiving')::boolean, true));
  -- per-source retention: recorded, not enforced. null days means kept permanently.
  foreach k in array array['staging_retention_days', 'raw_retention_days'] loop
    if p ? k then v_n := nullif(p->>k, '')::numeric; else v_n := nullif(v_row.payload->>k, '')::numeric; end if;
    if v_n is not null and (v_n <> trunc(v_n) or v_n < 1 or v_n > 36500) then raise exception '% is a whole number of days from 1 to 36,500, or empty for permanent', k using errcode = '22023'; end if; -- fixed: input-safety bound
    v_clean := v_clean || jsonb_build_object(k, v_n);
  end loop;
  -- an uploaded sample: column names and the first rows only
  m := coalesce(case when p ? 'sample' then p->'sample' end, v_row.payload->'sample');
  if m is not null and jsonb_typeof(m) = 'object' then
    if jsonb_typeof(m->'columns') <> 'array' or jsonb_array_length(m->'columns') > 300 then raise exception 'the sample needs its column names (300 at most)' using errcode = '22023'; end if; -- fixed: input-safety bound
    v_clean := v_clean || jsonb_build_object('sample', jsonb_build_object('columns', m->'columns', 'total_rows', nullif(m->>'total_rows', '')::bigint,
      'rows', (select coalesce(jsonb_agg(r.value order by r.ord), '[]'::jsonb) from jsonb_array_elements(case when jsonb_typeof(m->'rows') = 'array' then m->'rows' else '[]'::jsonb end) with ordinality r(value, ord) where r.ord <= v_max_sample)));
    if pg_column_size(v_clean->'sample') > 400000 then raise exception 'the sample is too large; keep fewer or narrower rows' using errcode = '22023'; end if; -- fixed: input-safety bound
  end if;
  -- mappings: source field to a coverage field and its category
  v_maps := coalesce(p_mappings, v_row.mappings, '[]'::jsonb);
  if jsonb_typeof(v_maps) <> 'array' or jsonb_array_length(v_maps) > 500 then raise exception 'the mappings must be a list (500 at most)' using errcode = '22023'; end if; -- fixed: input-safety bound
  for m in select value from jsonb_array_elements(v_maps) loop
    if coalesce(btrim(m->>'source_field'), '') = '' then raise exception 'every mapping names its source field' using errcode = '22023'; end if;
    if coalesce(m->>'category_key', '') <> '' and not exists (select 1 from ref.enrichment_categories c where c.category_key = m->>'category_key') then raise exception 'unknown category %', m->>'category_key' using errcode = '22023'; end if;
    if coalesce(m->>'target_field', '') <> '' and coalesce(m->>'target_field', '') !~ '^[a-z0-9_.]{2,80}$' then raise exception 'target field % is not a field name', m->>'target_field' using errcode = '22023'; end if;
    if coalesce(m->>'by', 'manual') not in ('manual', 'ai', 'ai_adjusted') then raise exception 'a mapping is manual, ai or ai_adjusted' using errcode = '22023'; end if;
  end loop;
  if p_id is null then
    insert into pipeline.layer1_source_inductions(country_code, payload, mappings, created_by, updated_by) values (v_cc, v_clean, v_maps, auth.uid(), auth.uid()) returning * into v_row;
  else
    update pipeline.layer1_source_inductions i set country_code = v_cc, payload = v_clean, mappings = v_maps, updated_by = auth.uid(), updated_at = now() where i.id = p_id returning * into v_row;
  end if;
  return jsonb_build_object('ok', true, 'item', security.layer1_induction_item_v1(v_row));
end $$;

create or replace function public.admin_layer1_induction_cancel(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_row pipeline.layer1_source_inductions;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 4 then raise exception 'Pipeline Operator (rank 4) or above is needed for Layer 1' using errcode = '42501'; end if; -- fixed: who opens Layer 1
  if v_reason is null then raise exception 'a reason is required' using errcode = '22023'; end if;
  update pipeline.layer1_source_inductions i set status = 'cancelled', status_reason = v_reason, updated_by = auth.uid(), updated_at = now() where i.id = p_id and i.status = 'draft' returning * into v_row;
  if v_row.id is null then raise exception 'only a draft can be cancelled' using errcode = '22023'; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('layer1', 'induction_cancel', v_row.id::text, jsonb_build_object('reason', v_reason, 'label', v_row.payload->>'source_label'), auth.uid());
  return jsonb_build_object('ok', true, 'item', security.layer1_induction_item_v1(v_row));
end $$;

-- Step 6: the Platform Admin activates. The source is created paused by admin_layer1_add_source and stays paused; nothing runs from here.
create or replace function public.admin_layer1_induction_activate(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_row pipeline.layer1_source_inductions; s jsonb; v_added jsonb; v_source uuid; v_ev bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) activates a new source' using errcode = '42501'; end if; -- fixed: activation is the Platform Admin's
  if v_reason is null or length(v_reason) < 4 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into v_row from pipeline.layer1_source_inductions i where i.id = p_id for update;
  if v_row.id is null then raise exception 'draft not found' using errcode = '22023'; end if;
  if v_row.status <> 'draft' then raise exception 'this induction is already %', v_row.status using errcode = '22023'; end if;
  s := security.layer1_induction_steps_v1(v_row);
  if not (s->>'scheme')::boolean then raise exception 'step 1 is not finished: choose the country and scheme' using errcode = '22023'; end if;
  if not (s->>'source')::boolean then raise exception 'step 2 is not finished: source address, authority, connector and licence terms' using errcode = '22023'; end if;
  if not (s->>'mapping')::boolean then raise exception 'step 3 is not finished: map at least one field' using errcode = '22023'; end if;
  if not (s->>'cadence')::boolean then raise exception 'step 4 is not finished: choose the cadence' using errcode = '22023'; end if;
  if coalesce(v_row.dry_run->>'status', '') = 'failed' then raise exception 'the dry run failed; fix the source or its mapping and run it again' using errcode = '22023'; end if;
  v_added := public.admin_layer1_add_source(jsonb_build_object('country_code', v_row.country_code, 'label', v_row.payload->>'source_label', 'url', v_row.payload->>'source_url',
    'authority_name', v_row.payload->>'authority_name', 'dataset_class', coalesce(nullif(v_row.payload->>'dataset_class', ''), 'register'),
    'ingestion_cadence_days', case v_row.payload->>'cadence' when 'weekly' then 7 when 'monthly' then 30 else 365 end, -- fixed: days in the named cadence
    'expected_format', v_row.payload->>'connector_type', 'notes', nullif(v_row.payload->>'notes', ''), 'reason', v_reason));
  v_source := (v_added->>'source_id')::uuid;
  update pipeline.layer1_source_inductions i set status = 'activated', source_id = v_source, activated_by = auth.uid(), activated_at = now(), activation_reason = v_reason,
         updated_by = auth.uid(), updated_at = now() where i.id = p_id returning * into v_row;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer1', 'induction_activate', v_source::text, jsonb_build_object('reason', v_reason, 'induction_id', v_row.id, 'label', v_row.payload->>'source_label', 'country', v_row.country_code,
          'scheme', v_row.payload->>'scheme', 'terms_status', v_row.payload->>'terms_status', 'dry_run', s->>'dry_run_state', 'source_paused', true), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', true, 'source_id', v_source, 'source_paused', true, 'dry_run', s->>'dry_run_state', 'event_id', v_ev, 'item', security.layer1_induction_item_v1(v_row));
end $$;

-- for the loaders (service role): read an induction by id or by its source, and record a dry run
create or replace function public.svc_layer1_induction_read(p_id uuid default null, p_source_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  return (select security.layer1_induction_item_v1(i) from pipeline.layer1_source_inductions i
           where (p_id is not null and i.id = p_id) or (p_id is null and p_source_id is not null and i.source_id = p_source_id) order by i.updated_at desc limit 1);
end $$;

create or replace function public.svc_layer1_induction_dry_run_record(p_id uuid, p_result jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb := coalesce(p_result, '{}'::jsonb); v_row pipeline.layer1_source_inductions; k text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  if r->>'status' not in ('passed', 'failed') then raise exception 'a dry run is passed or failed' using errcode = '22023'; end if;
  foreach k in array array['rows_read', 'inserts', 'updates', 'departures', 'postcode_escalations'] loop
    if coalesce(r->>k, '') !~ '^[0-9]{1,9}$' then raise exception '% is a count', k using errcode = '22023'; end if;
  end loop;
  update pipeline.layer1_source_inductions i set updated_at = now(),
    dry_run = jsonb_build_object('status', r->>'status', 'rows_read', (r->>'rows_read')::int, 'inserts', (r->>'inserts')::int, 'updates', (r->>'updates')::int, 'departures', (r->>'departures')::int,
      'postcode_escalations', (r->>'postcode_escalations')::int, 'reader', left(coalesce(r->>'reader', ''), 120), 'message', left(coalesce(r->>'message', ''), 600), 'recorded_at', now())
   where i.id = p_id returning * into v_row;
  if v_row.id is null then raise exception 'induction not found' using errcode = '22023'; end if;
  -- recorded only: a passing dry run switches nothing on
  return jsonb_build_object('ok', true, 'item', security.layer1_induction_item_v1(v_row));
end $$;

-- the Platform Admin moves a coverage field to another category, with a reason
create or replace function public.admin_enrichment_category_field_set(p_field text, p_category_key text, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_old text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) changes a field''s category' using errcode = '42501'; end if; -- fixed: reference data is the Platform Admin's
  if v_reason is null then raise exception 'a reason is required' using errcode = '22023'; end if;
  if not exists (select 1 from ref.enrichment_categories c where c.category_key = p_category_key and c.active) then raise exception 'unknown category' using errcode = '22023'; end if;
  if coalesce(p_field, '') !~ '^[a-z0-9_]{2,60}$' then raise exception 'not a field name' using errcode = '22023'; end if;
  select f.category_key into v_old from ref.enrichment_category_fields f where f.field = p_field;
  insert into ref.enrichment_category_fields(field, category_key, label, updated_by) values (p_field, p_category_key, initcap(replace(p_field, '_', ' ')), auth.uid())
  on conflict (field) do update set category_key = excluded.category_key, updated_by = excluded.updated_by, updated_at = now();
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('reference', 'enrichment_category_field_set', p_field, jsonb_build_object('reason', v_reason, 'from', v_old, 'to', p_category_key), auth.uid());
  return jsonb_build_object('ok', true, 'field', p_field, 'from', v_old, 'to', p_category_key);
end $$;

-- 5. Country & category completeness report (Platform health)
create or replace function public.admin_completeness_report() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_day date; v_warn int := security.pipeline_num_v1('health.layer4_age_warn_days', 7)::int; v_old int := greatest(security.pipeline_num_v1('health.layer4_age_old_days', 30)::int, v_warn + 1);
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator (rank 3) or above is needed for this report' using errcode = '42501'; end if; -- fixed: Platform health opens at Curator
  select max(f.snapshot_date) into v_day from pipeline.field_coverage_daily f;
  return jsonb_build_object(
    'rank', security.current_role_rank(), 'snapshot_date', v_day,
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('key', k.category_key, 'label', k.label, 'description', k.description) order by k.sort_order), '[]'::jsonb) from ref.enrichment_categories k where k.active),
    'countries', (select coalesce(jsonb_agg(distinct f.country_code order by f.country_code), '[]'::jsonb) from pipeline.field_coverage_daily f where f.snapshot_date = v_day),
    'cells', (select coalesce(jsonb_agg(jsonb_build_object('country_code', x.country_code, 'category_key', x.category_key, 'total', x.total, 'filled', x.filled,
                'pct', case when x.total > 0 then round(100.0 * x.filled / x.total, 1) end, 'fields', x.fields) order by x.country_code, x.category_key), '[]'::jsonb)
              from (select f.country_code, coalesce(m.category_key, 'unmapped') as category_key, sum(f.total) as total, sum(f.filled) as filled,
                           jsonb_agg(jsonb_build_object('field', f.field, 'label', coalesce(m.label, f.field), 'total', f.total, 'filled', f.filled,
                             'pct', case when f.total > 0 then round(100.0 * f.filled / f.total, 1) end) order by f.field) as fields
                      from pipeline.field_coverage_daily f left join ref.enrichment_category_fields m on m.field = f.field
                     where f.snapshot_date = v_day group by 1, 2) x),
    'editions', (select coalesce(jsonb_agg(jsonb_build_object('source_id', s.id, 'label', s.label, 'country_code', c.iso_alpha2, 'paused', o.paused, 'source_status', s.status,
                   'editions_kept', e.n, 'current_edition', e.current_key, 'edition_last_verified_at', e.last_verified,
                   'last_verified_at', o.last_verified_at, 'verification_status', o.verification_status, 'previous_count', o.previous_accepted_count, 'last_count', o.last_expected_count,
                   'variance_percent', o.variance_percent, 'variance_decision', o.variance_decision,
                   'retention', jsonb_build_object('per_source', i.id is not null, 'staging_retention_days', coalesce(nullif(i.payload->>'staging_retention_days', '')::int, pol.staging),
                     'raw_retention_days', case when i.id is not null then nullif(i.payload->>'raw_retention_days', '')::int else pol.raw end,
                     'edition_archiving', coalesce((i.payload->>'edition_archiving')::boolean, true)))
                   order by c.iso_alpha2, s.label), '[]'::jsonb)
                 from pipeline.layer1_source_operations o join pipeline.sources s on s.id = o.source_id left join ref.countries c on c.id = s.country_id
                 left join lateral (select count(*) as n, max(d.edition_key) filter (where d.status = 'current') as current_key, max(d.last_verified_at) as last_verified
                                      from pipeline.layer1_dataset_editions d where d.source_id = s.id) e on true
                 left join lateral (select x.id, x.payload from pipeline.layer1_source_inductions x where x.source_id = s.id order by x.updated_at desc limit 1) i on true
                 cross join (select (select p.default_retention_days from pipeline.retention_class_policies p where p.class_key = 'temporary_staging') as staging,
                                    (select p.default_retention_days from pipeline.retention_class_policies p where p.class_key = 'accepted_source_versions') as raw) pol
                where s.status <> 'retired'),
    'retention_policy', (select coalesce(jsonb_agg(jsonb_build_object('class_key', p.class_key, 'days', p.default_retention_days, 'immutable', p.immutable, 'purge_allowed', p.purge_allowed) order by p.class_key), '[]'::jsonb)
                         from pipeline.retention_class_policies p),
    'layer4', jsonb_build_object('warn_days', v_warn, 'old_days', v_old,
      'pending', (select count(*) from pipeline.layer4_review_items r where r.status = 'pending'),
      'oldest_at', (select min(r.created_at) from pipeline.layer4_review_items r where r.status = 'pending'),
      'by_type', (select coalesce(jsonb_agg(jsonb_build_object('entity_type', x.entity_type, 'pending', x.n, 'fresh', x.fresh, 'waiting', x.waiting, 'old', x.old, 'oldest_at', x.oldest) order by x.n desc), '[]'::jsonb)
                  from (select r.entity_type, count(*) as n, count(*) filter (where r.created_at > now() - make_interval(days => v_warn)) as fresh,
                               count(*) filter (where r.created_at <= now() - make_interval(days => v_warn) and r.created_at > now() - make_interval(days => v_old)) as waiting,
                               count(*) filter (where r.created_at <= now() - make_interval(days => v_old)) as old, min(r.created_at) as oldest
                          from pipeline.layer4_review_items r where r.status = 'pending' group by 1) x)));
end $$;

revoke all on function public.admin_layer1_induction_read(uuid) from public, anon;
revoke all on function public.admin_layer1_induction_save(uuid, jsonb, jsonb) from public, anon;
revoke all on function public.admin_layer1_induction_cancel(uuid, text) from public, anon;
revoke all on function public.admin_layer1_induction_activate(uuid, text) from public, anon;
revoke all on function public.admin_enrichment_category_field_set(text, text, text) from public, anon;
revoke all on function public.admin_completeness_report() from public, anon;
revoke all on function public.svc_layer1_induction_read(uuid, uuid) from public, anon, authenticated;
revoke all on function public.svc_layer1_induction_dry_run_record(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.admin_layer1_induction_read(uuid) to authenticated, service_role;
grant execute on function public.admin_layer1_induction_save(uuid, jsonb, jsonb) to authenticated, service_role;
grant execute on function public.admin_layer1_induction_cancel(uuid, text) to authenticated, service_role;
grant execute on function public.admin_layer1_induction_activate(uuid, text) to authenticated, service_role;
grant execute on function public.admin_enrichment_category_field_set(text, text, text) to authenticated, service_role;
grant execute on function public.admin_completeness_report() to authenticated, service_role;
grant execute on function public.svc_layer1_induction_read(uuid, uuid) to service_role;
grant execute on function public.svc_layer1_induction_dry_run_record(uuid, jsonb) to service_role;

-- Post-check
do $$ begin
  if (select count(*) from ref.enrichment_categories) < 8 or (select count(*) from ref.enrichment_category_fields) < 32
     or (select count(*) from ref.enrichment_category_fields f where not exists (select 1 from ref.enrichment_categories c where c.category_key = f.category_key)) > 0
     or (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and (key like 'layer1.induction_%' or key like 'health.layer4_age_%')) <> 4 then
    raise exception 'post-check: induction wizard';
  end if;
end $$;
