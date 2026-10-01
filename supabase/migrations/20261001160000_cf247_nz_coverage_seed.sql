-- CF-247 (Platform Admin, 1 Oct 2026 16:01 AEST: "Start parallel jobs for nz asap"). New Zealand's 287 providers with
-- active courses (6,475 courses) were never added to the course-page discovery queue, so nothing had started for NZ.
-- This adds every active NZ provider with active courses: those with a website as 'pending' (the existing
-- coverage-discover job maps their sites, coverage-bind matches pages to courses by title, coverage-read stores the
-- pages and their candidate values), the rest as 'no_website'.
-- Nothing is admitted to the catalogue for NZ by this change: direct admission and the Layer 3 tuition hand-off both
-- require a CRICOS code on the page, which NZ pages do not carry. NZ admission (NZQA title identity, NZD currency) is a
-- separate, reviewed change. Idempotent: providers already in the queue are left as they are.

insert into pipeline.coverage_provider_discovery(provider_id, website, status, attempts, updated_at)
select p.id, nullif(btrim(p.website), ''), case when nullif(btrim(p.website), '') is null then 'no_website' else 'pending' end, 0, now()
  from catalogue.providers p join ref.countries k on k.id = p.country_id
 where k.iso_alpha2 = 'NZ'
   and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
   and not exists (select 1 from pipeline.coverage_provider_discovery d where d.provider_id = p.id);
