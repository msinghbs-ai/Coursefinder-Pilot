CREATE OR REPLACE FUNCTION security.scholarship_provider_coverage_refresh_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 F-SCH (13 Nov 2026): the same reading as scripts/export/sch-provider-coverage-evidence.sql, kept as a snapshot for the Coverage screen
-- (the university test runs once per provider; about 70 s for all providers, hourly, after classification)
declare v_n int;
begin
  delete from pipeline.scholarship_provider_coverage;
  insert into pipeline.scholarship_provider_coverage (provider_id, provider, country, classified_university, provider_type, website, provider_publication,
         discovery_status, discovery_method, map_urls, kept_pages, discovered_at, next_discover_at, discovery_error, search_off, search_eligible,
         candidates, candidates_read, candidates_unread, candidates_admitted, candidates_rejected, reject_reasons, n_domestic, n_intl_unknown,
         listing_pages, listing_complete, listing_failed, scholarships_active, scholarships_published, scholarships_unpublished, sample_published_sources,
         coverage_states, layer4_open, layer4_facts, ai_reviews_pending, firecrawl_credits_30d, next_retry, disposition, next_action)
  select provider_id, provider, country, classified_university, provider_type, website, provider_publication,
         discovery_status, discovery_method, map_urls, kept_pages, discovered_at, next_discover_at, discovery_error, search_off, search_eligible,
         candidates, candidates_read, candidates_unread, candidates_admitted, candidates_rejected, reject_reasons, n_domestic, n_intl_unknown,
         listing_pages, listing_complete, listing_failed, scholarships_active, scholarships_published, scholarships_unpublished, sample_published_sources,
         coverage_states, layer4_open, layer4_facts, ai_reviews_pending, firecrawl_credits_30d, next_retry, disposition, next_action
    from (
with univ as materialized (select p.id from catalogue.providers p where security.scholarship_university(p.id)),
pop as (
  select id from univ
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
  select p.id provider_id, coalesce(p.display_name, p.canonical_name) provider, c.iso_alpha2 country, (p.id in (select u.id from univ u)) classified_university,
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
select b.*,
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
    ) z;
  get diagnostics v_n = row_count;
  return v_n;
end $function$
