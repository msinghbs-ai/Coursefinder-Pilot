-- CF-247 s1086 — AU AER Steps 1-2, Batch 3 (S1-RM-Design, Platform Admin 24 Nov 2026 22:15; AER-FU-04).
-- Registers two official academic entry sources through the existing pipeline.entry_matrix_sources table;
-- the existing entry-matrix-read job fetches and stores them (direct HTTP first; Firecrawl only where HTTP is blocked).
-- No reader, rule, cron, setting, consumer API or admission change; 7,585 manual locks and G3 75/48 untouched.
-- Replaces: none. Retires: none.
-- Source notes (registered is not stored; evidence is confirmed after the fetch):
--   TAFE International WA  tafe-admission-requirements page with "Year level equivalents by country" table.
--   CQUniversity           "Country Specific Academic Requirements, diploma and undergraduate courses" (CQU content hub);
--                          the document says its minimum scores follow 2024 entrance-exam cut-offs, so edition currency is flagged for S1-AER.
with rows(provider_id, url, title, rank) as (
 values
 ('7339c659-60a6-4839-ba65-e1f5b926bdf8'::uuid,'https://www.tafeinternational.wa.edu.au/tafe-courses/tafe-admission-requirements','TAFE International Western Australia admission requirements: year level equivalents by country',1),
 ('f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6'::uuid,'https://delivery-cqucontenthub.stylelabs.cloud/api/public/content/country-specific-academic-requirements?v=edf51706','CQUniversity country specific academic requirements, diploma and undergraduate courses',2)
)
insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
select r.provider_id, r.url, r.title, r.rank, 'manual' from rows r
join catalogue.providers p on p.id = r.provider_id
join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU'
on conflict (provider_id, url) do nothing;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'aer', 'au_source_batch3_register', 'pipeline.entry_matrix_sources',
       jsonb_build_object('spec', 's1086', 'providers_attempted', 14, 'providers_registered', 2, 'sources_registered', 2,
         'already_registered_elsewhere', jsonb_build_array('QUT diploma and foundation by-country PDFs'),
         'reason', 'AER-FU-04: AU source acquisition; no extraction, admission or rule change'),
       auth.uid()
where not exists (select 1 from pipeline.admin_control_events e where e.area = 'aer' and e.action = 'au_source_batch3_register' and e.detail->>'spec' = 's1086');
