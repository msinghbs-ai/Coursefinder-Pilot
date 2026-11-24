-- CF-247 s1078 — AU AER Steps 1-2, Batch 2 (S1-RM-Design, Platform Admin 24 Nov 2026 21:38; AER-FU-04).
-- Registers official academic entry sources found for the next AU providers by active courses; the existing
-- entry-matrix-read job fetches and stores them (direct HTTP first; Firecrawl only where HTTP is blocked).
-- Guards: AU AER Steps 1-2 only; 7,585 manual locks and G3 75/48 untouched; no new cron, setting, reader or admission change.
-- Replaces: none. Retires: none.
-- Source notes (registered is not stored; evidence is confirmed after the fetch):
--   Murdoch  previous tertiary study by country (undergraduate and postgraduate minimums); the secondary-by-country pages are not yet addressed.
--   USC      undergraduate program admission requirements (secondary qualifications and minimum grades, grouped by country).
--   SCU      international admission requirements ("Academic Score by Country").
--   JCU      international coursework academic and English requirements (candidate; old 2013-2018 PDFs rejected as old editions).
--   TAFE NSW International Academic Requirements by Country (PDF, current edition; the older copy is not registered).
with rows(provider_id, url, title) as (
 values
 ('fbe38fea-5f2c-4946-9097-1de27ea0940f'::uuid,'https://www.murdoch.edu.au/study/international-students/entry-requirements/previous-tertiary-study','Murdoch University previous tertiary study requirements by country'),
 ('42ea5eb7-d243-4e4d-a780-22858a090377'::uuid,'https://usc.edu.au/study/international-students/how-to-apply/step-2-check-entry-requirements/undergraduate-program-admission-requirements','UniSC undergraduate program admission requirements: secondary qualifications and minimum grades by country'),
 ('f30cd2cd-01fc-458e-a061-b7aa5faa8a00'::uuid,'https://www.scu.edu.au/study/international-study/how-to-apply-international-future-students/admission-requirements/','Southern Cross University international admission requirements, academic score by country'),
 ('fe6af182-f5ca-4a3c-bfb4-b0773ff1b113'::uuid,'https://www.jcu.edu.au/applying-to-jcu/international/coursework/academic-and-english-language-entry-requirements','JCU international coursework academic and English language entry requirements'),
 ('430a7fd4-6c32-41d8-b756-0ebbd16b2c0c'::uuid,'https://cd.tafensw.edu.au/api/-/media/Files/PDFs/International/TAFE-International-Academic-Requirements-by-Country.pdf','TAFE NSW International Academic Requirements by Country')
)
insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
select r.provider_id, r.url, r.title, 3, 'manual' from rows r
join catalogue.providers p on p.id = r.provider_id
join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU'
on conflict (provider_id, url) do nothing;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'aer', 'au_source_batch2_register', 'pipeline.entry_matrix_sources',
       jsonb_build_object('spec', 's1078', 'providers_attempted', 9, 'providers_registered', 5, 'sources_registered', 5,
         'held', jsonb_build_array('La Trobe: equivalence published on each course page','Collarts: Year 12 equivalent only','Holmesglen: course-level criteria','Le Cordon Bleu: course-level criteria'),
         'reason', 'AER-FU-04: AU source acquisition; no extraction, admission or rule change'),
       auth.uid()
where not exists (select 1 from pipeline.admin_control_events e where e.area = 'aer' and e.action = 'au_source_batch2_register' and e.detail->>'spec' = 's1078');
