-- CF-247 s1107 — AU AER Steps 1-2 (S1-AER-Claude, Platform Admin 25 Nov 2026 06:06 AEDT, Admin #1049 wave 1, 40 named providers; Admin #1028).
-- Registers official pages and PDFs found for 16 of the 40 named providers (La Trobe University, Collarts, Le Cordon Bleu Australia, Australian Pacific College, AIBT,
-- Excelsia, Holmesglen, George Brown College (Australia, the NSW record), Greenwich, Box Hill, William Angliss, Reach, York, AAPoly / AMI, Gold Coast Learning Centre,
-- TasTAFE). Every address was returned by a search of the provider's own domain on 25 Nov 2026, except La Trobe's (read on the university's staging mirror; the path is the
-- same on production) and William Angliss and Gold Coast Learning Centre (found earlier by the stored-source finder). A page that is gone is marked failed by the
-- fetch worker and costs nothing. Registration only, through pipeline.entry_matrix_sources; the existing entry-matrix-read job fetches and stores.
-- No reader, rule, cron, setting, admission or consumer object change. Spend US$0.
-- Replaces: none. Retires: none.
with rows(provider_id, url, title) as (
 values
 ('4f86e09a-557c-4544-a0a3-3eb5dc8468a9'::uuid,'https://www.latrobe.edu.au/international/applying/entry-requirements','La Trobe University international entry and language requirements'),
 ('53eaf404-8f22-46ff-a208-b0e82da4284e'::uuid,'https://www.collarts.edu.au/study-information/international-students/','Collarts international student information hub (entry criteria)'),
 ('2968fe36-b879-4b53-8318-664ed56d291a'::uuid,'https://www.cordonbleu.edu/australia/how-to-apply/en','Le Cordon Bleu Australia how to apply'),
 ('2968fe36-b879-4b53-8318-664ed56d291a'::uuid,'https://www.cordonbleu.edu/Files/AAGCEN25513.pdf','Le Cordon Bleu Australia student selection and admission policy (Appendix A entry requirements)'),
 ('658d593d-cd4a-4940-9927-0d471776284e'::uuid,'https://www.apc.edu.au/apply/requirements/','Australian Pacific College entry requirements'),
 ('eb9e3903-6d92-4502-a2b3-51cb231b21fc'::uuid,'https://aibtglobal.edu.au/about/course-terms/','AIBT course terms and conditions (English entry requirements)'),
 ('eb9e3903-6d92-4502-a2b3-51cb231b21fc'::uuid,'https://aibtglobal.edu.au/courses/study/diploma-leadership-management/','AIBT Diploma of Leadership and Management entry requirements (course level)'),
 ('c537423d-028a-4b06-b135-003f2c6c393d'::uuid,'https://excelsia.edu.au/wp-content/uploads/International-Students-Guide.pdf','Excelsia international students guide (admission requirements)'),
 ('c537423d-028a-4b06-b135-003f2c6c393d'::uuid,'https://excelsia.edu.au/study/future-students/','Excelsia future students: application and entry requirements'),
 ('4b0e9d62-2ad7-4467-911c-1571e30a74d6'::uuid,'https://www.holmesglen.edu.au/study-with-us/international-student-study/how-to-apply-international-students/English-requirements-for-international-students','Holmesglen English language entry requirements (international)'),
 ('4b0e9d62-2ad7-4467-911c-1571e30a74d6'::uuid,'https://holmesglen.edu.au/Students/Higher-Education-students/Admissions-information/','Holmesglen higher education admissions information'),
 ('80e8f5fd-1b38-4292-90ab-adafc9884381'::uuid,'https://georgebrown.nsw.edu.au/wp-content/uploads/2024/06/Recruitment-Admissions-and-Enrolment-Policy-and-Procedure-V.12-15.05.2024.pdf','George Brown College (Sydney) recruitment, admissions and enrolment policy'),
 ('80e8f5fd-1b38-4292-90ab-adafc9884381'::uuid,'https://georgebrown.nsw.edu.au/wp-content/uploads/2025/08/English-Language-Requirements-Policy-v.7-07.08.2025.pdf','George Brown College (Sydney) English language requirements policy'),
 ('21e1cb6d-9c85-431f-b354-43b7370e5f40'::uuid,'https://greenwichcollege.edu.au/how_to_apply/','Greenwich College how to apply'),
 ('21e1cb6d-9c85-431f-b354-43b7370e5f40'::uuid,'https://www.greenwichcollege.edu.au/study-in-australia','Greenwich College study in Australia (entry requirements)'),
 ('104f3038-862c-445d-aaf3-b8727ff756f3'::uuid,'https://www.boxhill.edu.au/courses/bachelor-of-information-technology-bit01-ihe/','Box Hill Institute Bachelor of Information Technology entry requirements (course level)'),
 ('104f3038-862c-445d-aaf3-b8727ff756f3'::uuid,'https://www.boxhill.edu.au/courses/bachelor-of-commerce-applied-bcom2-ihe/','Box Hill Institute Bachelor of Commerce (Applied) entry requirements (course level)'),
 ('5c234f7f-a84c-46ae-b2ef-bfa75b59badd'::uuid,'https://www.angliss.edu.au/study-with-us/international-student-info/how-to-apply/entry-requirements/','William Angliss international entry requirements'),
 ('8495927d-cbd8-426d-814c-fa87d1a966e7'::uuid,'https://reachcollege.edu.au/how-to-apply/','Reach Community College how to apply'),
 ('8495927d-cbd8-426d-814c-fa87d1a966e7'::uuid,'https://reachcollege.edu.au/course-terms/','Reach Community College course terms (English entry requirements)'),
 ('9aa61e05-ec5e-4468-8d2e-c3c6fb984f37'::uuid,'https://york.edu.au/pre-enrolment/','York Business Institute pre-enrolment and entry requirements'),
 ('f0c0f1dc-e628-4bb7-9943-727f32b26d50'::uuid,'https://aapoly.edu.au/new-english-language-requirements','AAPoly / AMI Education English language requirements'),
 ('f2ec4927-522c-42a7-8de4-33ada6684595'::uuid,'https://www.goldcoaststudy.com/policies-and-procedures/entry-requirements-vet/','Gold Coast Learning Centre VET entry requirements'),
 ('f16868c3-5487-487f-92cd-88e63116765c'::uuid,'https://www.tastafe.tas.edu.au/international/how-to-apply-international-students/english-entry-requirements-international','TasTAFE English entry requirements (international)')
)
insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
select r.provider_id, r.url, r.title, 1, 'manual' from rows r
join catalogue.providers p on p.id = r.provider_id
join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU'
on conflict (provider_id, url) do nothing;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'aer', 'au_source_wave1_steps12_register', 'pipeline.entry_matrix_sources',
       jsonb_build_object('spec', 's1107', 'admin', '#1049', 'providers_named', 40, 'providers_registered', 16, 'sources_registered', 24,
         'reason', 'Admin #1049 wave 1 Steps 1-2: registration of official sources only; no extraction, admission or rule change'),
       auth.uid()
where not exists (select 1 from pipeline.admin_control_events e where e.area='aer' and e.action='au_source_wave1_steps12_register' and e.detail->>'spec'='s1107');
