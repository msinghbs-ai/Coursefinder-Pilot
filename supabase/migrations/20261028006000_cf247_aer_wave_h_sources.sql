-- CF-247 AER programme, Wave H (28 Oct 2026). Platform Admin consolidated mandate, 28 Oct 2026 23:22: complete the approved AER plan.
-- Decision record (admin): docs/platform/ENTRY-REQUIREMENTS-PROGRAMME-DECISION-2026-10-28.md (P1 provider scope, P2 sources), lodged before this change.
-- 1. Seeds the official entry-requirements sources of the planned providers (ENTRY-REQUIREMENTS-IMPLEMENTATION.md Part 1) as found_via 'manual':
--    58 sources for 26 providers; 11 are PDFs, which svc_entry_matrix_fetch_next parks as pdf_step_b until the PDF route
--    (Step B) ships; nothing reads them before then. Central-page discovery found no entry page for these providers (no central search
--    result of kind entry_requirements), so the sources are seeded, as UTS, WSU, VU and Federation were.
--    ANU: per-qualification pages from the first index page plus pages found by search; the index's further pages are disallowed by
--    robots.txt (Disallow: /*?*), so the list is partial and reported as such. Melbourne: the per-qualification pages found by search.
--    Monash (course pages), QUT, EIT, NorthTec, UCOL, Toi Ohomai and Canterbury are not seeded (course-page route or contact provider).
--    JavaScript-only pages (Newcastle, Griffith, VUW, Whitireia and WelTec) follow with Step C.
-- 2. Setting entry.providers widened to the planned providers with a seeded source. RMIT stays out (PA mandate: outside matrix reading
--    scope). Guarded: the live value must still be UTS and WSU.
-- Every first read goes to Layer 4 (entry.matrix_first_run_review 1); nothing is admitted by this change. AI spend stays under
-- guard_entry_matrix; pacing stays batch.entry_matrix.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table or status.

do $$
declare v_scope jsonb := (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.providers');
begin
  if v_scope is null or jsonb_array_length(v_scope) <> 2 or not (v_scope ? '9d22a19e-c3f7-4012-b738-17bc0b481e7f') or not (v_scope ? '1719c3ba-1ddf-483e-935e-c750124ba99c') then
    raise exception 'entry.providers is not UTS and WSU (live: %)', v_scope;
  end if;
end $$;

create temporary table wave_h_src(provider_id uuid, url text, title text) on commit drop;
insert into wave_h_src values
  ('0a42da16-8df1-4439-a929-4dfdd04b6d83'::uuid, 'https://www.flinders.edu.au/international/apply/entry-requirements/undergraduate-entry-requirements', 'Flinders: undergraduate entry requirements (international)'),
  ('9109fe0c-9f44-4e2d-a136-eb00dec24701'::uuid, 'https://www.uwa.edu.au/study/how-to-apply/pathways-and-eligibility/international-and-overseas-qualifications', 'UWA: international and overseas qualifications'),
  ('62e61a02-9fcb-4c5e-bb11-1c43bed6eee6'::uuid, 'https://www.uow.edu.au/study/international/representatives/international-entry-requirements/', 'UOW: international entry requirements'),
  ('00e5f26c-446e-453c-a3fb-bc5239a4feec'::uuid, 'https://www.waikato.ac.nz/study/apply/international/entry-requirements-for-international-students/', 'Waikato: entry requirements for international students'),
  ('229dc07d-c573-44a3-b5dc-cc423cc2c300'::uuid, 'https://www.massey.ac.nz/study/entry-requirements-to-study-at-massey/entry-requirements-for-international-students/', 'Massey: entry requirements for international students'),
  ('becd7287-5ede-4a62-800e-b2cd15d62c33'::uuid, 'https://www.manukau.ac.nz/study/international-students/how-to-apply/entry-requirements-academic/', 'MIT: academic entry requirements'),
  ('dbf22c45-062e-4c5d-92a9-aaabd8c452f7'::uuid, 'https://www.nmit.ac.nz/international/entry-requirements', 'NMIT: international entry requirements'),
  ('cd27693c-6c80-42f4-8b76-1ed2d94e0b45'::uuid, 'https://www.op.ac.nz/international/apply-and-enrol/entry-requirements', 'Otago Polytechnic: international entry requirements'),
  ('e2dd4b2b-1379-46c5-abe1-e8f24e685913'::uuid, 'https://sit.ac.nz/International/How-to-Apply', 'SIT: international how to apply (entry requirements)'),
  ('87576ec2-c4b0-4a00-ab94-64422c77d545'::uuid, 'https://www.ara.ac.nz/academic-equivalence', 'Ara: academic equivalence'),
  ('742eef0a-1341-46ef-a4ab-4d105c47be9b'::uuid, 'https://www.wintec.ac.nz/international/international-academic-entry-requirements', 'Wintec: international academic entry requirements'),
  ('66f6fcc9-15f8-46e6-b3b3-0576ab4bcce3'::uuid, 'https://www.unitec.ac.nz/international/study-with-us/country-specific-criteria/', 'Unitec: country-specific criteria'),
  ('39301fa8-bff2-4389-bbcd-32d8415fae04'::uuid, 'https://www.aut.ac.nz/study/entry-requirements/international-student-entry-requirements', 'AUT: international student entry requirements'),
  ('ab12c7f8-e368-453d-9dfe-4ab8bd744829'::uuid, 'https://www.otago.ac.nz/study/entry-requirements/international-entrance-requirements', 'Otago: international entrance requirements'),
  ('248374d1-0629-41cd-a6f4-0804c422a4ff'::uuid, 'https://www.lincoln.ac.nz/study/apply-and-enrol/international-undergraduate-entry-criteria/', 'Lincoln: international undergraduate entry criteria'),
  ('349da14b-66b1-4c57-9dfd-6f9c36412432'::uuid, 'https://www.swinburne.edu.au/international-students/countries/india/', 'Swinburne: India country page (bachelor minimum)'),
  ('de6d32b0-f91b-4dd0-a3da-a542f1aba5f2'::uuid, 'https://study.unimelb.edu.au/how-to-apply/undergraduate-study/international-applications/entry-requirements/recognised-international-qualifications/qualifications/india-all-india-senior-school-certificate-cbse-and-indian-school-certificate-isc', 'Melbourne: India CBSE and ISC (courses)'),
  ('de6d32b0-f91b-4dd0-a3da-a542f1aba5f2'::uuid, 'https://study.unimelb.edu.au/how-to-apply/undergraduate-study/international-applications/entry-requirements/recognised-international-qualifications/qualifications/india-state-board-matriculation-examination', 'Melbourne: India State Boards (courses)'),
  ('de6d32b0-f91b-4dd0-a3da-a542f1aba5f2'::uuid, 'https://study.unimelb.edu.au/how-to-apply/undergraduate-study/recognised-vce-equivalent-qualifications/qualifications/general-international-qualifications-gce-a-levels', 'Melbourne: GCE A Levels (courses)'),
  ('de6d32b0-f91b-4dd0-a3da-a542f1aba5f2'::uuid, 'https://study.unimelb.edu.au/how-to-apply/undergraduate-study/recognised-vce-equivalent-qualifications/qualifications/general-international-qualifications-international-baccalaureate-ib-diploma', 'Melbourne: IB Diploma (courses)'),
  ('22657140-1cb0-4fa7-91df-90518ea8b35b'::uuid, 'https://www.unsw.edu.au/content/dam/pdfs/future-students/2027-int-ug-entry-table.pdf', 'UNSW: 2027 international undergraduate entry table (PDF)'),
  ('68022bdf-43e8-44b3-ac14-e9eed9f71e83'::uuid, 'https://www.sydney.edu.au/dam/corporate/documents/study/how-to-apply/international-admission-guide.pdf', 'Sydney: international admission guide (PDF)'),
  ('e55396d2-869a-46ef-9d17-841c7eab1313'::uuid, 'https://study.uq.edu.au/sites/default/files/2026-09/International-minimum-entry-score-guide.pdf', 'UQ: international minimum entry score guide (PDF)'),
  ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0'::uuid, 'https://adelaide.edu.au/content/dam/adelaideuniversity/documents/study/pdfs/AU_Undergraduate_Admission_By_Country.pdf', 'Adelaide: undergraduate admission by country (PDF)'),
  ('982fb12f-41ed-4358-9d1b-d7422b3089dd'::uuid, 'https://s30991.pcdn.co/study/wp-content/uploads/sites/3/2026/03/2026-Overseas-qualifications-recognised-by-Curtin-University.pdf', 'Curtin: 2026 overseas qualifications recognised (PDF)'),
  ('1719c3ba-1ddf-483e-935e-c750124ba99c'::uuid, 'https://www.westernsydney.edu.au/content/dam/digital/pdf/international/INTL0910_Entry_Qualifications_v07.pdf', 'WSU: entry qualifications v07 (PDF)'),
  ('188103a5-1aba-4f99-bd3e-0416659086d3'::uuid, 'https://www.mq.edu.au/__data/assets/pdf_file/0003/1381269/Academic-Entry-for-International-Students-Undergraduate-July-2026.pdf', 'Macquarie: academic entry, undergraduate, July 2026 (PDF)'),
  ('188103a5-1aba-4f99-bd3e-0416659086d3'::uuid, 'https://www.mq.edu.au/__data/assets/pdf_file/0010/1381267/Academic-Entry-for-International-Students-Pathways-July-2026.pdf', 'Macquarie: academic entry, pathways, July 2026 (PDF)'),
  ('188103a5-1aba-4f99-bd3e-0416659086d3'::uuid, 'https://www.mq.edu.au/__data/assets/pdf_file/0011/1381268/Academic-Entry-for-International-Students-Postgraduate-July-2026.pdf', 'Macquarie: academic entry, postgraduate, July 2026 (PDF)'),
  ('e096aba7-e1eb-4903-9a63-2bfb71e9a8b8'::uuid, 'https://www.auckland.ac.nz/assets/study/applications-and-admissions/entry-requirements/undergraduate-entry-requirements/overseas-secondary-school-applicants/2027+Undergraduate-programme-specific-entry-requirements-A-I.pdf', 'Auckland: 2027 programme entry requirements A-I (PDF)'),
  ('e096aba7-e1eb-4903-9a63-2bfb71e9a8b8'::uuid, 'https://www.auckland.ac.nz/assets/study/applications-and-admissions/entry-requirements/undergraduate-entry-requirements/overseas-secondary-school-applicants/2027+Undergraduate-programme-specific-entry-requirements-J-Z.pdf', 'Auckland: 2027 programme entry requirements J-Z (PDF)'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/advanced-placement-ap-applications', 'ANU: indicative entry, advanced-placement-ap-applications'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/austrian-maturity-certificate', 'ANU: indicative entry, austrian-maturity-certificate'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/belgian-upper-secondary-school', 'ANU: indicative entry, belgian-upper-secondary-school'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/belgium-certificate-access-higher', 'ANU: indicative entry, belgium-certificate-access-higher'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/bosnia-herzegovina-secondary-school', 'ANU: indicative entry, bosnia-herzegovina-secondary-school'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/brazilian-national-high-school-exam', 'ANU: indicative entry, brazilian-national-high-school-exam'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/bulgarian-diploma-completion', 'ANU: indicative entry, bulgarian-diploma-completion'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/canada-alberta-high-school-diploma', 'ANU: indicative entry, canada-alberta-high-school-diploma'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/canada-british-columbia-certificate', 'ANU: indicative entry, canada-british-columbia-certificate'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/canada-manitoba-high-school', 'ANU: indicative entry, canada-manitoba-high-school'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/canada-new-brunswick-high-school', 'ANU: indicative entry, canada-new-brunswick-high-school'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/canada-newfoundland-provincial-high', 'ANU: indicative entry, canada-newfoundland-provincial-high'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/canada-nova-scotia-high-school', 'ANU: indicative entry, canada-nova-scotia-high-school'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/canada-ontario-secondary-school', 'ANU: indicative entry, canada-ontario-secondary-school'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/canada-quebec-diploma-collegial', 'ANU: indicative entry, canada-quebec-diploma-collegial'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/canada-saskatchewan-complete-division', 'ANU: indicative entry, canada-saskatchewan-complete-division'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/china-gao-kao', 'ANU: indicative entry, china-gao-kao'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/croatian-matura', 'ANU: indicative entry, croatian-matura'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/czech-republic-maturita', 'ANU: indicative entry, czech-republic-maturita'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/usa-american-college-test-act', 'ANU: indicative entry, usa-american-college-test-act'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/singapore-levels', 'ANU: indicative entry, singapore-levels'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/sri-lankan-gce-advanced-level', 'ANU: indicative entry, sri-lankan-gce-advanced-level'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/hong-kong-diploma-secondary-education', 'ANU: indicative entry, hong-kong-diploma-secondary-education'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/indian-school-certificate-isc', 'ANU: indicative entry, indian-school-certificate-isc'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/vietnam-upper-secondary-education-0', 'ANU: indicative entry, vietnam-upper-secondary-education-0'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/international-applications/indicative-entry-requirement/india-all-india-senior-school', 'ANU: indicative entry, india-all-india-senior-school'),
  ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid, 'https://study.anu.edu.au/apply/undergraduate-program-indicative-entry-requirements/international-baccalaureate-applications', 'ANU: indicative entry, international-baccalaureate');

do $$
declare v_before int := (select count(*) from pipeline.entry_matrix_sources); v_new int; v_bad int;
begin
  select count(*) into v_bad from wave_h_src w where not exists (select 1 from catalogue.providers p where p.id = w.provider_id);
  if v_bad > 0 then raise exception '% Wave H sources name an unknown provider', v_bad; end if;
  select count(*) into v_bad from wave_h_src w where w.provider_id = '8e1adb6c-e069-43db-9584-bd054255e702';
  if v_bad > 0 then raise exception 'RMIT is outside matrix reading scope'; end if;
  insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
  select w.provider_id, w.url, w.title, 1, 'manual' from wave_h_src w
  on conflict (provider_id, url) do nothing;
  get diagnostics v_new = row_count;
  if v_new <> 58 then raise exception 'Wave H: expected 58 new sources, inserted %', v_new; end if;
  if (select count(*) from pipeline.entry_matrix_sources) <> v_before + 58 then raise exception 'Wave H: source count mismatch'; end if;
end $$;

update pipeline.platform_toolset_settings
   set value = '["00e5f26c-446e-453c-a3fb-bc5239a4feec", "0a42da16-8df1-4439-a929-4dfdd04b6d83", "1719c3ba-1ddf-483e-935e-c750124ba99c", "188103a5-1aba-4f99-bd3e-0416659086d3", "22657140-1cb0-4fa7-91df-90518ea8b35b", "229dc07d-c573-44a3-b5dc-cc423cc2c300", "248374d1-0629-41cd-a6f4-0804c422a4ff", "349da14b-66b1-4c57-9dfd-6f9c36412432", "39301fa8-bff2-4389-bbcd-32d8415fae04", "62e61a02-9fcb-4c5e-bb11-1c43bed6eee6", "66f6fcc9-15f8-46e6-b3b3-0576ab4bcce3", "68022bdf-43e8-44b3-ac14-e9eed9f71e83", "742eef0a-1341-46ef-a4ab-4d105c47be9b", "87576ec2-c4b0-4a00-ab94-64422c77d545", "9109fe0c-9f44-4e2d-a136-eb00dec24701", "982fb12f-41ed-4358-9d1b-d7422b3089dd", "9cc8ef21-52ec-4c18-849a-598ba1072459", "9d22a19e-c3f7-4012-b738-17bc0b481e7f", "ab12c7f8-e368-453d-9dfe-4ab8bd744829", "bac82321-ded7-4e10-a71d-b18f3ae4d1c7", "becd7287-5ede-4a62-800e-b2cd15d62c33", "cd27693c-6c80-42f4-8b76-1ed2d94e0b45", "dbf22c45-062e-4c5d-92a9-aaabd8c452f7", "de2201a1-69ee-40ff-b6aa-0e54e535e6c0", "de6d32b0-f91b-4dd0-a3da-a542f1aba5f2", "e096aba7-e1eb-4903-9a63-2bfb71e9a8b8", "e2dd4b2b-1379-46c5-abe1-e8f24e685913", "e47a940d-186f-4a17-bb22-2b794b73248c", "e55396d2-869a-46ef-9d17-841c7eab1313"]'::jsonb,
       updated_at = now(),
       reason = 'CF-247 AER programme Wave H: Platform Admin consolidated mandate 28 Oct 2026 23:22 (complete the approved plan; RMIT outside matrix reading scope). Planned providers with a seeded official source.'
 where toolset_key = 'pipeline' and key = 'entry.providers';

do $$ begin
  if jsonb_array_length((select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.providers')) <> 29 then
    raise exception 'entry.providers widening did not apply';
  end if;
  if security.entry_matrix_enabled_v1('8e1adb6c-e069-43db-9584-bd054255e702') then raise exception 'RMIT must stay out of matrix reading scope'; end if;
end $$;
