create table if not exists pipeline.course_field_source (
  course_id uuid primary key,
  provider_id uuid not null,
  country_code text,
  tier text,
  intakes_src text not null,
  english_src text not null,
  fee_src text not null,
  computed_at timestamptz not null default now()
);
create index if not exists course_field_source_provider_idx on pipeline.course_field_source (provider_id);
create index if not exists course_field_source_country_tier_idx on pipeline.course_field_source (country_code, tier);
alter table pipeline.course_field_source enable row level security;
revoke all on pipeline.course_field_source from public, anon, authenticated;