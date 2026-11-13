-- F-SCH per-provider scholarship coverage evidence (Platform Admin S2-Scholarship directive 13 Nov 2026 14:50 §1, §6; Developer Requirements
-- v2.26 F-SCH.11). Read-only. One row per provider in the scholarship population: every classified university
-- (security.scholarship_university) plus every provider with a scholarship discovery row, a candidate page, a listing page or a scholarship.
-- Distinct provider IDs; counts are distinct candidate or scholarship IDs. Disposition is one of:
--   published | admitted_not_published | protected_hold | source_found_unprocessed | evidence_insufficient |
--   current_awards_ineligible_or_domestic | searched_none_evidenced | website_unknown | not_yet_attempted_or_vendor_failure
-- Run by .github/workflows/sch-provider-coverage-evidence.yml (psql --csv, READ ONLY); the dated CSV is evidence beside the F-SCH Execution
-- Register, not a task list.
with pop as (
  select p.id from catalogue.providers p where security.scholarship_university(p.id)
  union select provider_id from pipeline.scholarship_discovery_providers
  union select provider_id from pipeline.scholarship_page_candidates
  union select provider_id from pipeline.scholarship_listing_pages
  union select provider_id from scholarship.scholarships where provider_id is not null),
cand as (
  select k.provider_id, count(*) n,
         count(*) filter (where k.read_status in ('read', 'too_thin')) n_read,
         count(*) filter (where k.read_status is null or k.read_status in ('pending', 'queued', 'waiting_scraper', 'failed')) n_unread,
         count(*) filter (where k.admit_status = 'admitted') n_admitted,
         count(*) filter (where k.admit_status = 'rejected') n_rejected,
         min(k.next_read_at) filter (where k.read_status is distinct from 'read') next_read
    from pipeline.scholarship_page_candidates k group by 1),
rej as (
  select provider_id, string_agg(r || ' ' || n, '; ' order by n desc) reasons,
         sum(n) filter (where r in ('domestic_only', 'eligibility_domestic')) n_domestic,
         sum(n) filter (where r in ('international_not_stated')) n_intl_unknown
    from (select provider_id, r, count(*) n from pipeline.scholarship_page_candidates, unnest(admit_reasons) r where admit_status = 'rejected' group by 1, 2) x
   group by 1),
lst as (
  select provider_id, count(*) n, count(*) filter (where completed_at is not null) n_complete, count(*) filter (where status = 'failed') n_failed
    from pipeline.scholarship_listing_pages group by 1),
sch as (
  select provider_id, count(*) filter (where lifecycle_status = 'active') n_active,
         count(*) filter (where lifecycle_status = 'active' and publication_status = 'published') n_published,
         count(*) filter (where lifecycle_status = 'active' and publication_status <> 'published') n_held,
         (array_agg(source_url order by updated_at desc) filter (where lifecycle_status = 'active' and publication_status = 'published'))[1:3] sample_published
    from scholarship.scholarships group by 1),
cov as (
  select provider_id, string_agg(state || ' ' || n, '; ' order by n desc) states, min(next_recovery_at) next_recovery
    from (select provider_id, state, count(*) n, min(next_recovery_at) next_recovery_at from pipeline.scholarship_coverage_items where present group by 1, 2) y group by 1),
l4 as (
  select split_part(entity, '|', 1)::uuid provider_id, count(*) n, string_agg(distinct missing_fact, ', ') facts
    from pipeline.layer4_interventions where lane like 'sch%' and status = 'awaiting_input' group by 1),
rv as (select provider_id, count(*) n from pipeline.scholarship_ai_reviews where status = 'pending' group by 1),
fc as (select provider_id, sum(units) units from pipeline.coverage_vendor_usage where purpose like 'sch%' and at > now() - interval '30 days' group by 1),
base as (
  select p.id provider_id, coalesce(p.display_name, p.canonical_name) provider, c.iso_alpha2 country, security.scholarship_university(p.id) classified_university,
         t.code provider_type, p.website, p.publication_status provider_publication,
         d.status discovery_status, d.method discovery_method, d.url_count map_urls, d.kept_count kept_pages, d.discovered_at, d.next_discover_at,
         left(d.last_error, 160) discovery_error, security.provider_sch_search_off_v1(p.id) search_off, security.fc_sch_eligible_v1(p.id) search_eligible,
         coalesce(k.n, 0) candidates, coalesce(k.n_read, 0) candidates_read, coalesce(k.n_unread, 0) candidates_unread,
         coalesce(k.n_admitted, 0) candidates_admitted, coalesce(k.n_rejected, 0) candidates_rejected, r.reasons reject_reasons,
         coalesce(r.n_domestic, 0) n_domestic, coalesce(r.n_intl_unknown, 0) n_intl_unknown,
         coalesce(l.n, 0) listing_pages, coalesce(l.n_complete, 0) listing_complete, coalesce(l.n_failed, 0) listing_failed,
         coalesce(s.n_active, 0) scholarships_active, coalesce(s.n_published, 0) scholarships_published, coalesce(s.n_held, 0) scholarships_unpublished,
         array_to_string(s.sample_published, ' ') sample_published_sources,
         cv.states coverage_states, coalesce(i.n, 0) layer4_open, i.facts layer4_facts, coalesce(v.n, 0) ai_reviews_pending,
         coalesce(f.units, 0) firecrawl_credits_30d,
         least(d.next_discover_at, k.next_read, cv.next_recovery) next_retry
    from pop join catalogue.providers p on p.id = pop.id join ref.countries c on c.id = p.country_id
    left join ref.provider_types t on t.id = p.provider_type_id
    left join pipeline.scholarship_discovery_providers d on d.provider_id = p.id
    left join cand k on k.provider_id = p.id left join rej r on r.provider_id = p.id left join lst l on l.provider_id = p.id
    left join sch s on s.provider_id = p.id left join cov cv on cv.provider_id = p.id left join l4 i on i.provider_id = p.id
    left join rv v on v.provider_id = p.id left join fc f on f.provider_id = p.id)
select now()::date as as_of, b.*,
       case when scholarships_published > 0 then 'published'
            when scholarships_active > 0 then 'admitted_not_published'
            when layer4_open > 0 or ai_reviews_pending > 0 then 'protected_hold'
            when candidates_unread > 0 or listing_failed > 0 or (listing_pages > listing_complete) then 'source_found_unprocessed'
            when candidates > 0 and n_domestic > 0 and n_domestic >= n_intl_unknown then 'current_awards_ineligible_or_domestic'
            when candidates > 0 then 'evidence_insufficient'
            when nullif(btrim(coalesce(website, '')), '') is null then 'website_unknown'
            when discovery_status in ('mapped', 'empty') then 'searched_none_evidenced'
            else 'not_yet_attempted_or_vendor_failure' end disposition,
       case when scholarships_published > 0 then 'keep re-reading on the cadence; complete fields'
            when scholarships_active > 0 then 'complete the publishing checks (value, audience, round) from the stored page'
            when layer4_open > 0 or ai_reviews_pending > 0 then 'Layer 4: ' || coalesce(layer4_facts, 'AI review question') || ' (reviewer)'
            when candidates_unread > 0 then 'read the unread candidate pages'
            when listing_failed > 0 or listing_pages > listing_complete then 'traverse the listing pages'
            when candidates > 0 and n_domestic > 0 and n_domestic >= n_intl_unknown then 'none needed while the current awards are domestic-only; re-map on the cadence'
            when candidates > 0 then 'eligibility reader on the award pages; re-map the official scholarship section'
            when nullif(btrim(coalesce(website, '')), '') is null then 'find the official website'
            when discovery_status in ('mapped', 'empty') then 're-map on the cadence; site search for the scholarship section'
            when not search_eligible then 'not eligible for scholarship search under the current rule'
            else 'map the official website' end next_action
  from base b
 order by country, classified_university desc, provider;
