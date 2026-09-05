-- CF-191 — HTML-entity-aware semantic terminal guard + stricter verified-detail reconciliation view.
create or replace function pipeline.scholarship_candidate_semantic_terminal_guard()
returns trigger language plpgsql security definer set search_path='pg_catalog','pipeline'
as $$
declare
  v_title text:=lower(trim(replace(replace(replace(coalesce(new.observed_title,''),'&amp;','&'),'&#x2019;','’'),'&#x27;','''')));
  v_url text:=lower(coalesce(nullif(new.detail_target_url,''),nullif(new.scholarship_url,''),''));
begin
  if v_title ~ '^(search|about us|learn more|scholarships? & grants|academic scholarships|external scholarships|scholarships and fees|financial aid for international students|domestic student scholarships|prestigious.*scholarships|home country sponsored scholarships)$'
     or v_url ~ '/search\.html([?#].*)?$' or v_url ~ '/about-us(\.html)?([?#].*)?$' or v_url ~ '/scholarships/domestic/?([?#].*)?$' or v_url ~ '/home-country-sponsored-scholarships/?([?#].*)?$' then
    new.classification:='support_or_navigation'; new.classification_reason:='CF-191 semantic terminal guard: navigation, collection, domestic or support page is not an individual international Scholarship'; new.classified_at:=now();
  elsif v_title ~ '^(scholarships?|scholarships? & grants|scholarships? for international students|international scholarships?)$' or v_url ~ '/scholarships/?([?#].*)?$' then
    new.classification:='catalogue_or_filter'; new.classification_reason:='CF-191 semantic terminal guard: Scholarship catalogue root retained as Evidence only'; new.classified_at:=now();
  end if;
  return new;
end $$;
update pipeline.layer2_scholarship_discovery_candidates set classification=classification where status='discovered';
update pipeline.scholarship_source_records set status='unmapped',error_text='CF-191 generic/navigation/support page retained as Evidence; individual Scholarship reconciliation required' where status='captured' and lower(replace(coalesce(payload->>'name',''),'&amp;','&')) ~ '^(about us|academic scholarships|external scholarships|scholarships and fees|financial aid for international students|domestic student scholarships|scholarships & grants|prestigious.*scholarships|home country sponsored scholarships)$';

create or replace view pipeline.scholarship_verified_detail_reconciliation_candidates as
with base as (
 select sr.id source_record_id,sr.source_id,src.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,c.iso_alpha2::text country_code,sr.evidence_id,sr.source_record_url,scholarship.normalise_first_party_url(sr.source_record_url) normalised_url,sr.payload,sr.status,sr.observed_at,sr.created_at,nullif(trim(sr.payload->>'name'),'') observed_name,scholarship.normalise_title(sr.payload->>'name') normalised_title,coalesce(nullif(sr.payload->>'confidence','')::numeric,0) confidence,row_number() over(partition by src.provider_id,scholarship.normalise_first_party_url(sr.source_record_url) order by sr.observed_at desc nulls last,sr.created_at desc,sr.id desc) url_recency_rank
 from pipeline.scholarship_source_records sr join pipeline.sources src on src.id=sr.source_id join catalogue.providers p on p.id=src.provider_id join ref.countries c on c.id=p.country_id where src.provider_id is not null and sr.evidence_id is not null and sr.status in('captured','applied')
), classified as (
 select b.*,case
  when lower(replace(coalesce(b.observed_name,''),'&amp;','&')) ~ '^(about us|academic scholarships|external scholarships|scholarships and fees|financial aid for international students|domestic student scholarships|scholarships & grants|prestigious.*scholarships|home country sponsored scholarships)$' then 'generic_or_navigation_title'
  when b.status='applied' then 'already_applied'
  when b.url_recency_rank>1 then 'duplicate_source'
  when coalesce(b.payload->>'identifier_scheme','')<>'first_party_detail_url' then 'not_first_party_detail'
  when lower(coalesce(b.payload->>'audience',''))<>'international' then 'not_international'
  when b.confidence<0.8 then 'low_confidence'
  when b.normalised_url is null or b.normalised_url !~ '^https?://' then 'invalid_url'
  when b.source_record_url ~* '[?&](query|collection|form|num_ranks|f\.)=' or b.source_record_url ~ '#!/' then 'catalogue_or_filter'
  when b.normalised_url ~* '/(scholarships|international-scholarships|global-scholarships-and-fellowships|scholarships-for-international-students)$' then 'catalogue_or_filter'
  when b.observed_name is null or length(b.observed_name)<8 then 'generic_or_navigation_title'
  when b.observed_name ~* '^(eligibility|faq|guidelines?|menu|go to top|skip to main content|find a scholarship|scholarships? for international students|international student scholarships|all scholarship opportunities for international students|global curtin scholarships|international scholarship detail|external scholarship opportunities|internal scholarship opportunities|government-funded scholarships|scholarships for commencing international students)$' then 'generic_or_navigation_title'
  when b.observed_name ~* 'is blocked$' then 'generic_or_navigation_title'
  else 'ready' end reconciliation_state from base b
) select * from classified;
revoke all on pipeline.scholarship_verified_detail_reconciliation_candidates from public,anon,authenticated;
grant select on pipeline.scholarship_verified_detail_reconciliation_candidates to service_role;
