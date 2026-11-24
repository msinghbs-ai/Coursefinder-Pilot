-- CF-247 s1096 — AU AER Steps 1-2 (S1-RM-Design, Platform Admin 24 Nov 2026 23:47; AER-FU-04, Admin #1019 and #1027).
-- 1. Re-registers Kent Institute Australia's equivalences PDF. The s1094 Kent file shares version 20261126003000 with another lane's migration and never applied (Kent had no source row).
-- 2. Registers verified official documents found in returned-provider wave 1 batch 2:
--    Skills Australia Institute (international admission page and international student brochure), Ozford (undergraduate and postgraduate minimum entry pages), AIH (admission page).
-- Registration only, through pipeline.entry_matrix_sources; the existing entry-matrix-read job fetches and stores. No reader, rule, cron, setting or admission change.
-- Replaces: none. Retires: none.
with rows(provider_id, url, title) as (
 values
 ('b3d3ae78-318c-4061-b19a-a734b86c9f85'::uuid,'https://kent.edu.au/wp-content/uploads/DOC-Academic-Entry-Equivalences.pdf','Kent Institute Australia academic entry equivalences by country'),
 ('c4160a2b-7787-4be9-a772-b6f095c334c8'::uuid,'https://skillsaustralia.edu.au/?p=70','Skills Australia Institute admission entry requirements for international students'),
 ('c4160a2b-7787-4be9-a772-b6f095c334c8'::uuid,'https://skillsaustralia.edu.au/allpdfs/international-student-brochure.pdf','Skills Australia Institute international student brochure (entry requirements)'),
 ('a1193021-e436-4e0f-8591-4fef64a53476'::uuid,'https://ozford.edu.au/?p=16376','Ozford undergraduate minimum entry requirements'),
 ('a1193021-e436-4e0f-8591-4fef64a53476'::uuid,'https://ozford.edu.au/?p=22597','Ozford postgraduate entry requirements'),
 ('12924d5c-3e7d-4c99-a10f-10fc36bb244a'::uuid,'https://aih.edu.au/?p=930','AIH admission undergraduate and postgraduate entry requirements')
)
insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
select r.provider_id, r.url, r.title, 1, 'manual' from rows r
join catalogue.providers p on p.id = r.provider_id
join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU'
on conflict (provider_id, url) do nothing;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'aer', 'au_source_returned_wave1b_register', 'pipeline.entry_matrix_sources',
       jsonb_build_object('spec', 's1096', 'providers_attempted', 8, 'providers_registered', 4, 'sources_registered', 6,
         'reason', 'AER-FU-04: Kent re-registered after version clash; verified returned-provider sources; no extraction, admission or rule change'),
       auth.uid()
where not exists (select 1 from pipeline.admin_control_events e where e.area='aer' and e.action='au_source_returned_wave1b_register' and e.detail->>'spec'='s1096');
