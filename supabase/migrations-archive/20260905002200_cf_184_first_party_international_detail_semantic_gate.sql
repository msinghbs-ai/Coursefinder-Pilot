-- CF-184 — first-party + Scholarship-semantic gate for international detail acquisition.
with x as (
 select c.id,c.observed_title,c.scholarship_url,c.detail_target_url,s.url catalogue_url,s.metadata,
        lower(coalesce(substring(coalesce(c.detail_target_url,c.scholarship_url) from '^https?://([^/]+)'),'') ) target_host,
        lower(coalesce(substring(s.url from '^https?://([^/]+)'),'') ) catalogue_host,
        lower(coalesce(c.observed_title,'')) title_l,
        lower(coalesce(c.detail_target_url,c.scholarship_url,'')) url_l
 from pipeline.layer2_scholarship_discovery_candidates c join pipeline.sources s on s.id=c.source_id
 where c.status='discovered' and (coalesce(s.metadata->>'change_control_ref','')='CF-182' or s.source_type='scholarship_catalogue')
), classified as (
 select *,
   (target_host<>'' and catalogue_host<>'' and (target_host=catalogue_host or target_host like '%.'||catalogue_host or catalogue_host like '%.'||target_host)) same_first_party_host,
   (title_l ~ '(scholarship|scholarships|award|awards|grant|grants|bursar|fellowship|fellowships)' or url_l ~ '(scholarship|award|grant|bursar|fellowship)') scholarship_semantic,
   (title_l ~ '^(skip to|menu$|home$|apply$|contact|financial aid|student loans?|sponsor|fees? and|how to apply|international students?$|scholarships?$)' or title_l ~ '(student loan|financial aid|sponsor students|study loan)') support_semantic,
   (scholarship.normalise_first_party_url(coalesce(detail_target_url,scholarship_url))=scholarship.normalise_first_party_url(catalogue_url)) same_as_catalogue
 from x
)
update pipeline.layer2_scholarship_discovery_candidates c
set classification=case
      when not k.same_first_party_host then 'external_or_out_of_scope'
      when k.same_as_catalogue then 'catalogue_or_filter'
      when k.support_semantic then 'support_or_navigation'
      when k.scholarship_semantic and coalesce(k.metadata->>'audience','')='international' then 'detail_ready'
      when k.scholarship_semantic and k.title_l ~ '(international|overseas|global|asean|india|indonesia|vietnam|malaysia|singapore|thailand|china|pakistan|bangladesh|sri lanka|nepal|africa|latin america|middle east)' then 'detail_ready'
      else 'needs_review' end,
    classification_reason=case
      when not k.same_first_party_host then 'CF-184 external domain; not a first-party university Scholarship detail'
      when k.same_as_catalogue then 'CF-184 catalogue root retained as catalogue Evidence'
      when k.support_semantic then 'CF-184 support/finance/navigation page; not an individual Scholarship'
      when k.scholarship_semantic and coalesce(k.metadata->>'audience','')='international' then 'CF-184 first-party Scholarship semantic from qualified international catalogue'
      when k.scholarship_semantic then 'CF-184 first-party Scholarship semantic with explicit international cue'
      else 'CF-184 first-party page lacks individual Scholarship semantics; review required' end,
    classified_at=now()
from classified k where c.id=k.id;

comment on column pipeline.layer2_scholarship_discovery_candidates.classification is 'Automatic Scholarship detail firing requires status=discovered plus first-party domain, individual Scholarship semantics and international qualification. External, catalogue/filter and support/navigation classes are terminal automatic exclusions.';