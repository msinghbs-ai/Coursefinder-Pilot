-- CF-247 StudySearch API v3: additive schema extensions (REQ-18/19/28, REQ-34, REQ-52, REQ-53, REQ-57, REQ-65/67, REQ-75, REQ-76).
--   1. catalogue.courses: study_load, study_load_source, study_load_evidence_id, empty_reason_code (new columns, checked vocabularies).
--   2. catalogue.campuses: is_primary (at most one per provider), primary_basis, street_address, accepts_international, source_url,
--      last_checked_at (new columns).
--   3. catalogue.provider_accreditations: AACSB / EQUIS / AMBA accreditations per provider (new table, FK catalogue.providers(id)).
--   4. catalogue.course_english_requirements: score_grade and subtest_grades for letter-graded tests such as OET (new columns). The numeric
--      OET score (0 to 500, WP-2.1, 20261113250000) stays in overall_score; a letter grade is held here and never turned into a number.
--   5. ref.grade_scale_conversions: academic entry grade normalisation to 0 to 100 (new table).
--   6. destination.editions, study_rules, city_profiles, career_outcomes: governed destination editions (new schema and tables).
--      city_profiles.city_id has no foreign key: the database has no canonical cities table (campuses hold city as text;
--      pipeline.city_regions is keyed by city_key text). Add the FK in the change that introduces one.
--   7. ref.api_field_dictionary: v3 field dictionary and allowed values (new table).
-- Consumer API (G3): no consumer object, table shape or column is altered, renamed, retyped or dropped. Existing tables gain new nullable
-- columns (campuses.is_primary is NOT NULL DEFAULT false, metadata-only on PG 17) and new CHECK constraints and indexes on those new columns
-- only. Website and Zoho v2 read none of them; website-api-v3 / public.website_v3_* (Decision 277, open to additions) will read them later.
-- RLS: enabled on all seven new tables with read policies for authenticated and anon. Neither role has USAGE on schemas catalogue, ref or
-- destination, so the policies grant no direct access; consumers read through the existing definer functions, as for every catalogue table.
-- Locks: deploy-on-merge applies the file in one transaction with its history row (scripts/ci/apply-migration.sh), so ADD COLUMN /
-- ADD CONSTRAINT take ACCESS EXCLUSIVE on courses, campuses and course_english_requirements until commit; VALIDATE CONSTRAINT and the
-- index builds run under that lock. The constraints are still added NOT VALID then validated (no change if the file is ever split). The
-- 5 s lock_timeout means a busy minute fails the whole change cleanly (nothing applied) instead of queueing workers behind it. Rehearsed on
-- the Pilot twice in one rolled-back transaction; measured lock window in the PR.
-- No job, setting, function or edge function is created or changed.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted.

set local lock_timeout = '5s'; -- fixed: deploy-time safety, not a pipeline control (a busy minute fails cleanly; apply again in a quiet minute)
set local statement_timeout = '60s'; -- fixed: deploy-time safety time-out, so no single statement holds the catalogue locks for long

create schema if not exists catalogue;
create schema if not exists ref;
create schema if not exists destination;

-- ----------------------------------------------------------------------------
-- 1. catalogue.courses: study_load and empty_reason_code (REQ-52, REQ-53)
-- ----------------------------------------------------------------------------
alter table catalogue.courses
  add column if not exists study_load text,
  add column if not exists study_load_source text,
  add column if not exists study_load_evidence_id uuid,
  add column if not exists empty_reason_code text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'courses_study_load_check'
      and conrelid = 'catalogue.courses'::regclass
  ) then
    alter table catalogue.courses
      add constraint courses_study_load_check
      check (study_load is null or study_load in ('full_time', 'part_time', 'both'))
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'courses_study_load_source_check'
      and conrelid = 'catalogue.courses'::regclass
  ) then
    alter table catalogue.courses
      add constraint courses_study_load_source_check
      check (
        study_load_source is null
        or study_load_source in ('register', 'provider_page', 'manual')
      )
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'courses_empty_reason_code_check'
      and conrelid = 'catalogue.courses'::regclass
  ) then
    alter table catalogue.courses
      add constraint courses_empty_reason_code_check
      check (
        empty_reason_code is null
        or empty_reason_code in (
          'not_published_by_provider',
          'not_listed_on_register',
          'online_only_no_campus',
          'pending_extraction',
          'source_unavailable'
        )
      )
      not valid;
  end if;
end $$;

alter table catalogue.courses validate constraint courses_study_load_check;
alter table catalogue.courses validate constraint courses_study_load_source_check;
alter table catalogue.courses validate constraint courses_empty_reason_code_check;

create index if not exists idx_courses_study_load
  on catalogue.courses (study_load)
  where study_load is not null;

create index if not exists idx_courses_empty_reason_code
  on catalogue.courses (empty_reason_code)
  where empty_reason_code is not null;

comment on column catalogue.courses.study_load is 'Normalized study load: full_time, part_time, or both (REQ-52).';
comment on column catalogue.courses.empty_reason_code is 'Machine-readable reason explaining why sparse fields (e.g., campus or study_mode) are null (REQ-53).';

-- ----------------------------------------------------------------------------
-- 2. catalogue.campuses: primary campus flag and provenance (REQ-75)
-- ----------------------------------------------------------------------------
alter table catalogue.campuses
  add column if not exists is_primary boolean not null default false,
  add column if not exists primary_basis text,
  add column if not exists street_address text,
  add column if not exists accepts_international boolean,
  add column if not exists source_url text,
  add column if not exists last_checked_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'campuses_primary_basis_check'
      and conrelid = 'catalogue.campuses'::regclass
  ) then
    alter table catalogue.campuses
      add constraint campuses_primary_basis_check
      check (
        primary_basis is null
        or primary_basis in (
          'cricos_head_office',
          'provider_stated',
          'highest_course_count',
          'manual'
        )
      )
      not valid;
  end if;
end $$;

alter table catalogue.campuses validate constraint campuses_primary_basis_check;

-- At most one primary campus per provider; zero while unverified
create unique index if not exists uq_campuses_one_primary_per_provider
  on catalogue.campuses (provider_id)
  where is_primary = true;

comment on column catalogue.campuses.is_primary is 'True for the single designated primary campus of a provider (REQ-75).';

-- ----------------------------------------------------------------------------
-- 3. catalogue.provider_accreditations: business school accreditations (REQ-57)
-- ----------------------------------------------------------------------------
create table if not exists catalogue.provider_accreditations (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  body_code text not null check (body_code in ('AACSB', 'EQUIS', 'AMBA')),
  accredited_unit_name text,
  status text not null default 'active'
    check (status in ('active', 'expired', 'revoked', 'under_review')),
  accredited_since date,
  expires_at date,
  source_url text not null,
  evidence_id uuid,
  content_hash text,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table catalogue.provider_accreditations is 'StudySearch API v3 (REQ-57): business school accreditations (AACSB, EQUIS, AMBA) held per provider and accredited unit, with source URL and status.';

create unique index if not exists uq_provider_accreditations_unit
  on catalogue.provider_accreditations (
    provider_id,
    body_code,
    coalesce(accredited_unit_name, '')
  );

create index if not exists idx_provider_accreditations_provider
  on catalogue.provider_accreditations (provider_id)
  where status = 'active';

alter table catalogue.provider_accreditations enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'catalogue'
      and tablename = 'provider_accreditations'
      and policyname = 'provider_accreditations_read_active'
  ) then
    create policy provider_accreditations_read_active
      on catalogue.provider_accreditations
      for select
      to authenticated, anon
      using (status = 'active');
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 4. catalogue.course_english_requirements: OET letter grades (REQ-34)
-- ----------------------------------------------------------------------------
alter table catalogue.course_english_requirements
  add column if not exists score_grade text,
  add column if not exists subtest_grades jsonb;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'course_english_requirements_score_grade_check'
      and conrelid = 'catalogue.course_english_requirements'::regclass
  ) then
    alter table catalogue.course_english_requirements
      add constraint course_english_requirements_score_grade_check
      check (score_grade is null or score_grade in ('A', 'B', 'C+', 'C'))
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'course_english_requirements_subtest_grades_object_check'
      and conrelid = 'catalogue.course_english_requirements'::regclass
  ) then
    alter table catalogue.course_english_requirements
      add constraint course_english_requirements_subtest_grades_object_check
      check (subtest_grades is null or jsonb_typeof(subtest_grades) = 'object')
      not valid;
  end if;
end $$;

alter table catalogue.course_english_requirements
  validate constraint course_english_requirements_score_grade_check;
alter table catalogue.course_english_requirements
  validate constraint course_english_requirements_subtest_grades_object_check;

create index if not exists idx_course_english_req_score_grade
  on catalogue.course_english_requirements (score_grade)
  where score_grade is not null;

comment on column catalogue.course_english_requirements.score_grade is 'Alphanumeric overall grade (A, B, C+, C) for tests such as OET (REQ-34).';
comment on column catalogue.course_english_requirements.subtest_grades is 'JSONB map of per-subtest alphanumeric grades, e.g. {"listening":"B","reading":"B","writing":"C+","speaking":"B"}.';

-- ----------------------------------------------------------------------------
-- 5. ref.grade_scale_conversions: academic entry normalisation (REQ-18/19/28)
-- ----------------------------------------------------------------------------
create table if not exists ref.grade_scale_conversions (
  id uuid primary key default gen_random_uuid(),
  country_code char(2) not null,
  qualification_code text not null,
  qualification_name text not null,
  board_or_stream text,
  scale_code text not null,
  raw_min_value numeric(8,3) not null,
  raw_max_value numeric(8,3),
  raw_grade_label text,
  normalized_0_100 numeric(5,2) not null
    check (normalized_0_100 >= 0 and normalized_0_100 <= 100),
  is_active boolean not null default true,
  source_url text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint grade_scale_conversions_raw_range_check
    check (raw_max_value is null or raw_max_value >= raw_min_value)
);

comment on table ref.grade_scale_conversions is 'StudySearch API v3 (REQ-18/19/28): maps a raw grade band of a country qualification and scale to a 0 to 100 value for academic entry normalisation.';

create unique index if not exists uq_grade_scale_conversions_key
  on ref.grade_scale_conversions (
    country_code,
    qualification_code,
    coalesce(board_or_stream, ''),
    scale_code,
    raw_min_value
  );

create index if not exists idx_grade_scale_conversions_lookup
  on ref.grade_scale_conversions (country_code, qualification_code, normalized_0_100)
  where is_active = true;

alter table ref.grade_scale_conversions enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'ref'
      and tablename = 'grade_scale_conversions'
      and policyname = 'grade_scale_conversions_read_active'
  ) then
    create policy grade_scale_conversions_read_active
      on ref.grade_scale_conversions
      for select
      to authenticated, anon
      using (is_active = true);
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 6. destination.*: governed destination editions and domain tables (REQ-65/67)
-- ----------------------------------------------------------------------------

-- 6a. destination.editions
create table if not exists destination.editions (
  id uuid primary key default gen_random_uuid(),
  country_code char(2) not null,
  domain text not null
    check (domain in ('study_rules', 'city_profiles', 'career_outcomes')),
  edition_label text not null,
  effective_from date not null,
  effective_to date,
  status text not null default 'draft'
    check (status in ('draft', 'in_review', 'published', 'superseded')),
  source_url text not null,
  source_owner text not null,
  attribution_text text not null,
  terms_status text not null default 'pending'
    check (terms_status in ('approved', 'pending', 'restricted')),
  last_checked_at timestamptz not null default now(),
  approved_by uuid,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  constraint destination_editions_effective_window_check
    check (effective_to is null or effective_to >= effective_from)
);

comment on table destination.editions is 'StudySearch API v3 (REQ-65/67): one governed edition per destination country and domain (study rules, city profiles, career outcomes), with source, attribution, terms and approval; at most one published per country and domain.';

create unique index if not exists uq_destination_editions_single_published
  on destination.editions (country_code, domain)
  where status = 'published';

create index if not exists idx_destination_editions_country_domain
  on destination.editions (country_code, domain, status);

-- 6b. destination.study_rules (visa, funds, work hours, post-study work, TAC)
create table if not exists destination.study_rules (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references destination.editions(id) on delete restrict,
  country_code char(2) not null,
  visa_subclass text not null,
  visa_name text not null,
  application_fee_amount numeric(12,2),
  fee_currency char(3) not null,
  financial_capacity_annual numeric(12,2),
  work_hours_fortnight integer,
  work_hours_notes text,
  post_study_work_years_min numeric(4,1),
  post_study_work_years_max numeric(4,1),
  processing_time_days_min integer,
  processing_time_days_max integer,
  application_channels jsonb not null default '[]'::jsonb
    check (jsonb_typeof(application_channels) = 'array'),
  concessions jsonb not null default '{}'::jsonb
    check (jsonb_typeof(concessions) = 'object'),
  admission_tests_note text,
  source_url text not null,
  last_checked_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (edition_id, country_code, visa_subclass)
);

comment on table destination.study_rules is 'StudySearch API v3 (REQ-65/67): student visa rules per destination edition: fees, financial capacity, work hours, post-study work, processing times, application channels.';

create index if not exists idx_destination_study_rules_country
  on destination.study_rules (country_code, edition_id);

-- 6c. destination.city_profiles (population, 30-year climate, living costs)
create table if not exists destination.city_profiles (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references destination.editions(id) on delete restrict,
  city_id uuid not null, -- no FK: no canonical cities table exists yet (see header, item 6)
  country_code char(2) not null,
  city_name text not null,
  subdivision_code text,
  population integer check (population is null or population >= 0),
  population_year integer,
  population_source text,
  climate_baseline jsonb not null default '{}'::jsonb
    check (jsonb_typeof(climate_baseline) = 'object'),
  living_cost jsonb not null default '{}'::jsonb
    check (jsonb_typeof(living_cost) = 'object'),
  cost_currency char(3) not null,
  source_url text not null,
  last_checked_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (edition_id, city_id)
);

comment on table destination.city_profiles is 'StudySearch API v3 (REQ-65/67): city profile per destination edition: population, climate baseline and living costs.';

create index if not exists idx_destination_city_profiles_country
  on destination.city_profiles (country_code, edition_id);

-- 6d. destination.career_outcomes (occupations, skill shortages, pay, outlook)
create table if not exists destination.career_outcomes (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references destination.editions(id) on delete restrict,
  country_code char(2) not null,
  occupation_code text not null,
  occupation_title text not null,
  study_area_code text,
  skill_shortage_status text
    check (
      skill_shortage_status is null
      or skill_shortage_status in (
        'national_shortage',
        'regional_shortage',
        'no_shortage',
        'unknown'
      )
    ),
  median_salary numeric(12,2),
  salary_currency char(3) not null,
  salary_period text not null default 'annual'
    check (salary_period in ('annual', 'weekly', 'hourly')),
  employment_rate_pct numeric(5,2)
    check (employment_rate_pct is null or (employment_rate_pct >= 0 and employment_rate_pct <= 100)),
  job_outlook_rating text,
  outlook_horizon_years integer,
  source_url text not null,
  last_checked_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (edition_id, country_code, occupation_code)
);

comment on table destination.career_outcomes is 'StudySearch API v3 (REQ-65/67): occupation outcomes per destination edition: skill shortage status, median pay, employment rate and outlook.';

create index if not exists idx_destination_career_outcomes_country
  on destination.career_outcomes (country_code, edition_id);

create index if not exists idx_destination_career_outcomes_study_area
  on destination.career_outcomes (study_area_code)
  where study_area_code is not null;

-- RLS on all destination tables; only rows of published editions are readable
alter table destination.editions enable row level security;
alter table destination.study_rules enable row level security;
alter table destination.city_profiles enable row level security;
alter table destination.career_outcomes enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'destination' and tablename = 'editions' and policyname = 'destination_editions_read_published'
  ) then
    create policy destination_editions_read_published
      on destination.editions for select to authenticated, anon
      using (status = 'published');
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'destination' and tablename = 'study_rules' and policyname = 'destination_study_rules_read_published'
  ) then
    create policy destination_study_rules_read_published
      on destination.study_rules for select to authenticated, anon
      using (
        exists (
          select 1 from destination.editions e
          where e.id = study_rules.edition_id and e.status = 'published'
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'destination' and tablename = 'city_profiles' and policyname = 'destination_city_profiles_read_published'
  ) then
    create policy destination_city_profiles_read_published
      on destination.city_profiles for select to authenticated, anon
      using (
        exists (
          select 1 from destination.editions e
          where e.id = city_profiles.edition_id and e.status = 'published'
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'destination' and tablename = 'career_outcomes' and policyname = 'destination_career_outcomes_read_published'
  ) then
    create policy destination_career_outcomes_read_published
      on destination.career_outcomes for select to authenticated, anon
      using (
        exists (
          select 1 from destination.editions e
          where e.id = career_outcomes.edition_id and e.status = 'published'
        )
      );
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 7. ref.api_field_dictionary: API v3 field dictionary and vocabularies (REQ-76)
-- ----------------------------------------------------------------------------
create table if not exists ref.api_field_dictionary (
  id uuid primary key default gen_random_uuid(),
  api_surface text not null
    check (api_surface in ('website', 'zoho', 'shared')),
  version text not null default 'v3',
  endpoint text not null,
  field_path text not null,
  data_type text not null
    check (
      data_type in (
        'string',
        'integer',
        'number',
        'boolean',
        'date',
        'timestamptz',
        'object',
        'array<string>',
        'array<object>'
      )
    ),
  is_nullable boolean not null default true,
  allowed_values jsonb
    check (allowed_values is null or jsonb_typeof(allowed_values) = 'array'),
  req_ids text[] not null default '{}',
  source_table text,
  source_column text,
  description text not null,
  example_value jsonb,
  introduced_in text not null default 'v3.0',
  deprecated_in text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (api_surface, version, endpoint, field_path)
);

comment on table ref.api_field_dictionary is 'StudySearch API v3 (REQ-76): field dictionary for the website and Zoho v3 contracts: type, nullability, allowed values, source column and requirement ids per endpoint field.';

create index if not exists idx_api_field_dictionary_surface_version
  on ref.api_field_dictionary (api_surface, version, endpoint);

alter table ref.api_field_dictionary enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'ref'
      and tablename = 'api_field_dictionary'
      and policyname = 'api_field_dictionary_read_all'
  ) then
    create policy api_field_dictionary_read_all
      on ref.api_field_dictionary
      for select
      to authenticated, anon
      using (deprecated_in is null);
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- Post-check: every new table has RLS on and a read policy; every new constraint is validated
-- ----------------------------------------------------------------------------
do $check$
declare
  v_missing text;
begin
  select string_agg(t, ', ') into v_missing
  from unnest(array[
    'catalogue.provider_accreditations', 'ref.grade_scale_conversions', 'destination.editions', 'destination.study_rules',
    'destination.city_profiles', 'destination.career_outcomes', 'ref.api_field_dictionary'
  ]) t
  where not exists (
    select 1 from pg_class c
    where c.oid = to_regclass(t) and c.relrowsecurity
      and exists (select 1 from pg_policy p where p.polrelid = c.oid and p.polcmd = 'r')
  );
  if v_missing is not null then
    raise exception 'API v3 post-check: RLS or read policy missing on %', v_missing;
  end if;

  select string_agg(k.n, ', ') into v_missing
  from unnest(array[
    'courses_study_load_check', 'courses_study_load_source_check', 'courses_empty_reason_code_check', 'campuses_primary_basis_check',
    'course_english_requirements_score_grade_check', 'course_english_requirements_subtest_grades_object_check'
  ]) k(n)
  where not exists (select 1 from pg_constraint c where c.conname = k.n and c.convalidated);
  if v_missing is not null then
    raise exception 'API v3 post-check: constraint not validated: %', v_missing;
  end if;
end $check$;
