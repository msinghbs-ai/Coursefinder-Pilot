-- CF-247 s1100 — AU AER Steps 1-2 (S1-RM-Design, Platform Admin 24 Nov 2026 23:47; AER-FU-04, Admin #1019 and #1027).
-- 1. Corrects two s1095 URLs the fetch worker found gone (HTTP 404): the WSU International College flyer (replaced by the June 2025 academic entry requirements PDF)
--    and the Ozford high school page (replaced by the page address the site currently serves).
-- 2. Registers verified official documents for returned providers: Queensland International Business Academy (entry requirements page and international students page),
--    Academia International (international entry requirements), and the WSU International College earlier flyer edition.
-- Registration only, through pipeline.entry_matrix_sources; the existing entry-matrix-read job fetches and stores. No reader, rule, cron, setting or admission change.
-- Replaces: none. Retires: none.
with rows(provider_id, url, title) as (
 values
 ('c53d394b-bd68-4437-85c8-b9d78f2f83e8'::uuid,'https://internationalcollege.westernsydney.edu.au/wp-content/uploads/Academic-entry-requirements-June-2025.pdf','WSU International College academic entry requirements by country (June 2025)'),
 ('c53d394b-bd68-4437-85c8-b9d78f2f83e8'::uuid,'https://internationalcollege.westernsydney.edu.au/wp-content/uploads/Academic-Entry-Requirements-Flyer-2104.pdf','WSU International College academic entry requirements flyer (international qualifications table)'),
 ('a1193021-e436-4e0f-8591-4fef64a53476'::uuid,'https://ozford.edu.au/high-school/entry-requirements','Ozford high school entry requirements and equivalents by country'),
 ('4972562c-c01f-4634-8f44-abe4ad16a93c'::uuid,'https://www.qiba.edu.au/?p=445','QIBA entry requirements (English and academic by course level)'),
 ('4972562c-c01f-4634-8f44-abe4ad16a93c'::uuid,'https://www.qiba.edu.au/?p=82','QIBA international students'),
 ('2ca4b4ae-eb75-4d22-a65a-14f4d02062ab'::uuid,'https://www.academia21.com/international-students/entry-requirements','Academia International entry requirements for international students')
)
insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
select r.provider_id, r.url, r.title, 1, 'manual' from rows r
join catalogue.providers p on p.id = r.provider_id
join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU'
on conflict (provider_id, url) do nothing;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'aer', 'au_source_returned_wave1c_register', 'pipeline.entry_matrix_sources',
       jsonb_build_object('spec', 's1100', 'providers_attempted', 8, 'providers_registered', 3, 'sources_registered', 6,
         'reason', 'AER-FU-04: two s1095 URLs corrected after HTTP 404; verified returned-provider sources; no extraction, admission or rule change'),
       auth.uid()
where not exists (select 1 from pipeline.admin_control_events e where e.area='aer' and e.action='au_source_returned_wave1c_register' and e.detail->>'spec'='s1100');
