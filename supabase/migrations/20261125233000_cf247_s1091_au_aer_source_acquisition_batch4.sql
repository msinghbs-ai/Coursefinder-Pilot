-- CF-247 s1091 — AU AER Steps 1-2, Batch 4 (S1-RM-Design, Platform Admin 24 Nov 2026 22:55; AER-FU-04).
-- Registers three official by-country academic entry sources through the existing pipeline.entry_matrix_sources table;
-- the existing entry-matrix-read job fetches and stores them (direct HTTP first; Firecrawl only where HTTP is blocked).
-- No reader, rule, cron, setting, consumer API or admission change; 7,585 manual locks and G3 75/48 untouched.
-- Replaces: none. Retires: none.
-- Source notes (registered is not stored; evidence is confirmed after the fetch):
--   ICHM  international entry requirements page with a country and qualification table.
--   APAC  Australian Performing Arts Conservatory, International Academic Entry Requirements v4.0 (review date August 2025), PDF by country.
--   SAIBT Academic Entry Criteria v12.0 (public PDF) by country.
with rows(provider_id, url, title) as (
 values
 ('d263eab5-2ead-443f-82d1-37800b29a6b0'::uuid,'https://www.ichm.edu.au/future-students/international-students/entry-requirements','ICHM international entry requirements by country and qualification'),
 ('310f6537-ef7e-4e76-8697-30b06fa2af6c'::uuid,'https://apac.edu.au/media/q2elac5h/international-academic-entry-requirements-v2-1.pdf','APAC international academic entry requirements by country (v4.0)'),
 ('c001e5eb-bb39-4bf9-8284-ad13b7dd912f'::uuid,'https://saibt.sa.edu.au/wp-content/uploads/admissions-entry-criteria-v12.0-public.pdf','SAIBT academic entry criteria by country (v12.0)')
)
insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
select r.provider_id, r.url, r.title, 1, 'manual' from rows r
join catalogue.providers p on p.id = r.provider_id
join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU'
on conflict (provider_id, url) do nothing;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'aer', 'au_source_batch4_register', 'pipeline.entry_matrix_sources',
       jsonb_build_object('spec', 's1091', 'providers_attempted', 20, 'providers_registered', 3, 'sources_registered', 3,
         'reason', 'AER-FU-04: AU source acquisition; no extraction, admission or rule change'),
       auth.uid()
where not exists (select 1 from pipeline.admin_control_events e where e.area = 'aer' and e.action = 'au_source_batch4_register' and e.detail->>'spec' = 's1091');
