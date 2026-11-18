-- CF-247 28-destination schema lock, additive part (S2-Build, Platform Admin 18 Nov 2026 12:21: "Confirm/enable storage for national institutional
-- quality ratings (TEF, NZQA EER, TrustEd, KHDA, SETARA, IEQAS, FINEEC, ANVUR) and employment-by-industry series inside existing canonical tables
-- ... via additive columns/check-constraint values rather than new tables"; zero country-prefixed tables, s627; G3 75 functions / 48 relations).
--
-- What it adds (columns only; no table, no function in the consumer API; nothing dropped):
--   * catalogue.provider_accreditations: rating (the grade the body gives, for example Gold, Category 1, Outstanding) and rating_period
--     (the period or cycle it covers). A national quality rating is one row per provider and body, beside the AACSB, EQUIS and AMBA rows.
--   * destination.career_outcomes: series_kind (occupation, the default and every existing row, or industry), industry_scheme, industry_code,
--     industry_title and employment_count, so employment by industry is stored in the same table as the occupation series. An industry row must
--     name its industry; an occupation row is unchanged.
-- The value lists that need a CHECK constraint replaced (accreditation bodies including the eight rating bodies, ranking system ft, study rule
-- categories, occupation schemes OSCA and NOL, and occupation fields left empty on an industry row) go to the Platform Admin as admin paste file
-- docs/paste/PASTE-20261118-29-destination-check-constraints.sql (version 2), to be run after this migration and before Thu 01:15 AEDT.
-- Replaces: nothing.
-- Retires: nothing.

alter table catalogue.provider_accreditations add column if not exists rating text;
alter table catalogue.provider_accreditations add column if not exists rating_period text;
comment on column catalogue.provider_accreditations.rating is 'The grade a quality body gives (for example TEF Gold, NZQA EER Category 1, KHDA Outstanding); null for accreditations that have no grade (28-destination lock, 18 Nov 2026).';
comment on column catalogue.provider_accreditations.rating_period is 'The period or review cycle the rating covers, as the body states it (28-destination lock, 18 Nov 2026).';

alter table destination.career_outcomes add column if not exists series_kind text not null default 'occupation';
alter table destination.career_outcomes add column if not exists industry_scheme text;
alter table destination.career_outcomes add column if not exists industry_code text;
alter table destination.career_outcomes add column if not exists industry_title text;
alter table destination.career_outcomes add column if not exists employment_count numeric;
comment on column destination.career_outcomes.series_kind is 'occupation (an occupation series: occupation scheme, code and title) or industry (employment by industry: industry scheme, code and title) (28-destination lock, 18 Nov 2026).';
comment on column destination.career_outcomes.industry_scheme is 'Industry classification of an industry row: ANZSIC, NAICS, NACE, SIC, ISIC or a national scheme (KSIC, JSIC, MSIC, SSIC, TSIC).';
comment on column destination.career_outcomes.employment_count is 'People employed in the industry or occupation for the reference period, as the source states it.';

do $$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'destination.career_outcomes'::regclass and conname = 'career_outcomes_series_kind_check') then
    alter table destination.career_outcomes add constraint career_outcomes_series_kind_check check (series_kind in ('occupation', 'industry'));
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'destination.career_outcomes'::regclass and conname = 'career_outcomes_industry_scheme_check') then
    alter table destination.career_outcomes add constraint career_outcomes_industry_scheme_check
      check (industry_scheme is null or industry_scheme in ('ANZSIC', 'NAICS', 'NACE', 'SIC', 'ISIC', 'KSIC', 'JSIC', 'MSIC', 'SSIC', 'TSIC'));
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'destination.career_outcomes'::regclass and conname = 'career_outcomes_series_fields_check') then
    alter table destination.career_outcomes add constraint career_outcomes_series_fields_check
      check (series_kind = 'occupation' or (industry_scheme is not null and industry_code is not null and industry_title is not null));
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'destination.career_outcomes'::regclass and conname = 'career_outcomes_employment_count_check') then
    alter table destination.career_outcomes add constraint career_outcomes_employment_count_check check (employment_count is null or employment_count >= 0);
  end if;
end $$;

do $$
begin
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then -- fixed: the frozen consumer API surface
    raise exception 'post-check: the consumer API surface changed';
  end if;
  if exists (select 1 from destination.career_outcomes where series_kind <> 'occupation') then raise exception 'post-check: existing rows stay occupation series'; end if;
  if (select count(*) from information_schema.columns where (table_schema, table_name, column_name) in
        (('catalogue', 'provider_accreditations', 'rating'), ('catalogue', 'provider_accreditations', 'rating_period'), ('destination', 'career_outcomes', 'series_kind'),
         ('destination', 'career_outcomes', 'industry_scheme'), ('destination', 'career_outcomes', 'industry_code'), ('destination', 'career_outcomes', 'industry_title'),
         ('destination', 'career_outcomes', 'employment_count'))) <> 7 then -- fixed: the seven columns added here
    raise exception 'post-check: columns';
  end if;
end $$;
