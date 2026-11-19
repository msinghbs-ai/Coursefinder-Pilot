alter table pipeline.layer2_scholarship_discovery_candidates
  add column if not exists detail_target_url text;

-- Resolve known Monash Funnelback redirect targets to the first-party Monash detail URL.
update pipeline.layer2_scholarship_discovery_candidates c
set detail_target_url = case
  when c.classification='detail_redirect' then
    replace(replace(replace(replace(replace(replace(
      (regexp_match(c.scholarship_url,'[?&]url=([^&]+)'))[1],
      '%3A',':'),'%3a',':'),'%2F','/'),'%2f','/'),'%20',' '),'%2D','-')
  when c.classification='detail_ready' then c.scholarship_url
  else null end
where c.status='discovered' and c.classification in ('detail_ready','detail_redirect');

-- Strip any accidental encoded/query suffix after the first-party target and reject malformed/non-http targets.
update pipeline.layer2_scholarship_discovery_candidates
set detail_target_url=split_part(detail_target_url,'?',1)
where detail_target_url is not null;

update pipeline.layer2_scholarship_discovery_candidates
set classification='needs_review',classification_reason='resolved detail target is not a valid http(s) URL',detail_target_url=null,classified_at=now()
where status='discovered' and classification in ('detail_ready','detail_redirect')
  and (detail_target_url is null or detail_target_url !~* '^https?://');

create index if not exists layer2_scholarship_candidates_detail_target_idx
  on pipeline.layer2_scholarship_discovery_candidates(detail_target_url)
  where status='discovered' and detail_target_url is not null;
