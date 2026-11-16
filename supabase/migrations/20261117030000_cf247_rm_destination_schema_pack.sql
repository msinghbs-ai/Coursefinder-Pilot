-- CF-247 roadmap schema pack before the migration squash (Platform Admin 17 Nov 2026 07:39; admin DESTINATION-DATA-DESIGN.md v1.6; RM0C, RM0D,
-- RM0E, RM0F, RM1B, RM1C, RM1D, RM1H, RM1I, RM2B, RM2C, RM4A, RM4C, register readiness for RM3, RM5 and RM6). Schema and read paths only: no
-- row of destination data is loaded here, so every destination answer is an empty list until an edition is loaded, approved and published.
-- Platform Admin decision 17 Nov 2026 07:4x "Extend in place": the tables of 20261115190000 (destination.editions, study_rules, city_profiles,
-- career_outcomes), their importer and their publication guard (20261115230000) stay; nothing is duplicated and nothing is dropped.
--   1. New tables: destination.localities, locality_postcodes, locality_metrics (RM0C, RM1B, RM1I, RM4C), destination.rule_applicability
--      (RM0D), ref.registration_schemes (the register of registration and field-of-study schemes, so schemes are never mixed).
--   2. destination.study_rules gains the general rule fields (category, applicant scope, threshold, effective dates, row approval, quote and
--      evidence date); visa_subclass, visa_name and fee_currency become optional so a rule that is not a visa row fits; every row is one or
--      the other. destination.career_outcomes gains locality, occupation scheme, reference period, dataset edition, attribution and row status.
--      Its existing median_salary, salary_currency and job_outlook_rating are the earnings, currency and demand fields (not duplicated).
--   3. security.user_access_events accepts the action password_reset_sent (the constraint is replaced by its superset; no row changes).
--   4. Read path: security.destination_read_v1 and the wrappers public.website_v3_destination and public.zoho_v3_destination (API v3 action
--      "destination", Decision 277: v3 is open to additions). Only approved or published rows are returned; a study rule or career row also
--      needs its edition published (REQ-68 terms guard) and, for a rule, today inside its effective dates.
--   5. Admin: public.admin_destination_overview, admin_destination_review (Curator and above) and admin_destination_set_status (Platform Admin).
-- G1: no job. G2: three settings destination.* (page size, review list size, postcode share for a primary match; A-3 90%); no number in code.
-- G3: no consumer API object is read differently, altered, renamed or retyped (v2 untouched; the two new functions are v3 additions).
-- Replaces: nothing.
-- Retires: nothing.

set local lock_timeout = '5s'; -- fixed: deploy-time safety (the destination tables are empty)

do $$ begin
  if to_regclass('destination.editions') is null or to_regclass('destination.study_rules') is null or to_regclass('destination.career_outcomes') is null
     or to_regclass('security.user_access_events') is null or to_regprocedure('security.pipeline_num_v1(text,numeric)') is null
     or to_regprocedure('security.current_role_rank()') is null then
    raise exception 'an object this change builds on is missing';
  end if;
end $$;

-- 1a. Localities (stable id; one row per official geography unit and boundary vintage)
create table if not exists destination.localities (
  id uuid primary key default gen_random_uuid(),
  country_code char(2) not null check (country_code = upper(country_code)),
  name text not null,
  geography_type text not null,
  geography_code text not null,
  boundary_vintage text not null,
  dataset_edition text not null,
  attribution_text text not null,
  status text not null default 'draft' check (status in ('draft', 'in_review', 'approved', 'published', 'superseded', 'withdrawn')),
  status_changed_by uuid, status_changed_at timestamptz, status_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (country_code, geography_type, boundary_vintage, geography_code)
);
comment on table destination.localities is 'Destination data (RM0C): one official geography unit (for example an ABS Significant Urban Area) per boundary vintage, with a stable id, dataset edition, attribution and approval status.';

-- 1b. Postcode to locality shares (A-3: a primary match needs the share set in destination.postcode_primary_min_share; the rest go to Layer 4)
create table if not exists destination.locality_postcodes (
  id uuid primary key default gen_random_uuid(),
  locality_id uuid not null references destination.localities(id) on delete restrict,
  country_code char(2) not null check (country_code = upper(country_code)),
  postcode text not null,
  containment_share numeric(6,5) not null check (containment_share >= 0 and containment_share <= 1),
  is_primary_match boolean not null default false,
  needs_layer4_review boolean not null default false,
  boundary_vintage text not null,
  created_at timestamptz not null default now(),
  unique (locality_id, postcode, boundary_vintage),
  check (not (is_primary_match and needs_layer4_review))
);
comment on table destination.locality_postcodes is 'Destination data (RM1B): share of a postcode contained in a locality, by boundary vintage; at most one primary match per postcode, others flagged for Layer 4 review.';
create unique index if not exists uq_destination_locality_postcodes_primary
  on destination.locality_postcodes (country_code, postcode, boundary_vintage) where is_primary_match;
create index if not exists idx_destination_locality_postcodes_lookup on destination.locality_postcodes (country_code, postcode);

-- 1c. Locality metrics (population, climate, living cost), one value per key, period and edition
create table if not exists destination.locality_metrics (
  id uuid primary key default gen_random_uuid(),
  locality_id uuid not null references destination.localities(id) on delete restrict,
  metric_category text not null check (metric_category in ('population', 'climate', 'living_cost')),
  metric_key text not null,
  numeric_value numeric not null,
  unit text not null,
  currency_code char(3) check (currency_code is null or currency_code = upper(currency_code)),
  reference_period text not null,
  dataset_edition text not null,
  source_url text not null,
  attribution_text text not null,
  status text not null default 'draft' check (status in ('draft', 'in_review', 'approved', 'published', 'superseded', 'withdrawn')),
  status_changed_by uuid, status_changed_at timestamptz, status_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (locality_id, metric_key, reference_period, dataset_edition)
);
comment on table destination.locality_metrics is 'Destination data (RM1B, RM1I, RM4C): one sourced figure per locality, metric, reference period and dataset edition (population, climate normals, living costs), with attribution and approval status.';
create index if not exists idx_destination_locality_metrics_locality on destination.locality_metrics (locality_id, metric_category, status);

-- 2a. Study rules: general rule fields beside the visa columns of 20261115190000
alter table destination.study_rules
  add column if not exists state_code text,
  add column if not exists rule_category text,
  add column if not exists applicant_scope text,
  add column if not exists title text,
  add column if not exists summary text,
  add column if not exists numeric_threshold numeric,
  add column if not exists currency_code char(3),
  add column if not exists effective_from date,
  add column if not exists effective_to date,
  add column if not exists approval_status text not null default 'draft',
  add column if not exists approved_by uuid,
  add column if not exists approved_at timestamptz,
  add column if not exists status_reason text,
  add column if not exists quote_on_page text,
  add column if not exists evidence_date date;
alter table destination.study_rules alter column visa_subclass drop not null, alter column visa_name drop not null, alter column fee_currency drop not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'destination.study_rules'::regclass and conname = 'study_rules_rule_category_check') then
    alter table destination.study_rules
      add constraint study_rules_rule_category_check check (rule_category is null or rule_category in
        ('application_route', 'visa_funds', 'work_rights', 'post_study_work', 'visa_fee', 'processing_time')),
      add constraint study_rules_approval_status_check check (approval_status in ('draft', 'approved', 'superseded', 'withdrawn')),
      add constraint study_rules_effective_window_check check (effective_to is null or effective_from is null or effective_to >= effective_from),
      add constraint study_rules_currency_check check (currency_code is null or currency_code = upper(currency_code)),
      add constraint study_rules_kind_check check (visa_subclass is not null or (rule_category is not null and title is not null)),
      add constraint study_rules_visa_fields_check check (visa_subclass is null or (visa_name is not null and fee_currency is not null));
  end if;
end $$;
create index if not exists idx_destination_study_rules_category on destination.study_rules (country_id, rule_category, approval_status);

-- 2b. Rule applicability (proven or excluded, with evidence); a state has no uuid, so it is named by entity_code
create table if not exists destination.rule_applicability (
  id uuid primary key default gen_random_uuid(),
  rule_id uuid not null references destination.study_rules(id) on delete restrict,
  entity_type text not null check (entity_type in ('country', 'state', 'locality', 'provider', 'course')),
  entity_id uuid,
  entity_code text,
  applicability_status text not null check (applicability_status in ('proven', 'excluded')),
  evidence_url text not null,
  quote_on_page text,
  verified_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check (entity_id is not null or entity_code is not null)
);
comment on table destination.rule_applicability is 'Destination data (RM0D, O23, O27): where a study rule is proven to apply or is excluded (country, state, locality, provider or course), each with its evidence URL and quote.';
create unique index if not exists uq_destination_rule_applicability
  on destination.rule_applicability (rule_id, entity_type, coalesce(entity_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(entity_code, ''));
create index if not exists idx_destination_rule_applicability_entity on destination.rule_applicability (entity_type, entity_id);

-- 2c. Career outcomes: locality, scheme, period, edition, attribution and row status
alter table destination.career_outcomes
  add column if not exists locality_id uuid references destination.localities(id) on delete restrict,
  add column if not exists occupation_scheme text,
  add column if not exists reference_period text,
  add column if not exists dataset_edition text,
  add column if not exists attribution_text text,
  add column if not exists status text not null default 'draft',
  add column if not exists status_changed_by uuid,
  add column if not exists status_changed_at timestamptz,
  add column if not exists status_reason text;
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'destination.career_outcomes'::regclass and conname = 'career_outcomes_occupation_scheme_check') then
    alter table destination.career_outcomes
      add constraint career_outcomes_occupation_scheme_check check (occupation_scheme is null or occupation_scheme in ('ANZSCO', 'NOC', 'SOC')),
      add constraint career_outcomes_status_check check (status in ('draft', 'in_review', 'approved', 'published', 'superseded', 'withdrawn'));
  end if;
end $$;

alter table destination.localities enable row level security;
alter table destination.locality_postcodes enable row level security;
alter table destination.locality_metrics enable row level security;
alter table destination.rule_applicability enable row level security;

-- 1d. Register of registration and field-of-study schemes (keys are the lower-case values the catalogue already stores)
create table if not exists ref.registration_schemes (
  scheme text not null check (scheme = lower(scheme)),
  kind text not null check (kind in ('course_registration', 'provider_registration', 'field_of_study', 'work_eligibility')),
  country_code char(2) not null check (country_code = upper(country_code)),
  authority text not null,
  label text not null,
  never_mixed_with text[] not null default '{}',
  status text not null default 'active' check (status in ('active', 'planned', 'retired')),
  created_at timestamptz not null default now(),
  primary key (scheme, kind, country_code)
);
comment on table ref.registration_schemes is 'Register of registration and field-of-study schemes by country and authority (CRICOS, NZQA, DLI, PGWP, QAA, OfS, QQI, OPEID, IPEDS; ASCED, NZSCED, CIP, HECoS), with the schemes each is never mixed with. Reference only: it does not change what the catalogue stores.';
alter table ref.registration_schemes enable row level security;
insert into ref.registration_schemes(scheme, kind, country_code, authority, label, never_mixed_with, status) values
  ('cricos', 'course_registration', 'AU', 'Australian Government Department of Education', 'CRICOS course code', '{nzqa,mtcu,uk_qaa,uk_ofs,ie_qqi,us_opeid,us_ipeds}', 'active'),
  ('cricos', 'provider_registration', 'AU', 'Australian Government Department of Education', 'CRICOS provider code', '{nzqa,ircc_dli,uk_ofs,ie_qqi,us_opeid,us_ipeds}', 'active'),
  ('nzqa', 'course_registration', 'NZ', 'New Zealand Qualifications Authority', 'NZQCF qualification number', '{cricos,mtcu}', 'active'),
  ('nzqa', 'provider_registration', 'NZ', 'New Zealand Qualifications Authority', 'NZQA provider (MoE) number', '{cricos,ircc_dli}', 'active'),
  ('mtcu', 'course_registration', 'CA', 'Ontario Ministry of Colleges and Universities', 'MTCU programme code', '{cricos,nzqa,pgwp}', 'active'),
  ('ircc_dli', 'provider_registration', 'CA', 'Immigration, Refugees and Citizenship Canada', 'Designated learning institution number', '{pgwp,cricos,nzqa}', 'active'),
  ('pgwp', 'work_eligibility', 'CA', 'Immigration, Refugees and Citizenship Canada', 'Post-graduation work permit programme eligibility', '{ircc_dli,mtcu}', 'planned'),
  ('uk_qaa', 'provider_registration', 'GB', 'Quality Assurance Agency for Higher Education', 'QAA reviewed provider', '{uk_ofs}', 'planned'),
  ('uk_ofs', 'provider_registration', 'GB', 'Office for Students', 'OfS register (UKPRN)', '{uk_qaa}', 'planned'),
  ('ie_qqi', 'course_registration', 'IE', 'Quality and Qualifications Ireland', 'QQI / Irish Register of Qualifications programme', '{cricos,nzqa}', 'planned'),
  ('ie_qqi', 'provider_registration', 'IE', 'Quality and Qualifications Ireland', 'QQI provider', '{uk_ofs}', 'planned'),
  ('us_opeid', 'provider_registration', 'US', 'US Department of Education', 'OPE ID', '{us_ipeds}', 'planned'),
  ('us_ipeds', 'provider_registration', 'US', 'National Center for Education Statistics', 'IPEDS unit ID', '{us_opeid}', 'planned'),
  ('asced', 'field_of_study', 'AU', 'Australian Bureau of Statistics', 'ASCED field of education', '{nzsced,cip,hecos}', 'active'),
  ('nzsced', 'field_of_study', 'NZ', 'New Zealand Ministry of Education', 'NZSCED field of study', '{asced,cip,hecos}', 'planned'),
  ('cip', 'field_of_study', 'CA', 'Statistics Canada', 'CIP Canada instructional programme', '{asced,nzsced,hecos}', 'planned'),
  ('cip', 'field_of_study', 'US', 'National Center for Education Statistics', 'CIP instructional programme', '{asced,nzsced,hecos}', 'planned'),
  ('hecos', 'field_of_study', 'GB', 'Higher Education Statistics Agency', 'HECoS subject', '{asced,nzsced,cip}', 'planned')
on conflict do nothing;

-- 3. Admin access history: the password reset action (superset of the old list)
do $$ begin
  if pg_get_constraintdef((select c.oid from pg_constraint c where c.conrelid = 'security.user_access_events'::regclass
                                                             and c.conname = 'user_access_events_action_check')) not like '%''password_reset_sent''%' then
    alter table security.user_access_events drop constraint user_access_events_action_check;
    alter table security.user_access_events add constraint user_access_events_action_check
      check (action = any (array['user_created', 'user_invited', 'roles_replaced', 'user_disabled', 'user_enabled', 'password_reset_sent']));
  end if;
end $$;

-- G2 settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'destination.page_size_max', 'Destination API: largest page',
  'The most rows of each kind (localities, study rules, career outcomes) one call of the API v3 destination action returns.',
  'number', to_jsonb(100), 10, 500, 'rows', 1860, 'Roadmap schema pack (Platform Admin 17 Nov 2026 07:39)', 'Destination data', 'security.destination_read_v1 (API v3 action destination)'),
 ('pipeline', 'destination.review_list_max', 'Destination review: rows listed',
  'The most rows the Admin destination review list returns for one kind and status.',
  'number', to_jsonb(200), 20, 1000, 'rows', 1861, 'Roadmap schema pack (Platform Admin 17 Nov 2026 07:39)', 'Destination data', 'public.admin_destination_review'),
 ('pipeline', 'destination.postcode_primary_min_share', 'Destination: postcode share for a primary locality match',
  'A campus postcode maps to one locality only when at least this share of the postcode is contained in it; anything else is flagged for Layer 4 review (Platform Admin approval A-3, 17 Nov 2026).',
  'number', to_jsonb(0.9), 0.5, 1, 'share (0 to 1)', 1862, 'ABS source approval A-3 (Platform Admin 17 Nov 2026 07:29)', 'Destination data', 'security.destination_postcode_flags_v1 (locality postcode load)')
on conflict do nothing;

-- A-3 as one rule for every loader: (primary, needs review) for a share, from the setting
create or replace function security.destination_postcode_flags_v1(p_share numeric, out is_primary_match boolean, out needs_layer4_review boolean)
language sql stable set search_path = '' as $$
  select p_share >= security.pipeline_num_v1('destination.postcode_primary_min_share', 0.9),
         p_share < security.pipeline_num_v1('destination.postcode_primary_min_share', 0.9)
$$;
revoke all on function security.destination_postcode_flags_v1(numeric) from public, anon, authenticated;
grant execute on function security.destination_postcode_flags_v1(numeric) to service_role;

-- 4. Read path for API v3 action "destination"
create or replace function security.destination_read_v1(p_filters jsonb default '{}'::jsonb, p_page int default 1, p_page_size int default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  f jsonb := coalesce(p_filters, '{}'::jsonb);
  v_cc text := upper(nullif(btrim(coalesce(f->>'country_code', '')), ''));
  v_section text := nullif(btrim(coalesce(f->>'section', '')), '');
  v_postcode text := nullif(btrim(coalesce(f->>'postcode', '')), '');
  v_locality uuid; v_country uuid;
  v_max int := security.pipeline_num_v1('destination.page_size_max', 100)::int;
  v_size int; v_page int := greatest(coalesce(p_page, 1), 1); v_off int;
  v_loc jsonb := '[]'::jsonb; v_rules jsonb := '[]'::jsonb; v_careers jsonb := '[]'::jsonb; n_loc bigint := 0; n_rules bigint := 0; n_careers bigint := 0;
begin
  if jsonb_typeof(f) <> 'object' then return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', 'filters must be an object')); end if;
  if v_cc is not null and v_cc !~ '^[A-Z]{2}$' then return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', 'country_code must be a two-letter country code')); end if;
  if v_section is not null and v_section not in ('localities', 'study_rules', 'career_outcomes') then
    return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', 'section must be localities, study_rules or career_outcomes'));
  end if;
  if nullif(btrim(coalesce(f->>'locality_id', '')), '') is not null then
    if f->>'locality_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', 'locality_id must be a uuid'));
    end if;
    v_locality := (f->>'locality_id')::uuid;
  end if;
  v_size := least(greatest(coalesce(p_page_size, v_max), 1), v_max); v_off := (v_page - 1) * v_size;
  if v_cc is not null then select c.id into v_country from ref.countries c where c.iso_alpha2 = v_cc; end if;

  if v_section is null or v_section = 'localities' then
    with q as (
      select l.* from destination.localities l
       where l.status in ('approved', 'published') and (v_cc is null or l.country_code = v_cc) and (v_locality is null or l.id = v_locality)
         and (v_postcode is null or exists (select 1 from destination.locality_postcodes p where p.locality_id = l.id and p.postcode = v_postcode and p.is_primary_match)))
    select (select count(*) from q), coalesce((select jsonb_agg(x.j order by x.country_code, x.name, x.id) from (
      select q.country_code, q.name, q.id, jsonb_build_object('locality_id', q.id, 'country_code', q.country_code, 'name', q.name, 'geography_type', q.geography_type,
               'geography_code', q.geography_code, 'boundary_vintage', q.boundary_vintage, 'dataset_edition', q.dataset_edition, 'attribution', q.attribution_text,
               'metrics', coalesce((select jsonb_agg(jsonb_build_object('category', m.metric_category, 'key', m.metric_key, 'value', m.numeric_value, 'unit', m.unit,
                                      'currency_code', m.currency_code, 'reference_period', m.reference_period, 'dataset_edition', m.dataset_edition,
                                      'source_url', m.source_url, 'attribution', m.attribution_text) order by m.metric_category, m.metric_key, m.reference_period desc)
                                     from destination.locality_metrics m where m.locality_id = q.id and m.status in ('approved', 'published')), '[]'::jsonb)) j
        from q order by q.country_code, q.name, q.id offset v_off limit v_size) x), '[]'::jsonb)
      into n_loc, v_loc;
  end if;

  if v_section is null or v_section = 'study_rules' then
    with q as (
      select r.*, e.edition_label, e.attribution_text ed_attr, c.iso_alpha2 cc from destination.study_rules r
        join destination.editions e on e.id = r.edition_id and e.status = 'published'
        join ref.countries c on c.id = r.country_id
       where r.approval_status = 'approved' and (v_country is null or r.country_id = v_country) and (v_cc is null or v_country is not null)
         and (r.effective_from is null or r.effective_from <= current_date) and (r.effective_to is null or r.effective_to >= current_date)
         and (nullif(btrim(coalesce(f->>'rule_category', '')), '') is null or r.rule_category = f->>'rule_category'))
    select (select count(*) from q), coalesce((select jsonb_agg(x.j order by x.cc, x.k, x.id) from (
      select q.cc, coalesce(q.rule_category, 'visa') k, q.id, jsonb_build_object('rule_id', q.id, 'country_code', q.cc, 'state_code', q.state_code, 'rule_category', q.rule_category,
               'applicant_scope', q.applicant_scope, 'title', coalesce(q.title, q.visa_name), 'summary', q.summary, 'numeric_threshold', q.numeric_threshold,
               'currency_code', q.currency_code, 'effective_from', q.effective_from, 'effective_to', q.effective_to,
               'visa', case when q.visa_subclass is null then null else jsonb_build_object('subclass', q.visa_subclass, 'name', q.visa_name, 'application_fee_amount', q.application_fee_amount,
                         'fee_currency', q.fee_currency, 'financial_capacity_annual', q.financial_capacity_annual, 'work_hours_fortnight', q.work_hours_fortnight,
                         'work_hours_notes', q.work_hours_notes, 'post_study_work_years_min', q.post_study_work_years_min, 'post_study_work_years_max', q.post_study_work_years_max,
                         'processing_time_days_min', q.processing_time_days_min, 'processing_time_days_max', q.processing_time_days_max,
                         'application_channels', q.application_channels, 'concessions', q.concessions, 'admission_tests_note', q.admission_tests_note) end,
               'source_url', q.source_url, 'quote_on_page', q.quote_on_page, 'evidence_date', q.evidence_date, 'edition', q.edition_label, 'attribution', q.ed_attr,
               'applicability', coalesce((select jsonb_agg(jsonb_build_object('entity_type', a.entity_type, 'entity_id', a.entity_id, 'entity_code', a.entity_code,
                                            'status', a.applicability_status, 'evidence_url', a.evidence_url, 'quote_on_page', a.quote_on_page, 'verified_at', a.verified_at)
                                            order by a.entity_type, a.entity_code, a.entity_id)
                                           from destination.rule_applicability a where a.rule_id = q.id), '[]'::jsonb)) j
        from q order by q.cc, coalesce(q.rule_category, 'visa'), q.id offset v_off limit v_size) x), '[]'::jsonb)
      into n_rules, v_rules;
  end if;

  if v_section is null or v_section = 'career_outcomes' then
    with q as (
      select o.*, e.edition_label, e.attribution_text ed_attr, c.iso_alpha2 cc from destination.career_outcomes o
        join destination.editions e on e.id = o.edition_id and e.status = 'published'
        join ref.countries c on c.id = o.country_id
       where o.status in ('approved', 'published') and (v_country is null or o.country_id = v_country) and (v_cc is null or v_country is not null)
         and (v_locality is null or o.locality_id = v_locality))
    select (select count(*) from q), coalesce((select jsonb_agg(x.j order by x.cc, x.occupation_code, x.id) from (
      select q.cc, q.occupation_code, q.id, jsonb_build_object('outcome_id', q.id, 'country_code', q.cc, 'locality_id', q.locality_id, 'occupation_scheme', q.occupation_scheme,
               'occupation_code', q.occupation_code, 'occupation_title', q.occupation_title,
               'median_annual_earnings', case when q.salary_period = 'annual' then q.median_salary end, 'median_earnings', q.median_salary, 'earnings_period', q.salary_period,
               'currency_code', q.salary_currency, 'demand_rating', q.job_outlook_rating, 'skill_shortage_status', q.skill_shortage_status,
               'employment_rate_pct', q.employment_rate_pct, 'reference_period', q.reference_period, 'dataset_edition', coalesce(q.dataset_edition, q.edition_label),
               'source_url', q.source_url, 'attribution', coalesce(q.attribution_text, q.ed_attr)) j
        from q order by q.cc, q.occupation_code, q.id offset v_off limit v_size) x), '[]'::jsonb)
      into n_careers, v_careers;
  end if;

  return jsonb_build_object('localities', v_loc, 'study_rules', v_rules, 'career_outcomes', v_careers,
           'totals', jsonb_build_object('localities', n_loc, 'study_rules', n_rules, 'career_outcomes', n_careers),
           'page', v_page, 'page_size', v_size, 'filters', jsonb_strip_nulls(jsonb_build_object('country_code', v_cc, 'section', v_section, 'postcode', v_postcode, 'locality_id', v_locality)));
end $$;
revoke all on function security.destination_read_v1(jsonb, int, int) from public, anon, authenticated;
grant execute on function security.destination_read_v1(jsonb, int, int) to service_role;

create or replace function public.website_v3_destination(p_filters jsonb default '{}'::jsonb, p_page int default 1, p_page_size int default null)
returns jsonb language sql stable security definer set search_path = '' as $$ select security.destination_read_v1(p_filters, p_page, p_page_size) $$;
create or replace function public.zoho_v3_destination(p_filters jsonb default '{}'::jsonb, p_page int default 1, p_page_size int default null)
returns jsonb language sql stable security definer set search_path = '' as $$ select security.destination_read_v1(p_filters, p_page, p_page_size) $$;
revoke all on function public.website_v3_destination(jsonb, int, int) from public, anon, authenticated;
revoke all on function public.zoho_v3_destination(jsonb, int, int) from public, anon, authenticated;
grant execute on function public.website_v3_destination(jsonb, int, int) to service_role;
grant execute on function public.zoho_v3_destination(jsonb, int, int) to service_role;

-- 5. Admin review and approval
create or replace function public.admin_destination_overview() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'editions', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select domain || ':' || status k, count(*) n from destination.editions group by 1) s),
    'localities', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from destination.localities group by 1) s),
    'locality_postcodes', (select jsonb_build_object('rows', count(*), 'primary', count(*) filter (where is_primary_match), 'needs_layer4_review', count(*) filter (where needs_layer4_review)) from destination.locality_postcodes),
    'locality_metrics', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select metric_category || ':' || status k, count(*) n from destination.locality_metrics group by 1) s),
    'study_rules', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select coalesce(rule_category, 'visa') || ':' || approval_status k, count(*) n from destination.study_rules group by 1) s),
    'rule_applicability', (select coalesce(jsonb_object_agg(applicability_status, n), '{}'::jsonb) from (select applicability_status, count(*) n from destination.rule_applicability group by 1) s),
    'career_outcomes', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from destination.career_outcomes group by 1) s),
    'registration_schemes', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select kind || ':' || status k, count(*) n from ref.registration_schemes group by 1) s),
    'checked_at', now());
end $$;

create or replace function public.admin_destination_review(p_kind text, p_status text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_max int := security.pipeline_num_v1('destination.review_list_max', 200)::int; v jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_kind = 'locality' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v from (select * from destination.localities l where p_status is null or l.status = p_status order by l.country_code, l.name limit v_max) x;
  elsif p_kind = 'locality_metric' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v from (select m.*, l.name locality_name, l.country_code from destination.locality_metrics m join destination.localities l on l.id = m.locality_id
                                                                    where p_status is null or m.status = p_status order by l.country_code, l.name, m.metric_key limit v_max) x;
  elsif p_kind = 'locality_postcode' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v from (select p.*, l.name locality_name from destination.locality_postcodes p join destination.localities l on l.id = p.locality_id
                                                                    where p.needs_layer4_review order by p.country_code, p.postcode, p.containment_share desc limit v_max) x;
  elsif p_kind = 'study_rule' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v from (select r.*, e.edition_label, e.status edition_status, e.terms_status from destination.study_rules r join destination.editions e on e.id = r.edition_id
                                                                    where p_status is null or r.approval_status = p_status order by r.created_at desc limit v_max) x;
  elsif p_kind = 'career_outcome' then
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v from (select o.*, e.edition_label, e.status edition_status, e.terms_status from destination.career_outcomes o join destination.editions e on e.id = o.edition_id
                                                                    where p_status is null or o.status = p_status order by o.occupation_code limit v_max) x;
  else
    raise exception 'kind must be locality, locality_metric, locality_postcode, study_rule or career_outcome' using errcode = '22023';
  end if;
  return jsonb_build_object('kind', p_kind, 'status', p_status, 'limit', v_max, 'rows', v);
end $$;

create or replace function public.admin_destination_set_status(p_kind text, p_id uuid, p_status text, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_old text; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if v_uid is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed to approve or withdraw destination data' using errcode = '42501'; end if; -- fixed: approval is the Platform Admin's (REQ-68)
  if v_reason is null then raise exception 'a reason is required' using errcode = '22023'; end if;
  if p_kind = 'study_rule' then
    if p_status not in ('draft', 'approved', 'superseded', 'withdrawn') then raise exception 'status must be draft, approved, superseded or withdrawn' using errcode = '22023'; end if;
    select r.approval_status into v_old from destination.study_rules r where r.id = p_id for update;
    if not found then raise exception 'not found' using errcode = 'P0002'; end if;
    update destination.study_rules r set approval_status = p_status, status_reason = v_reason,
           approved_by = case when p_status = 'approved' then v_uid else r.approved_by end, approved_at = case when p_status = 'approved' then now() else r.approved_at end
     where r.id = p_id and r.approval_status is distinct from p_status;
  elsif p_kind in ('locality', 'locality_metric', 'career_outcome') then
    if p_status not in ('draft', 'in_review', 'approved', 'published', 'superseded', 'withdrawn') then
      raise exception 'status must be draft, in_review, approved, published, superseded or withdrawn' using errcode = '22023';
    end if;
    if p_kind = 'locality' then
      select l.status into v_old from destination.localities l where l.id = p_id for update;
      if not found then raise exception 'not found' using errcode = 'P0002'; end if;
      update destination.localities l set status = p_status, status_reason = v_reason, status_changed_by = v_uid, status_changed_at = now(), updated_at = now()
       where l.id = p_id and l.status is distinct from p_status;
    elsif p_kind = 'locality_metric' then
      select m.status into v_old from destination.locality_metrics m where m.id = p_id for update;
      if not found then raise exception 'not found' using errcode = 'P0002'; end if;
      update destination.locality_metrics m set status = p_status, status_reason = v_reason, status_changed_by = v_uid, status_changed_at = now(), updated_at = now()
       where m.id = p_id and m.status is distinct from p_status;
    else
      select o.status into v_old from destination.career_outcomes o where o.id = p_id for update;
      if not found then raise exception 'not found' using errcode = 'P0002'; end if;
      update destination.career_outcomes o set status = p_status, status_reason = v_reason, status_changed_by = v_uid, status_changed_at = now()
       where o.id = p_id and o.status is distinct from p_status;
    end if;
  else
    raise exception 'kind must be locality, locality_metric, study_rule or career_outcome' using errcode = '22023';
  end if;
  return jsonb_build_object('kind', p_kind, 'id', p_id, 'from', v_old, 'to', p_status, 'changed', v_old is distinct from p_status, 'by', v_uid);
end $$;

revoke all on function public.admin_destination_overview() from public, anon;
revoke all on function public.admin_destination_review(text, text) from public, anon;
revoke all on function public.admin_destination_set_status(text, uuid, text, text) from public, anon;
grant execute on function public.admin_destination_overview() to authenticated, service_role;
grant execute on function public.admin_destination_review(text, text) to authenticated, service_role;
grant execute on function public.admin_destination_set_status(text, uuid, text, text) to authenticated, service_role;

-- Post-check
do $$ declare v jsonb := security.destination_read_v1('{}'::jsonb, 1, null); begin
  if (select count(*) from information_schema.tables where (table_schema, table_name) in
        (('destination', 'localities'), ('destination', 'locality_postcodes'), ('destination', 'locality_metrics'), ('destination', 'rule_applicability'), ('ref', 'registration_schemes'))) <> 5 then
    raise exception 'post-check: tables';
  end if;
  if jsonb_typeof(v->'localities') <> 'array' or jsonb_typeof(v->'study_rules') <> 'array' or jsonb_typeof(v->'career_outcomes') <> 'array' then raise exception 'post-check: read shape'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'destination.%') <> 3 then raise exception 'post-check: settings'; end if;
  if (select count(*) from ref.registration_schemes) < 18 then raise exception 'post-check: schemes'; end if;
end $$;
