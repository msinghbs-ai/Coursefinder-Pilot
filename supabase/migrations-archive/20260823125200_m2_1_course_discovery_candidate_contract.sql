-- Live migration: m2_1_course_discovery_candidate_contract
create table if not exists pipeline.layer2_course_discovery_candidates (
 id uuid primary key default gen_random_uuid(),
 trial_course_id uuid references pipeline.layer2_completeness_trial_courses(id) on delete cascade,
 course_id uuid not null references catalogue.courses(id),
 source_profile_version_id uuid references pipeline.layer2_source_profile_versions(id),
 provider_attempt_id uuid references pipeline.layer2_provider_attempts(id),
 evidence_id uuid references pipeline.evidence_artifacts(id),
 discovered_url text,
 discovered_title text,
 discovered_regulatory_code text,
 match_score numeric check(match_score is null or (match_score>=0 and match_score<=1)),
 match_basis jsonb not null default '{}'::jsonb,
 status text not null check(status in ('exact_match','likely_match','ambiguous','identity_mismatch','current_page_not_found','candidate')),
 selected boolean not null default false,
 blocker text,
 created_at timestamptz not null default now()
);
create index if not exists idx_l2_course_discovery_course on pipeline.layer2_course_discovery_candidates(course_id,created_at desc);
create index if not exists idx_l2_course_discovery_trial on pipeline.layer2_course_discovery_candidates(trial_course_id,status,match_score desc);
alter table pipeline.layer2_course_discovery_candidates enable row level security;
revoke all on pipeline.layer2_course_discovery_candidates from anon,authenticated;
grant select,insert,update,delete on pipeline.layer2_course_discovery_candidates to service_role;
