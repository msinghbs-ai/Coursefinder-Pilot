-- Recover Monash first-party detail targets from HTML-encoded Funnelback redirect URLs.
update pipeline.layer2_scholarship_discovery_candidates c
set detail_target_url = replace(replace(replace(replace(replace(replace(
    (regexp_match(c.scholarship_url,'(?:[?&]|&amp;)url=([^&]+)'))[1],
    '%3A',':'),'%3a',':'),'%2F','/'),'%2f','/'),'%20',' '),'%2D','-')
from pipeline.sources s join catalogue.providers p on p.id=s.provider_id
where c.source_id=s.id and p.canonical_name='Monash University'
  and c.status='discovered'
  and c.scholarship_url ~* '^https://mon-search\.funnelback\.squiz\.cloud/s/redirect'
  and c.scholarship_url ~* '(?:[?&]|&amp;)url=https%3A%2F%2Fwww\.monash\.edu%2Fstudy%2Ffees-scholarships%2Fscholarships%2Ffind-a-scholarship%2F';

update pipeline.layer2_scholarship_discovery_candidates
set detail_target_url=split_part(detail_target_url,'?',1)
where status='discovered' and detail_target_url is not null;

-- Precision classifier: URL identity first; only exact/generic titles are navigation.
update pipeline.layer2_scholarship_discovery_candidates c
set classification=case
  when coalesce(rc.iso_alpha2,'')<>'AU' then 'external_or_out_of_scope'
  when lower(btrim(coalesce(c.observed_title,''))) in (
    'find a scholarship','browse scholarships','search our scholarships','scholarships','research scholarships',
    'external scholarships','coursework scholarships','fees and scholarships','current students','applications',
    'supporting documentation','scholarship conditions','scholarship guide','how to apply for and receive a scholarship',
    'all scholarship opportunities for international students','scholarships for commencing international students'
  ) then 'support_or_navigation'
  when p.canonical_name='Monash University' and c.detail_target_url ~* '^https://www\.monash\.edu/study/fees-scholarships/scholarships/find-a-scholarship/[^/?#]+/?$' then 'detail_ready'
  when p.canonical_name='Australian National University' and c.detail_target_url ~* '^https://study\.anu\.edu\.au/scholarships/find-scholarship/[^/?#]+/?$' then 'detail_ready'
  when p.canonical_name='The University of Melbourne (UniMelb)' and c.detail_target_url ~* '^https://scholarships\.unimelb\.edu\.au/awards/[^/?#]+/?$' then 'detail_ready'
  when p.canonical_name='Federation University Australia' and c.detail_target_url ~* '^https://www\.federation\.edu\.au/study/scholarships/details/international/[^/?#]+/?$' then 'detail_ready'
  when p.canonical_name='RMIT University (RMIT)' and c.detail_target_url ~* '^https://www\.rmit\.edu\.au/scholarships/international-scholarships/[^/?#]+/?$' then 'detail_ready'
  when p.canonical_name='Charles Sturt University' and c.detail_target_url ~* '^https://www\.csu\.edu\.au/scholarships/scholarships-grants/find-scholarship/international/[^/?#]+/?$' then 'detail_ready'
  when p.canonical_name='Edith Cowan University' and c.detail_target_url ~* '^https://www\.ecu\.edu\.au/scholarships/details/[^/?#]+/?$' then 'detail_ready'
  when p.canonical_name='Charles Darwin University' and c.detail_target_url ~* '^https://www\.cdu\.edu\.au/international/how-apply/scholarships/[^/?#]+/?$' then 'detail_ready'
  else 'needs_review'
end,
classification_reason=case
  when coalesce(rc.iso_alpha2,'')<>'AU' then 'non-AU provider excluded from current milestone fill'
  when lower(btrim(coalesce(c.observed_title,''))) in (
    'find a scholarship','browse scholarships','search our scholarships','scholarships','research scholarships',
    'external scholarships','coursework scholarships','fees and scholarships','current students','applications',
    'supporting documentation','scholarship conditions','scholarship guide','how to apply for and receive a scholarship',
    'all scholarship opportunities for international students','scholarships for commencing international students'
  ) then 'generic catalogue/navigation/support title'
  when c.detail_target_url is not null then 'provider-qualified first-party detail URL pattern or manual review target'
  else 'not enough deterministic evidence for automatic detail acquisition'
end,
classified_at=now()
from pipeline.sources src
join catalogue.providers p on p.id=src.provider_id
left join ref.countries rc on rc.id=p.country_id
where c.source_id=src.id and c.status='discovered';

update pipeline.layer2_scholarship_discovery_candidates
set status='rejected'
where status='discovered' and classification in ('support_or_navigation','external_or_out_of_scope');
