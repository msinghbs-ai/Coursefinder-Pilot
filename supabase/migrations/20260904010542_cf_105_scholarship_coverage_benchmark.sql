create table if not exists pipeline.scholarship_coverage_benchmarks (
  id uuid primary key default gen_random_uuid(),
  source_key text not null,
  benchmark_scope text not null check (benchmark_scope in ('country','provider')),
  country_code text not null,
  provider_id uuid null references catalogue.providers(id) on delete cascade,
  observed_count integer not null check (observed_count >= 0),
  source_url text not null,
  observed_at timestamptz not null default now(),
  status text not null default 'observed' check (status in ('observed','reconciled','stale','needs_review')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (source_key, benchmark_scope, country_code, provider_id, source_url, observed_at)
);

alter table pipeline.scholarship_coverage_benchmarks enable row level security;
revoke all on pipeline.scholarship_coverage_benchmarks from public, anon, authenticated;
grant select, insert, update, delete on pipeline.scholarship_coverage_benchmarks to service_role;

create index if not exists scholarship_coverage_benchmarks_provider_idx on pipeline.scholarship_coverage_benchmarks(provider_id, observed_at desc);
create index if not exists scholarship_coverage_benchmarks_country_idx on pipeline.scholarship_coverage_benchmarks(country_code, observed_at desc);

insert into pipeline.scholarship_coverage_benchmarks(source_key,benchmark_scope,country_code,provider_id,observed_count,source_url,observed_at,status,metadata)
values
('hotcourses_abroad','country','AU',null,591,'https://www.hotcoursesabroad.com/study/international-scholarships/australia/qn/cn/9/qid/catid/scholarship7.html',now(),'observed',jsonb_build_object('authority','discovery_benchmark_only')),
('hotcourses_abroad','provider','AU','de6d32b0-f91b-4dd0-a3da-a542f1aba5f2',106,'https://www.hotcoursesabroad.com/india/international-scholarships/the-university-of-melbourne/879/sprograms.html',now(),'observed',jsonb_build_object('authority','discovery_benchmark_only')),
('hotcourses_abroad','provider','AU','e47a940d-186f-4a17-bb22-2b794b73248c',55,'https://www.hotcoursesabroad.com/india/international-scholarships/the-australian-national-university/864/sprograms.html',now(),'observed',jsonb_build_object('authority','discovery_benchmark_only')),
('hotcourses_abroad','provider','AU','543b87b8-f0dd-4bc7-80d6-76252cfaabec',46,'https://www.hotcoursesabroad.com/india/international-scholarships/monash-university/72222/sprograms.html',now(),'observed',jsonb_build_object('authority','discovery_benchmark_only'));
