create table if not exists catalogue.outcome_benchmarks (
  id uuid primary key default extensions.gen_random_uuid(),
  survey_id uuid not null references ref.outcome_surveys(id) on delete restrict,
  metric_id uuid not null references ref.outcome_metrics(id) on delete restrict,
  country_id uuid not null references ref.countries(id) on delete restrict,
  subdivision_id uuid references ref.subdivisions(id) on delete restrict,
  external_study_area_id uuid references ref.external_study_areas(id) on delete restrict,
  study_level_id uuid references ref.study_levels(id) on delete restrict,
  audience text not null default 'all' check (audience in ('all','domestic','international','mixed','unknown')),
  collection_year_from smallint not null,
  collection_year_to smallint not null,
  years_after_graduation smallint,
  metric_value numeric not null,
  response_count integer,
  source_id uuid not null references pipeline.sources(id) on delete restrict,
  evidence_id uuid references pipeline.evidence_artifacts(id) on delete restrict,
  source_geography_code text,
  source_study_area_code text,
  source_metric_code text,
  status text not null default 'current' check (status in ('current','superseded','withdrawn','review')),
  metadata jsonb not null default '{}'::jsonb,
  observed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (collection_year_to >= collection_year_from),
  check (years_after_graduation is null or years_after_graduation >= 0),
  check (response_count is null or response_count >= 0)
);

create unique index if not exists uq_outcome_benchmark_observation
on catalogue.outcome_benchmarks (
  survey_id,
  metric_id,
  country_id,
  coalesce(subdivision_id, '00000000-0000-0000-0000-000000000000'::uuid),
  coalesce(external_study_area_id, '00000000-0000-0000-0000-000000000000'::uuid),
  coalesce(study_level_id, '00000000-0000-0000-0000-000000000000'::uuid),
  audience,
  collection_year_from,
  collection_year_to,
  coalesce(years_after_graduation, -1),
  source_id
);

create index if not exists idx_outcome_benchmarks_country_period on catalogue.outcome_benchmarks(country_id, collection_year_to desc);
create index if not exists idx_outcome_benchmarks_subdivision on catalogue.outcome_benchmarks(subdivision_id) where subdivision_id is not null;
create index if not exists idx_outcome_benchmarks_metric on catalogue.outcome_benchmarks(metric_id, audience, collection_year_to desc);
create index if not exists idx_outcome_benchmarks_study_area on catalogue.outcome_benchmarks(external_study_area_id, study_level_id);
create index if not exists idx_outcome_benchmarks_source on catalogue.outcome_benchmarks(source_id);
create index if not exists idx_outcome_benchmarks_evidence on catalogue.outcome_benchmarks(evidence_id) where evidence_id is not null;

alter table catalogue.outcome_benchmarks enable row level security;
revoke all on catalogue.outcome_benchmarks from anon, authenticated;
grant all on catalogue.outcome_benchmarks to service_role;

insert into ref.outcome_surveys(code,name,source_family,description)
values
 ('statcan_psis','Postsecondary Student Information System','Statistics Canada','Institution-level postsecondary graduate and programme/student-characteristic statistics published through Statistics Canada.'),
 ('statcan_grad_longitudinal','Graduate longitudinal outcomes','Statistics Canada','Longitudinal graduate employment-income outcomes published through Statistics Canada; preserve published geography/field/credential granularity.'),
 ('on_university_graduate_survey','Ontario University Graduate Survey','Ontario MCU','Annual graduate employment outcomes survey administered to Ontario university graduates.'),
 ('on_college_kpi','Ontario College Graduate Outcomes / KPIs','Ontario MCU','Ontario public-college graduate employment, satisfaction and related KPI outcomes.'),
 ('bc_student_outcomes','BC Student Outcomes','British Columbia','Annual outcomes from former BC post-secondary students covering employment, further education and satisfaction.')
on conflict (code) do update set name=excluded.name, source_family=excluded.source_family, description=excluded.description, updated_at=now();

insert into integration.systems(code,name,system_type,base_url,status,config)
values
 ('statcan_wds','Statistics Canada Web Data Service','government_api','https://www150.statcan.gc.ca/t1/wds/rest','active',jsonb_build_object('auth','none','formats',jsonb_build_array('csv','sdmx'),'bulk_method','getFullTableDownloadCSV')),
 ('on_open_data_outcomes','Ontario Open Data - Postsecondary Outcomes','government_open_data','https://data.ontario.ca','active',jsonb_build_object('auth','none','formats',jsonb_build_array('xlsx','csv','web'))),
 ('bc_student_outcomes','BC Student Outcomes','government_open_data','https://www2.gov.bc.ca/gov/content/education-training/post-secondary-education/data-research','active',jsonb_build_object('auth','none','coverage',jsonb_build_array('employment','further_study','satisfaction')))
on conflict (code) do update set name=excluded.name, system_type=excluded.system_type, base_url=excluded.base_url, status='active', config=excluded.config, updated_at=now();

with ca as (select id country_id from ref.countries where iso_alpha2='CA'), sys as (select id,code from integration.systems where code in ('statcan_wds','on_open_data_outcomes','bc_student_outcomes'))
insert into pipeline.sources(source_type,system_id,country_id,url,label,trust_rank,status,metadata)
select 'structured_outcomes',sys.id,ca.country_id,
 case sys.code when 'statcan_wds' then 'https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=3710027801' when 'on_open_data_outcomes' then 'https://data.ontario.ca/en/dataset/ontario-university-graduate-survey' else 'https://www2.gov.bc.ca/gov/content/education-training/post-secondary-education/data-research' end,
 case sys.code when 'statcan_wds' then 'Statistics Canada PSIS / Postsecondary Graduates' when 'on_open_data_outcomes' then 'Ontario Postsecondary Graduate Outcomes' else 'BC Student Outcomes' end,
 case sys.code when 'statcan_wds' then 10 else 20 end,
 'active',
 case sys.code
   when 'statcan_wds' then jsonb_build_object('layer','2A','country','CA','pid','37100278','table','37-10-0278-01','coverage_role','national_structured_backbone','provider_mapping_required',true,'canonical_identity_write',false)
   when 'on_open_data_outcomes' then jsonb_build_object('layer','2A','country','CA','province','ON','coverage_role','provincial_provider_outcomes','provider_mapping_required',true,'canonical_identity_write',false)
   else jsonb_build_object('layer','2A','country','CA','province','BC','coverage_role','provincial_provider_outcomes','provider_mapping_required',true,'canonical_identity_write',false)
 end
from ca cross join sys
where not exists (select 1 from pipeline.sources s where s.country_id=ca.country_id and s.system_id=sys.id and s.label=case sys.code when 'statcan_wds' then 'Statistics Canada PSIS / Postsecondary Graduates' when 'on_open_data_outcomes' then 'Ontario Postsecondary Graduate Outcomes' else 'BC Student Outcomes' end);
