-- Reclassify all still-discovered candidates with provider-specific detail precision.
update pipeline.layer2_scholarship_discovery_candidates c
set classification=case
  when coalesce(rc.iso_alpha2,'')<>'AU' then 'external_or_out_of_scope'
  when c.detail_target_url is null then 'needs_review'
  when lower(coalesce(c.observed_title,'')) ~ '(find a scholarship|browse scholarships|search our scholarships|all scholarship opportunities|scholarship conditions|scholarship guide|research scholarships|external scholarships|coursework scholarships|fees and scholarships|how to apply|applications|definitions|current students|supporting documentation|international student scholarships$|scholarships for commencing international students$|scholarships$)' then 'support_or_navigation'
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
  when lower(coalesce(c.observed_title,'')) ~ '(find a scholarship|browse scholarships|search our scholarships|all scholarship opportunities|scholarship conditions|scholarship guide|research scholarships|external scholarships|coursework scholarships|fees and scholarships|how to apply|applications|definitions|current students|supporting documentation|international student scholarships$|scholarships for commencing international students$|scholarships$)' then 'generic catalogue/navigation/support title'
  when (p.canonical_name='Monash University' and c.detail_target_url ~* '/find-a-scholarship/[^/?#]+/?$')
    or (p.canonical_name='Australian National University' and c.detail_target_url ~* '/find-scholarship/[^/?#]+/?$')
    or (p.canonical_name='The University of Melbourne (UniMelb)' and c.detail_target_url ~* '/awards/[^/?#]+/?$')
    or (p.canonical_name='Federation University Australia' and c.detail_target_url ~* '/details/international/[^/?#]+/?$')
    or (p.canonical_name='RMIT University (RMIT)' and c.detail_target_url ~* '/international-scholarships/[^/?#]+/?$')
    or (p.canonical_name='Charles Sturt University' and c.detail_target_url ~* '/find-scholarship/international/[^/?#]+/?$')
    or (p.canonical_name='Edith Cowan University' and c.detail_target_url ~* '/scholarships/details/[^/?#]+/?$')
    or (p.canonical_name='Charles Darwin University' and c.detail_target_url ~* '/international/how-apply/scholarships/[^/?#]+/?$')
    then 'provider-qualified first-party detail URL pattern'
  else 'not enough deterministic evidence for automatic detail acquisition'
end,
classified_at=now()
from pipeline.sources src
join catalogue.providers p on p.id=src.provider_id
left join ref.countries rc on rc.id=p.country_id
where c.source_id=src.id and c.status='discovered';

-- Reject only definite current-scope exclusions/navigation noise after precision reclassification.
update pipeline.layer2_scholarship_discovery_candidates
set status='rejected'
where status='discovered' and classification in ('support_or_navigation','external_or_out_of_scope');
