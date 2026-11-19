create table if not exists pipeline.scholarship_acquisition_trace (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  observed_title text not null,
  landscape_url text null,
  first_party_catalogue_url text null,
  first_party_detail_url text null,
  discovery_candidate_id uuid null references pipeline.layer2_scholarship_discovery_candidates(id) on delete set null,
  source_record_id uuid null references pipeline.scholarship_source_records(id) on delete set null,
  scholarship_id uuid null references scholarship.scholarships(id) on delete set null,
  discovery_evidence_id uuid null references pipeline.evidence_artifacts(id) on delete set null,
  verification_evidence_id uuid null references pipeline.evidence_artifacts(id) on delete set null,
  review_queue_id uuid null references workflow.review_queue(id) on delete set null,
  publication_decision_id uuid null references pipeline.layer4_publication_decisions(id) on delete set null,
  stage text not null default 'landscape_discovery' check (stage in ('landscape_discovery','first_party_verified','detail_acquired','canonical_unpublished','layer4_review','publication_decided','published','rejected','duplicate')),
  verification_status text not null default 'pending' check (verification_status in ('pending','verified_first_party','not_found','conflict','rejected','duplicate')),
  observed_at timestamptz not null default now(),
  verified_at timestamptz null,
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique(provider_id, observed_title, landscape_url)
);

alter table pipeline.scholarship_acquisition_trace enable row level security;
revoke all on pipeline.scholarship_acquisition_trace from public, anon, authenticated;
grant select, insert, update, delete on pipeline.scholarship_acquisition_trace to service_role;

create index if not exists scholarship_acquisition_trace_provider_stage_idx on pipeline.scholarship_acquisition_trace(provider_id, stage, updated_at desc);
create index if not exists scholarship_acquisition_trace_scholarship_idx on pipeline.scholarship_acquisition_trace(scholarship_id) where scholarship_id is not null;
create index if not exists scholarship_acquisition_trace_review_idx on pipeline.scholarship_acquisition_trace(review_queue_id) where review_queue_id is not null;

insert into pipeline.scholarship_acquisition_trace(provider_id, observed_title, landscape_url, first_party_detail_url, stage, verification_status, verified_at, metadata)
select p.id, v.observed_title, v.landscape_url, v.first_party_detail_url, 'first_party_verified', 'verified_first_party', now(),
       jsonb_build_object('authority','first_party','discovery_role','landscape_only','change_control_ref','CF-CHG-20260904-107')
from (values
  ('The University of Melbourne (UniMelb)','AG Whitlam International Undergraduate Scholarship','https://www.hotcoursesabroad.com/india/international-scholarships/the-university-of-melbourne/879/sprograms.html','https://scholarships.unimelb.edu.au/awards/ag-whitlam-international-undergraduate-merit-scholarship'),
  ('Australian National University','ANU International Achievement Award','https://www.hotcoursesabroad.com/india/international-scholarships/the-australian-national-university/864/sprograms.html','https://study.anu.edu.au/scholarships/find-scholarship/anu-international-achievement-award'),
  ('Monash University','Monash International Merit Scholarship','https://www.hotcoursesabroad.com/india/international-scholarships/monash-university/72222/sprograms.html','https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/international-merit-5770')
) as v(provider_name, observed_title, landscape_url, first_party_detail_url)
join catalogue.providers p on p.canonical_name = v.provider_name
on conflict (provider_id, observed_title, landscape_url) do update
set first_party_detail_url = excluded.first_party_detail_url,
    stage = excluded.stage,
    verification_status = excluded.verification_status,
    verified_at = excluded.verified_at,
    updated_at = now(),
    metadata = pipeline.scholarship_acquisition_trace.metadata || excluded.metadata;
