-- M1-L1-AU-CRICOS-FACTS
-- Preserve exact CRICOS Course identity while adding time-scoped regulatory observations.

alter table catalogue.course_fees
  add column if not exists source_snapshot_at timestamptz;

create index if not exists course_fees_source_snapshot_idx
  on catalogue.course_fees(source_id, source_snapshot_at)
  where source_id is not null;

comment on column catalogue.course_fees.source_snapshot_at is
  'Timestamp/version of the source snapshot that asserted this fee observation. Does not imply a fee year.';

create table if not exists catalogue.course_regulatory_observations (
  id uuid primary key default extensions.gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  scheme text not null,
  registration_code text not null,
  vet_national_code text,
  dual_qualification boolean,
  foundation_studies boolean,
  work_component boolean,
  work_component_hours_per_week numeric(12,2),
  work_component_weeks numeric(12,2),
  work_component_total_hours numeric(14,2),
  course_language text,
  source_id uuid not null references pipeline.sources(id) on delete restrict,
  evidence_id uuid references pipeline.evidence_artifacts(id) on delete restrict,
  source_snapshot_at timestamptz not null,
  content_hash text not null,
  status text not null default 'current'
    check (status in ('current','superseded','withdrawn')),
  valid_from timestamptz,
  valid_to timestamptz,
  observed_at timestamptz not null default now(),
  last_verified_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint course_regulatory_observations_snapshot_uq
    unique (course_id, source_id, scheme, registration_code, source_snapshot_at),
  constraint course_regulatory_observations_valid_range_ck
    check (valid_to is null or valid_from is null or valid_to >= valid_from)
);

create index if not exists course_regulatory_observations_current_idx
  on catalogue.course_regulatory_observations(course_id, source_id, scheme, status);
create index if not exists course_regulatory_observations_snapshot_idx
  on catalogue.course_regulatory_observations(source_id, source_snapshot_at);
create index if not exists course_regulatory_observations_evidence_idx
  on catalogue.course_regulatory_observations(evidence_id);

alter table catalogue.course_regulatory_observations enable row level security;

comment on table catalogue.course_regulatory_observations is
  'Time-scoped regulatory course facts asserted by an authoritative registration source. Rows preserve source snapshot and evidence; they do not redefine canonical Course identity.';
comment on column catalogue.course_regulatory_observations.vet_national_code is
  'VET National Code exactly as asserted by the regulatory source. Retained as an observation because it is not unique per Provider/Course identity in current CRICOS data.';
comment on column catalogue.course_regulatory_observations.course_language is
  'Course language exactly as asserted by the regulatory source; source vocabulary is preserved.';
comment on column catalogue.course_regulatory_observations.source_snapshot_at is
  'Source resource last-modified/version timestamp used for replay identity and observation history.';

create or replace function public.svc_layer1_au_cricos_facts_stats()
returns jsonb
language sql
stable
security definer
set search_path = public, catalogue, ref, pipeline
as $function$
  select jsonb_build_object(
    'providers',(
      select count(distinct p.id)
      from catalogue.providers p
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU'
    ),
    'courses',(
      select count(*)
      from catalogue.courses c
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and c.lifecycle_status='active'
    ),
    'current_regulatory_fact_rows',(
      select count(*)
      from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current'
    ),
    'fact_courses',(
      select count(distinct o.course_id)
      from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current'
    ),
    'with_vet_national_code',(
      select count(*) from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current' and o.vet_national_code is not null
    ),
    'with_dual_qualification',(
      select count(*) from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current' and o.dual_qualification is not null
    ),
    'with_foundation_studies',(
      select count(*) from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current' and o.foundation_studies is not null
    ),
    'with_work_component',(
      select count(*) from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current' and o.work_component is not null
    ),
    'with_work_hours_per_week',(
      select count(*) from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current' and o.work_component_hours_per_week is not null
    ),
    'with_work_weeks',(
      select count(*) from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current' and o.work_component_weeks is not null
    ),
    'with_work_total_hours',(
      select count(*) from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current' and o.work_component_total_hours is not null
    ),
    'with_course_language',(
      select count(*) from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current' and o.course_language is not null
    ),
    'active_fee_rows',(
      select count(*) from catalogue.course_fees f
      join catalogue.courses c on c.id=f.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and f.status='active' and f.basis='registered_total_course'
    ),
    'with_cricos_registered_tuition',(
      select count(distinct f.course_id) from catalogue.course_fees f
      join catalogue.courses c on c.id=f.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and f.status='active' and f.basis='registered_total_course' and f.fee_type='tuition'
    ),
    'with_cricos_registered_non_tuition',(
      select count(distinct f.course_id) from catalogue.course_fees f
      join catalogue.courses c on c.id=f.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and f.status='active' and f.basis='registered_total_course' and f.fee_type='non_tuition'
    ),
    'with_cricos_estimated_total_cost',(
      select count(distinct f.course_id) from catalogue.course_fees f
      join catalogue.courses c on c.id=f.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and f.status='active' and f.basis='registered_total_course' and f.fee_type='estimated_total_course_cost'
    ),
    'with_current_provider_fee',(
      select count(distinct f.course_id) from catalogue.course_fees f
      join catalogue.courses c on c.id=f.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and f.status='active' and coalesce(f.basis,'') <> 'registered_total_course' and f.fee_year is not null
    )
  );
$function$;

revoke all on function public.svc_layer1_au_cricos_facts_stats() from public;
revoke all on function public.svc_layer1_au_cricos_facts_stats() from anon;
revoke all on function public.svc_layer1_au_cricos_facts_stats() from authenticated;
grant execute on function public.svc_layer1_au_cricos_facts_stats() to service_role;
