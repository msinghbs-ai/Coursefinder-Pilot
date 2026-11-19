alter table pipeline.layer2_scholarship_discovery_candidates
  add column if not exists classification text,
  add column if not exists classification_reason text,
  add column if not exists classified_at timestamptz;

alter table pipeline.layer2_scholarship_discovery_candidates
  drop constraint if exists layer2_scholarship_discovery_candidates_classification_check;
alter table pipeline.layer2_scholarship_discovery_candidates
  add constraint layer2_scholarship_discovery_candidates_classification_check
  check (classification is null or classification in ('detail_ready','detail_redirect','catalogue_or_filter','support_or_navigation','external_or_out_of_scope','needs_review'));

create index if not exists layer2_scholarship_candidates_classification_idx
  on pipeline.layer2_scholarship_discovery_candidates(status,classification,created_at desc);

-- Deterministic pre-acquisition classifier. Conservative: only reject obvious navigation/filter/support/out-of-scope rows.
update pipeline.layer2_scholarship_discovery_candidates c
set classification = case
  when c.scholarship_url ~* '^https://mon-search\.funnelback\.squiz\.cloud/s/redirect' and c.scholarship_url ~* 'url=https%3A%2F%2Fwww\.monash\.edu%2Fstudy%2Ffees-scholarships%2Fscholarships%2Ffind-a-scholarship%2F' then 'detail_redirect'
  when c.scholarship_url ~* '/(find-a-scholarship|find-scholarship)/[^?/#]+/?$'
    or c.scholarship_url ~* '/scholarships/details/[^?/#]+/?$'
    or c.scholarship_url ~* '/international-scholarships/[^?/#]+/?$'
    or c.scholarship_url ~* '/scholarships/[^?/#]+/?$' and coalesce(c.observed_title,'') ~* '(scholarship|award|bursary|grant)' then 'detail_ready'
  when c.scholarship_url ~* '[?&](combine|field_|query|sort|collection|form|num_ranks|student-type|study-level|category)='
    or c.scholarship_url ~* '#(find-scholarship|main)$'
    or c.scholarship_url ~* '/find-a-scholarship/?$'
    or c.scholarship_url ~* '/find-scholarship/?$' then 'catalogue_or_filter'
  when lower(coalesce(c.observed_title,'')) ~ '(find a scholarship|find a scholarship|browse scholarships|search our scholarships|supporting documentation|applications|how to apply|fees and scholarships|current students|definitions|centrelink|payments|enrolment changes|multiple scholarships|sign up now|view all faqs|skip to main|become a scholarship sponsor)'
    or c.scholarship_url ~* '/(applications|supporting-documentation|definitions|payments|enrolment-changes|multiple-scholarships|create-subscription|how-to-apply|applying-for-a-scholarship)/?$' then 'support_or_navigation'
  when c.scholarship_url !~* '^https?://([^/]*\.)?(monash\.edu|anu\.edu\.au|unimelb\.edu\.au|federation\.edu\.au|rmit\.edu\.au|csu\.edu\.au|curtin\.edu\.au|deakin\.edu\.au|ecu\.edu\.au|cdu\.edu\.au|acu\.edu\.au)/' then 'external_or_out_of_scope'
  else 'needs_review'
end,
classification_reason = case
  when c.scholarship_url ~* '^https://mon-search\.funnelback\.squiz\.cloud/s/redirect' then 'provider search redirect contains first-party scholarship detail target'
  when c.scholarship_url ~* '/(find-a-scholarship|find-scholarship)/[^?/#]+/?$' or c.scholarship_url ~* '/scholarships/details/[^?/#]+/?$' or c.scholarship_url ~* '/international-scholarships/[^?/#]+/?$' then 'first-party scholarship detail URL pattern'
  when c.scholarship_url ~* '[?&](combine|field_|query|sort|collection|form|num_ranks|student-type|study-level|category)=' or c.scholarship_url ~* '#(find-scholarship|main)$' then 'catalogue/filter/navigation URL'
  when lower(coalesce(c.observed_title,'')) ~ '(supporting documentation|how to apply|fees and scholarships|current students|definitions|centrelink|payments|enrolment changes|multiple scholarships|sign up now|view all faqs|skip to main|become a scholarship sponsor)' then 'support/navigation title'
  when c.scholarship_url !~* '^https?://([^/]*\.)?(monash\.edu|anu\.edu\.au|unimelb\.edu\.au|federation\.edu\.au|rmit\.edu\.au|csu\.edu\.au|curtin\.edu\.au|deakin\.edu\.au|ecu\.edu\.au|cdu\.edu\.au|acu\.edu\.au)/' then 'external domain requires separate authority qualification'
  else 'not enough deterministic evidence to auto-fire'
end,
classified_at=now()
where c.status='discovered';

-- Reject only deterministic non-detail noise. needs_review/detail_* remain available for operator/reconciliation.
update pipeline.layer2_scholarship_discovery_candidates
set status='rejected'
where status='discovered' and classification in ('catalogue_or_filter','support_or_navigation','external_or_out_of_scope');

create or replace view pipeline.scholarship_candidate_classification_stats as
select s.provider_id,p.canonical_name as provider_name,
  count(*) as candidate_total,
  count(*) filter(where c.status='discovered' and c.classification in ('detail_ready','detail_redirect')) as detail_ready_total,
  count(*) filter(where c.status='discovered' and c.classification='needs_review') as needs_review_total,
  count(*) filter(where c.status='rejected') as rejected_total,
  count(*) filter(where c.status='acquired') as acquired_total,
  max(c.classified_at) as last_classified_at
from pipeline.layer2_scholarship_discovery_candidates c
join pipeline.sources s on s.id=c.source_id
join catalogue.providers p on p.id=s.provider_id
group by s.provider_id,p.canonical_name;

revoke all on pipeline.scholarship_candidate_classification_stats from public,anon,authenticated;
grant select on pipeline.scholarship_candidate_classification_stats to service_role;
