-- CF-247 s1095 — AU AER Steps 1-2, returned-provider wave 1 (S1-RM-Design, Platform Admin 24 Nov 2026 23:47; AER-FU-04, Admin #1019 and #1027).
-- Registers deeper official academic entry documents for providers whose stored overview page held no country table:
--   Western Sydney University International College (flyer PDF by country), UWS College (university entry-qualifications PDF by country),
--   UNSW College (Global Student Guide PDF and conditional-offer results table), Ozford (high-school equivalents by country page),
--   AIH Higher Education (international academic entry page).
-- Registration only, through pipeline.entry_matrix_sources; the existing entry-matrix-read job fetches and stores. No reader, rule, cron, setting or admission change.
-- Replaces: none. Retires: none.
with rows(provider_id, url, title) as (
 values
 ('c53d394b-bd68-4437-85c8-b9d78f2f83e8'::uuid,'https://internationalcollege.westernsydney.edu.au/wp-content/uploads/WSUIC240910-1200-Academic-Entry-Requirements-Flyer-final.pdf','WSU International College academic entry requirements flyer by country'),
 ('bd473ff9-d45a-4447-9b84-cead3c11c01c'::uuid,'https://www.westernsydney.edu.au/content/dam/digital/pdf/international/INTL0910_Entry_Qualifications_v07.pdf','Western Sydney University entry qualifications table by country (v07)'),
 ('93c852cf-6df7-4161-82bd-ca95941cc227'::uuid,'https://www.unswcollege.edu.au/content/dam/pdfs/unsw-college/global-student-guide.pdf','UNSW College Global Student Guide, academic entry by country'),
 ('93c852cf-6df7-4161-82bd-ca95941cc227'::uuid,'https://www.unswcollege.edu.au/important-notice','UNSW College accepted Semester 1 results for conditional offers by country'),
 ('a1193021-e436-4e0f-8591-4fef64a53476'::uuid,'https://ozford.edu.au/admissions/entry-requirements/high-school/','Ozford high school entry requirements and equivalents by country'),
 ('12924d5c-3e7d-4c99-a10f-10fc36bb244a'::uuid,'https://aih.edu.au/students/entry-requirements/international-students/','AIH international students academic entry requirements')
)
insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
select r.provider_id, r.url, r.title, 1, 'manual' from rows r
join catalogue.providers p on p.id = r.provider_id
join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU'
on conflict (provider_id, url) do nothing;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'aer', 'au_source_returned_wave1_register', 'pipeline.entry_matrix_sources',
       jsonb_build_object('spec', 's1095', 'providers_attempted', 15, 'providers_registered', 5, 'sources_registered', 6,
         'reason', 'AER-FU-04: Admin #1019 returned providers; deeper official sources; no extraction, admission or rule change'),
       auth.uid()
where not exists (select 1 from pipeline.admin_control_events e where e.area='aer' and e.action='au_source_returned_wave1_register' and e.detail->>'spec'='s1095');
