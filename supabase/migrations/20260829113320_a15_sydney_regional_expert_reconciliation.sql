-- A15 final contact-quality reconciliation.
-- The v1.3.0 structured extractor correctly reacquired these four first-party
-- Sydney regional experts after the earlier pre-heading parser rows were rejected.
-- Record the accepted semantics explicitly so later discovery cannot inherit an
-- ambiguous rejected disposition.

with expected(full_name,job_title,territory_text,work_email) as (
  values
    ('Chris Lawrance','Regional Manager','Americas and Europe','chris.lawrance@sydney.edu.au'),
    ('Nishant Jadhav','Senior Regional Manager','Central Asia, South Asia, Middle East and Africa','nishant.jadhav@sydney.edu.au'),
    ('Sean Lee','Senior Regional Manager','Asia (excluding China, Hong Kong and Macau)','sean.lee@sydney.edu.au'),
    ('Sherrie Huan','Senior Regional Manager','China, Hong Kong and Macau','sherrie.huan@sydney.edu.au')
)
update pipeline.provider_contact_observations o set
  full_name=e.full_name,
  job_title=e.job_title,
  team_name='International Recruitment',
  territory_text=e.territory_text,
  work_email=e.work_email,
  source_url='https://www.sydney.edu.au/study/applying/how-to-apply/international-students/contact-our-regional-experts.html',
  verification_state='current',
  is_current=true,
  valid_to=null,
  metadata=(o.metadata-'a15_quality_disposition')||jsonb_build_object(
    'a15_prior_quality_disposition',o.metadata->>'a15_quality_disposition',
    'a15_quality_reconciliation','sydney_first_party_regional_experts',
    'a15_quality_review_at',now(),
    'a15_reconciliation_reason','structured regional-expert extraction with institutional email and governed territory'
  ),
  updated_at=now()
from expected e
join catalogue.providers p on lower(p.canonical_name)='the university of sydney'
where o.provider_id=p.id
  and o.source_class='first_party'
  and lower(coalesce(o.full_name,''))=lower(e.full_name)
  and lower(coalesce(o.work_email,''))=lower(e.work_email);
