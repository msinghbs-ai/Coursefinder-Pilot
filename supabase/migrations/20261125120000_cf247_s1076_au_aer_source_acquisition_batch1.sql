-- CF-247 s1076 — AU AER Steps 1-2, Batch 1 (S1-RM-Design, Platform Admin 24 Nov 2026 20:05; Admin #966, AER-FU-04).
-- Registers official academic entry sources found for the first named AU providers; the existing
-- entry-matrix-read job fetches and stores them (direct HTTP first; Firecrawl only where HTTP is blocked,
-- Platform Admin 24 Nov 20:12). No reader, rule, cron, setting or admission change.
-- Guards: AU AER Steps 1-2 only; 7,585 manual locks and G3 75/48 untouched; no new cron; existing sources kept.
-- Replaces: none. Retires: none.
-- Source notes (a registered address is not a completed Step 2; evidence is confirmed after the fetch):
--   Newcastle  2027 International Prospectus, Academic entry requirements section (printed by country).
--   Deakin     2027 International Course Guide (PDF) and the stored "admission requirements table" page.
--   ECU        Secondary school results (country-specific minimum results, undergraduate).
--   Bond       College Foundation Program academic entry (country table; foundation level only).
--   Melbourne Polytechnic  overseas secondary qualification equivalents by country (qualification list, no scores).
--   JMC        Entry requirements by country 2025 v2 (PDF; 2025 edition, currency to be confirmed).
--   ICMS       International undergraduate requirements by country (page table).
with rows(provider_id, url, title) as (
 values
 ('1822b40a-8b13-44dc-8c37-106ae31bb447'::uuid,'https://www.newcastle.edu.au/__data/assets/pdf_file/0020/1102565/2025-1079-International-Prospectus-2027-ROW_WEB-2.pdf','University of Newcastle International Prospectus 2027: academic entry requirements by country'),
 ('c5c5d225-3d4c-4e41-8275-78eddd261073'::uuid,'https://www.deakin.edu.au/__data/assets/pdf_file/0034/274669/deakin-international-course-guide.pdf','Deakin 2027 International Course Guide: academic admission requirements'),
 ('c5c5d225-3d4c-4e41-8275-78eddd261073'::uuid,'https://www.deakin.edu.au/courses/how-to-apply/international-students','Deakin international students: admission requirements table'),
 ('fac03540-a412-4c76-a5ab-cd338d7760db'::uuid,'https://www.ecu.edu.au/future-students/course-entry/secondary-school-results','ECU secondary school results required by country (undergraduate)'),
 ('739948f6-6338-4ee9-8d0c-a8c8e953c29d'::uuid,'https://bond.edu.au/program/bond-college-foundation-program/bond-university-college-foundation-program-academic-entry','Bond University College Foundation Program academic entry by country (foundation level only)'),
 ('91491287-ab6a-46bd-9723-a2284a36717a'::uuid,'https://www.melbournepolytechnic.edu.au/students/international-students/how-to-apply-as-an-international-student/australian-equivalencies-for-international-students/','Melbourne Polytechnic overseas secondary qualifications equivalent to Year 12, by country'),
 ('8d77204e-d6a1-4bf0-ba9b-3df2310bda33'::uuid,'https://www.jmcacademy.edu.au/media/d3edp3ui/entry-requirements-by-country-2025.pdf','JMC Academy entry requirements by country 2025 v2 (edition currency to confirm)'),
 ('435ca964-67a5-483c-bc8f-9d5ab059c0c2'::uuid,'https://www.icms.edu.au/future-students/application-information/admission-information-2/undergraduate-requirements/','ICMS international undergraduate academic requirement by country')
)
insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
select r.provider_id, r.url, r.title, 2, 'manual' from rows r
join catalogue.providers p on p.id = r.provider_id
join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU'
on conflict (provider_id, url) do nothing;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'aer', 'au_source_batch1_register', 'pipeline.entry_matrix_sources',
       jsonb_build_object('spec', 's1076', 'providers_attempted', 13, 'providers_registered', 7, 'sources_registered', 8,
         'held', jsonb_build_array('Torrens: course-level criteria only','UNE: country list address not exposed','CQU: country document address not exposed','UniSQ: interactive country selector','SAE: no AU entry page beyond the registered one','Sydney Metro College: course-level criteria only'),
         'reason', 'Admin #966 / AER-FU-04: AU source acquisition; no extraction, admission or rule change'),
       auth.uid()
where not exists (select 1 from pipeline.admin_control_events e where e.area = 'aer' and e.action = 'au_source_batch1_register' and e.detail->>'spec' = 's1076');
