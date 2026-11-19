-- CF-247 s798 (Platform Admin 20 Nov 2026 05:42 AEDT, chat S1-Build; decisions B1, B3 and B4 of the 19 Nov AU/NZ/CA gap assessment, approved).
-- B1 (REQ-57, RM1F): AACSB and EQUIS accreditations of AU, NZ and CA providers, read 20 Nov 2026 from the bodies' own pages at no cost
--   (no Firecrawl, no AI): EQUIS from the EFMD accredited-schools list; AACSB from AACSB's accredited-school pages, or the school's own
--   accreditation page where AACSB's page could not be read. 58 AACSB rows (AU 25 incl. UNSW Canberra, NZ 7, CA 26) and 31 EQUIS
--   (AU 14, NZ 6, CA 11). Left out: Wilfrid Laurier University (not in the catalogue) and the University of New Brunswick (AACSB lists it
--   as a non-accredited member). The 13 AMBA rows held for review since 18 Nov are approved. Double Crown = any two of the three bodies,
--   Triple Crown = all three (security.provider_accreditation_crown_v1), on the v3 provider and course answers.
-- B3 (REQ-77): IRU is renamed the 2050 Alliance (May 2026); ACU and Victoria University are added. Checked against the alliance's list on
--   ACU's page (nine members: ACU, Flinders, Griffith, JCU, La Trobe, Murdoch, Canberra, VU, Western Sydney) and iru.edu.au: Canberra is a
--   member, Charles Darwin is not. The collection code au_iru is kept so filters that use it do not break. The members' courses are queued
--   for a search refresh (collection names).
-- B4: the English grades held (score_grade, subtest_grades) are shown on each v3 English requirement, as held (null when none is held);
--   no letter is derived from a number.
-- v3 also states the basis of the study load (study_load_basis: provider_page, register, register_rule, manual), so a B7 rule value is never
--   mistaken for a reading. API v3 is open to additions (Decision 277); the v3 field dictionary is reloaded by 20261120080100.
-- Parity before writing (read live 20 Nov 2026 05:45 AEDT): head 20261120010000. G3: no consumer (v2) object changes. No spend.
-- Replaces: nothing.
-- Retires: nothing.

create or replace function security.provider_accreditation_crown_v1(p_provider uuid)
returns text language sql stable security definer set search_path to '' as $f$
  select case count(distinct a.body_code) when 3 then 'triple_crown' when 2 then 'double_crown' end
    from catalogue.provider_accreditations a
   where a.provider_id = p_provider and a.status = 'active' and (a.expires_at is null or a.expires_at >= current_date)
     and a.body_code in ('AACSB', 'EQUIS', 'AMBA')
$f$;
revoke all on function security.provider_accreditation_crown_v1(uuid) from public, anon, authenticated;
comment on function security.provider_accreditation_crown_v1(uuid) is 'CF-247 s798 B1: triple_crown when AACSB, EQUIS and AMBA are all held now, double_crown for any two, else null.';

-- B1: the accreditations read 20 Nov 2026
insert into catalogue.provider_accreditations (provider_id, body_code, accredited_unit_name, status, source_url, verified_at, content_hash)
select v.provider_id, v.body_code, v.unit, 'active', v.url, now(), md5(v.body_code || '|' || v.provider_id || '|' || coalesce(v.unit, '') || '|' || v.url)
  from (values
  ('AACSB', 'de6d32b0-f91b-4dd0-a3da-a542f1aba5f2'::uuid, null, 'https://www.aacsb.edu/accredited/u/university-of-melbourne'),
  ('AACSB', '68022bdf-43e8-44b3-ac14-e9eed9f71e83'::uuid, null, 'https://www.aacsb.edu/accredited/t/the-university-of-sydney'),
  ('AACSB', '188103a5-1aba-4f99-bd3e-0416659086d3'::uuid, null, 'https://www.aacsb.edu/accredited/m/macquarie-university'),
  ('AACSB', '22657140-1cb0-4fa7-91df-90518ea8b35b'::uuid, 'UNSW Business School', 'https://www.aacsb.edu/accredited/u/unsw-business-school-unsw-sydney'),
  ('AACSB', '22657140-1cb0-4fa7-91df-90518ea8b35b'::uuid, 'UNSW Canberra School of Business', 'https://www.aacsb.edu/accredited/u/unsw-canberra-school-of-business-unsw-sydney'),
  ('AACSB', '982fb12f-41ed-4358-9d1b-d7422b3089dd'::uuid, null, 'https://www.aacsb.edu/accredited/c/curtin-university'),
  ('AACSB', '4f86e09a-557c-4544-a0a3-3eb5dc8468a9'::uuid, null, 'https://www.aacsb.edu/accredited/l/la-trobe-university'),
  ('AACSB', 'c5c5d225-3d4c-4e41-8275-78eddd261073'::uuid, null, 'https://www.aacsb.edu/accredited/d/deakin-university'),
  ('AACSB', '030992c3-72c6-452d-8a3b-10ceb0fd77f2'::uuid, null, 'https://www.aacsb.edu/accredited/a/australian-catholic-university'),
  ('AACSB', '349da14b-66b1-4c57-9dfd-6f9c36412432'::uuid, null, 'https://www.aacsb.edu/accredited/s/swinburne-university-of-technology'),
  ('AACSB', '8e1adb6c-e069-43db-9584-bd054255e702'::uuid, null, 'https://www.aacsb.edu/accredited/r/rmit-university'),
  ('AACSB', '543b87b8-f0dd-4bc7-80d6-76252cfaabec'::uuid, 'Monash Business School', 'https://www.aacsb.edu/accredited/m/monash-business-school-monash-university'),
  ('AACSB', '2c4f515c-c146-4e90-ba8a-294130aa1f40'::uuid, null, 'https://www.aacsb.edu/accredited/q/queensland-university-of-technology'),
  ('AACSB', 'e55396d2-869a-46ef-9d17-841c7eab1313'::uuid, null, 'https://www.aacsb.edu/accredited/t/the-university-of-queensland'),
  ('AACSB', '36086f5e-9fe0-4878-aa40-1897a7d8cb24'::uuid, null, 'https://www.aacsb.edu/accredited/g/griffith-university'),
  ('AACSB', 'fac03540-a412-4c76-a5ab-cd338d7760db'::uuid, null, 'https://www.aacsb.edu/accredited/e/edith-cowan-university'),
  ('AACSB', '1719c3ba-1ddf-483e-935e-c750124ba99c'::uuid, null, 'https://www.aacsb.edu/accredited/w/western-sydney-university'),
  ('AACSB', '62e61a02-9fcb-4c5e-bb11-1c43bed6eee6'::uuid, null, 'https://www.aacsb.edu/accredited/u/university-of-wollongong'),
  ('AACSB', '9d22a19e-c3f7-4012-b738-17bc0b481e7f'::uuid, null, 'https://www.aacsb.edu/accredited/u/university-of-technology-sydney'),
  ('AACSB', '9109fe0c-9f44-4e2d-a136-eb00dec24701'::uuid, null, 'https://www.aacsb.edu/accredited/u/university-of-western-australia'),
  ('AACSB', '1822b40a-8b13-44dc-8c37-106ae31bb447'::uuid, null, 'https://www.aacsb.edu/accredited/t/the-university-of-newcastle'),
  ('AACSB', '719403bc-6957-4d21-af69-2b3b102df578'::uuid, 'Tasmanian School of Business and Economics', 'https://aacsb.edu/accredited/t/tasmanian-school-of-business-and-economics-university-of-tasmania'),
  ('AACSB', '42ea5eb7-d243-4e4d-a780-22858a090377'::uuid, null, 'https://aacsb.edu/accredited/u/university-of-the-sunshine-coast'),
  ('AACSB', '739948f6-6338-4ee9-8d0c-a8c8e953c29d'::uuid, null, 'https://www.aacsb.edu/accredited/b/bond-university'),
  ('AACSB', '0a42da16-8df1-4439-a929-4dfdd04b6d83'::uuid, null, 'https://www.aacsb.edu/media-center/news/2026/11/6-institutions-earn-aacsb-initial-business-accreditation'),
  ('AACSB', 'e096aba7-e1eb-4903-9a63-2bfb71e9a8b8'::uuid, null, 'https://www.aacsb.edu/accredited/t/the-university-of-auckland'),
  ('AACSB', '39301fa8-bff2-4389-bbcd-32d8415fae04'::uuid, null, 'https://www.aacsb.edu/accredited/a/auckland-university-of-technology'),
  ('AACSB', '34616965-b2b7-42a7-8da7-50ffbf120958'::uuid, null, 'https://www.aacsb.edu/accredited/v/victoria-university-of-wellington'),
  ('AACSB', '00e5f26c-446e-453c-a3fb-bc5239a4feec'::uuid, null, 'https://www.aacsb.edu/accredited/t/the-university-of-waikato'),
  ('AACSB', '229dc07d-c573-44a3-b5dc-cc423cc2c300'::uuid, null, 'https://www.aacsb.edu/accredited/m/massey-university'),
  ('AACSB', 'ab12c7f8-e368-453d-9dfe-4ab8bd744829'::uuid, null, 'https://www.aacsb.edu/accredited/u/university-of-otago'),
  ('AACSB', 'db910e88-67d1-4d2b-a65c-cea290aa0692'::uuid, 'UC Business School', 'https://www.canterbury.ac.nz/news-and-events/news/2025/uc-business-school-retains-triple-crown-accreditation-'),
  ('AACSB', 'fa9fb404-21ea-4f52-8caf-351dc3b55a83'::uuid, null, 'https://www.aacsb.edu/accredited/u/university-of-toronto'),
  ('AACSB', 'cffb854b-5d63-43b1-96fe-23bcd0c1917e'::uuid, null, 'https://www.aacsb.edu/accredited/u/university-of-ottawa'),
  ('AACSB', 'db436563-4650-4820-bd76-0695afcc953d'::uuid, null, 'https://www.aacsb.edu/accredited/u/university-of-alberta'),
  ('AACSB', 'ed3cf118-13fa-4538-b1e0-689228770ed3'::uuid, null, 'https://www.aacsb.edu/accredited/u/university-of-saskatchewan'),
  ('AACSB', '175462f3-59ea-4370-9c80-e7a06b100137'::uuid, null, 'https://www.aacsb.edu/accredited/u/university-of-british-columbia'),
  ('AACSB', 'ad7bb2f7-ed12-4181-b5c4-d071db14bfda'::uuid, null, 'https://www.aacsb.edu/accredited/u/university-of-calgary'),
  ('AACSB', '40abe289-b458-47dd-a035-96d339bd1248'::uuid, null, 'https://www.aacsb.edu/accredited/q/queens-university'),
  ('AACSB', 'c9d6e8c8-a988-4f90-94c4-944a5bf2aec0'::uuid, null, 'https://www.aacsb.edu/accredited/m/memorial-university-of-newfoundland'),
  ('AACSB', '97433acd-91da-4e21-ab9f-427ed2d39e33'::uuid, null, 'https://www.aacsb.edu/accredited/d/dalhousie-university'),
  ('AACSB', '1e006385-fd4a-431d-b63a-5b29c09f1fea'::uuid, null, 'https://www.aacsb.edu/accredited/m/mcmaster-university'),
  ('AACSB', 'b509ab5c-87b2-4040-8385-d1ce610c7263'::uuid, null, 'https://www.aacsb.edu/accredited/u/university-of-lethbridge'),
  ('AACSB', '8045d740-6a60-452e-9b24-d5e18841b06f'::uuid, null, 'https://www.aacsb.edu/accredited/l/lakehead-university'),
  ('AACSB', '68341895-092b-480c-962d-57ec0fb152fc'::uuid, null, 'https://www.aacsb.edu/accredited/u/university-of-guelph'),
  ('AACSB', 'e450a320-27d7-4ca2-8ad6-cafa266df869'::uuid, null, 'https://www.aacsb.edu/accredited/a/athabasca-university'),
  ('AACSB', 'd47b6006-396a-4785-b2ae-15186c3e7709'::uuid, null, 'https://www.aacsb.edu/accredited/s/simon-fraser-university'),
  ('AACSB', '9e94a92a-fd26-4aa5-82c9-77b481f7682d'::uuid, null, 'https://www.aacsb.edu/accredited/c/concordia-university'),
  ('AACSB', '140703e7-5d00-4007-88d6-4084148c6736'::uuid, null, 'https://aacsb.edu/accredited/h/hec-montral'),
  ('AACSB', '98e591df-d272-481e-9054-2b85a66261be'::uuid, null, 'https://www.aacsb.edu/accredited/u/university-of-victoria'),
  ('AACSB', '037ccfe3-cc93-43d1-a30a-283a979b2a28'::uuid, null, 'https://www.aacsb.edu/accredited/s/saint-marys-university'),
  ('AACSB', 'd7508425-0ecb-4ae0-8f47-064399362fe9'::uuid, null, 'https://www.aacsb.edu/accredited/u/university-of-windsor'),
  ('AACSB', '758e7d2b-f419-49bf-9e69-34f1454bc6ec'::uuid, null, 'https://www.aacsb.edu/accredited/b/brock-university'),
  ('AACSB', 'ede06b09-1e9a-4594-96d3-24e769cb4f91'::uuid, 'Hill Levene School of Business', 'https://www.uregina.ca/news/2026/hill-levene-school-of-business-at-the-university-of-regina-earns-aacsb-international-accreditation.html'),
  ('AACSB', 'd4150646-46b4-4a83-b89b-2a4de22b2f4d'::uuid, 'Ted Rogers School of Management', 'https://www.torontomu.ca/tedrogersschool/about/accreditations/'),
  ('AACSB', '881a0ebc-9e8c-4e7e-8172-6c1e6f149e67'::uuid, 'Sprott School of Business', 'https://sprott.carleton.ca/accreditation-recognition/'),
  ('AACSB', 'cffa9cab-0a3b-458b-8383-483ce622c9c3'::uuid, 'I.H. Asper School of Business', 'https://www.umanitoba.ca/asper/accreditations-and-recognitions'),
  ('AACSB', '27afe83b-071e-4e0d-a048-52bd1440f576'::uuid, 'Faculté des sciences de l''administration (FSA ULaval)', 'https://www.fsa.ulaval.ca/en/news/promoting-fsa-ulaval-seals-excellence/'),
  ('EQUIS', 'de2201a1-69ee-40ff-b6aa-0e54e535e6c0'::uuid, 'Adelaide Business School, Adelaide University', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '739948f6-6338-4ee9-8d0c-a8c8e953c29d'::uuid, 'Bond Business School', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '982fb12f-41ed-4358-9d1b-d7422b3089dd'::uuid, 'Curtin Business School, Curtin University', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', 'c5c5d225-3d4c-4e41-8275-78eddd261073'::uuid, 'Deakin Business School, Deakin University', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '36086f5e-9fe0-4878-aa40-1897a7d8cb24'::uuid, 'Griffith Business School, Griffith University', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', 'de6d32b0-f91b-4dd0-a3da-a542f1aba5f2'::uuid, 'Melbourne Business School and the Faculty of Business and Economics of the University of Melbourne', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '543b87b8-f0dd-4bc7-80d6-76252cfaabec'::uuid, 'Monash Business School, Monash University', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '1822b40a-8b13-44dc-8c37-106ae31bb447'::uuid, 'Newcastle Business School, The University of Newcastle', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '2c4f515c-c146-4e90-ba8a-294130aa1f40'::uuid, 'QUT Business School, QUT - Queensland University of Technology', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '9109fe0c-9f44-4e2d-a136-eb00dec24701'::uuid, 'Business School, The University of Western Australia', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '68022bdf-43e8-44b3-ac14-e9eed9f71e83'::uuid, 'University of Sydney Business School', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '22657140-1cb0-4fa7-91df-90518ea8b35b'::uuid, 'UNSW Business School, UNSW Australia', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', 'e55396d2-869a-46ef-9d17-841c7eab1313'::uuid, 'UQ Business, University of Queensland', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '9d22a19e-c3f7-4012-b738-17bc0b481e7f'::uuid, 'UTS Business School, University of Technology Sydney', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '39301fa8-bff2-4389-bbcd-32d8415fae04'::uuid, 'Auckland University of Technology Business School', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', 'e096aba7-e1eb-4903-9a63-2bfb71e9a8b8'::uuid, 'The University of Auckland Business School', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', 'ab12c7f8-e368-453d-9dfe-4ab8bd744829'::uuid, 'Otago Business School, University of Otago', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', 'db910e88-67d1-4d2b-a65c-cea290aa0692'::uuid, 'UC Business School, University of Canterbury', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '34616965-b2b7-42a7-8da7-50ffbf120958'::uuid, 'Wellington School of Business and Government, Victoria University of Wellington', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '00e5f26c-446e-453c-a3fb-bc5239a4feec'::uuid, 'Waikato Management School, The University of Waikato', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '140703e7-5d00-4007-88d6-4084148c6736'::uuid, 'HEC Montréal', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', 'ebd96fd9-b4b8-474c-8729-6fb01c3c0b57'::uuid, 'Ivey Business School, Western University', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '2bf782c5-e2df-477f-959d-fcec254c2d7b'::uuid, 'Desautels Faculty of Management, McGill University', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '9e94a92a-fd26-4aa5-82c9-77b481f7682d'::uuid, 'John Molson School of Business, Concordia University', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '40abe289-b458-47dd-a035-96d339bd1248'::uuid, 'Queen''s University, Smith School of Business', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', 'a1198033-11d5-4ecb-979f-84991ae99fbe'::uuid, 'Schulich School of Business, York University', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', 'd47b6006-396a-4785-b2ae-15186c3e7709'::uuid, 'Beedie School of Business, Simon Fraser University', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '27afe83b-071e-4e0d-a048-52bd1440f576'::uuid, 'Faculté des Sciences de l''Administration, Université Laval', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', 'cffb854b-5d63-43b1-96fe-23bcd0c1917e'::uuid, 'Telfer School of Management, University of Ottawa', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '98e591df-d272-481e-9054-2b85a66261be'::uuid, 'Peter B. Gustavson School of Business, University of Victoria', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/'),
  ('EQUIS', '037ccfe3-cc93-43d1-a30a-283a979b2a28'::uuid, 'Sobey School of Business, Saint Mary''s University', 'https://www.efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/')
  ) v(body_code, provider_id, unit, url)
 where exists (select 1 from catalogue.providers p where p.id = v.provider_id and p.lifecycle_status = 'active')
   and not exists (select 1 from catalogue.provider_accreditations a where a.provider_id = v.provider_id and a.body_code = v.body_code
                    and coalesce(a.accredited_unit_name, '') = coalesce(v.unit, ''));

update catalogue.provider_accreditations set status = 'active', verified_at = coalesce(verified_at, now()), updated_at = now()
 where body_code = 'AMBA' and status = 'under_review';

-- B3: IRU is now the 2050 Alliance
update ref.institution_collections
   set name = '2050 Alliance', description = 'Nine Australian universities committed to students, regions and the future of higher education (formerly Innovative Research Universities, renamed May 2026)', updated_at = now()
 where code = 'au_iru' and name = 'Innovative Research Universities';
insert into catalogue.provider_collection_memberships (provider_id, collection_id, membership_type, status, valid_from, verified_at)
select v.provider_id, c.id, 'member', 'active', date '2026-05-27', now()
  from (values ('030992c3-72c6-452d-8a3b-10ceb0fd77f2'::uuid), ('bac82321-ded7-4e10-a71d-b18f3ae4d1c7'::uuid)) v(provider_id)
  join ref.institution_collections c on c.code = 'au_iru'
 where not exists (select 1 from catalogue.provider_collection_memberships m where m.provider_id = v.provider_id and m.collection_id = c.id);
insert into search.course_refresh_requests (course_id, requested_at, requested_by)
select c.id, now(), 's798_2050_alliance' from catalogue.courses c
  join catalogue.provider_collection_memberships m on m.provider_id = c.provider_id and m.status = 'active'
  join ref.institution_collections k on k.id = m.collection_id and k.code = 'au_iru'
 where c.lifecycle_status = 'active'
   and not exists (select 1 from search.course_refresh_requests r where r.course_id = c.id and r.processed_at is null);

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

-- v3 provider answer: the crown beside the accreditations
select pg_temp.cf_edit_def('public.website_v3_provider_item(jsonb)'::regprocedure, '3a48ac0a47003837dda85d6db3773f19',
  array[$o$'accreditations', security.provider_accreditations_v3_v1(v_provider));  -- 18 Nov 2026 (REQ-57)$o$],
  array[$n$'accreditations', security.provider_accreditations_v3_v1(v_provider),  -- 18 Nov 2026 (REQ-57)
                               'accreditation_crown', security.provider_accreditation_crown_v1(v_provider));  -- s798 B1$n$]);

-- v3 course answers: the crown, the study load basis, and the English grades as held
select pg_temp.cf_edit_def('security.course_v3_fields_v1(jsonb,uuid)'::regprocedure, '705df909b55e06f8c57c160fce5f6721',
  array[$o$declare v_load text; v_reason text; v_provider uuid; v_cc text;$o$,
        $o$select c.study_load, c.empty_reason_code, c.provider_id into v_load, v_reason, v_provider from catalogue.courses c where c.id = p_course;$o$,
        $o$    p_item := jsonb_set(p_item, '{provider,accreditations}', security.provider_accreditations_v3_v1(v_provider));$o$,
        $o$  return p_item || jsonb_build_object('study_load', v_load, 'empty_reason_code', v_reason);$o$],
  array[$n$declare v_load text; v_reason text; v_provider uuid; v_cc text; v_load_src text; v_load_ev uuid;$n$,
        $n$select c.study_load, c.empty_reason_code, c.provider_id, c.study_load_source, c.study_load_evidence_id into v_load, v_reason, v_provider, v_load_src, v_load_ev from catalogue.courses c where c.id = p_course;$n$,
        $n$    p_item := jsonb_set(p_item, '{provider,accreditations}', security.provider_accreditations_v3_v1(v_provider));
    p_item := jsonb_set(p_item, '{provider,accreditation_crown}', coalesce(to_jsonb(security.provider_accreditation_crown_v1(v_provider)), 'null'::jsonb));  -- s798 B1$n$,
        $n$  -- s798 B4: the grades held for each English requirement, as held (null when none is held; never derived from a number)
  if p_course is not null and jsonb_typeof(p_item->'english_requirements') = 'array' then
    p_item := jsonb_set(p_item, '{english_requirements}', (select coalesce(jsonb_agg(case when jsonb_typeof(e) = 'object' then e || coalesce((
        select jsonb_build_object('score_grade', r.score_grade, 'subtest_grades', r.subtest_grades)
          from catalogue.course_english_requirements r join ref.english_tests t on t.id = r.english_test_id
         where r.course_id = p_course and r.status = 'active' and t.code = e->>'test_code'
         order by (r.overall_score is not distinct from case when jsonb_typeof(e->'min_overall_score') = 'number' then (e->>'min_overall_score')::numeric end) desc, r.id
         limit 1), jsonb_build_object('score_grade', null, 'subtest_grades', null)) else e end order by o), '[]'::jsonb)
      from jsonb_array_elements(p_item->'english_requirements') with ordinality x(e, o)));
  end if;
  return p_item || jsonb_build_object('study_load', v_load, 'empty_reason_code', v_reason,
    'study_load_basis', case when v_load is null then null when v_load_src = 'register' and v_load_ev is null then 'register_rule' else v_load_src end);  -- s797/s798$n$]);

-- post-checks
do $$
declare v_triple int; v_double int; pi jsonb; ci jsonb; v_stable text; v_course uuid; v_o text;
begin
  if (select count(*) from catalogue.provider_accreditations where body_code = 'AACSB' and status = 'active') <> 58 then
    raise exception 'post-check: % active AACSB rows (expected 58)', (select count(*) from catalogue.provider_accreditations where body_code = 'AACSB' and status = 'active'); end if;
  if (select count(*) from catalogue.provider_accreditations where body_code = 'EQUIS' and status = 'active') <> 31 then raise exception 'post-check: EQUIS rows'; end if;
  if (select count(*) from catalogue.provider_accreditations where body_code = 'AMBA' and status = 'active') <> 13 then raise exception 'post-check: AMBA rows'; end if;
  select count(*) filter (where k = 'triple_crown'), count(*) filter (where k = 'double_crown') into v_triple, v_double
    from (select security.provider_accreditation_crown_v1(p.id) k from (select distinct provider_id id from catalogue.provider_accreditations) p) z;
  if v_triple <> 10 then raise exception 'post-check: % triple crown providers (expected 10)', v_triple; end if;
  if (select count(*) from catalogue.provider_collection_memberships m join ref.institution_collections c on c.id = m.collection_id and c.code = 'au_iru' and c.name = '2050 Alliance' where m.status = 'active') <> 9 then
    raise exception 'post-check: the 2050 Alliance does not have nine members'; end if;
  if exists (select 1 from catalogue.provider_collection_memberships m join ref.institution_collections c on c.id = m.collection_id and c.code = 'au_iru'
              where m.provider_id = '6f5cb7f7-7c70-4c06-970f-f368c3a786e2' and m.status = 'active') then raise exception 'post-check: Charles Darwin is not a member'; end if;
  if not exists (select 1 from catalogue.provider_registrations r where r.provider_id = 'bac82321-ded7-4e10-a71d-b18f3ae4d1c7' and to_jsonb(r)::text like '%00124K%') then
    raise exception 'post-check: the Victoria University added is not CRICOS 00124K'; end if;
  select stable_key into v_stable from catalogue.providers where id = '543b87b8-f0dd-4bc7-80d6-76252cfaabec';
  pi := public.website_v3_provider_item(jsonb_build_object('provider_id', v_stable, 'campuses', '[]'::jsonb));
  if pi->>'accreditation_crown' is distinct from 'triple_crown' or jsonb_array_length(pi->'accreditations') < 3 then raise exception 'post-check: Monash provider answer %', left(pi::text, 300); end if;
  select r.course_id into v_course from catalogue.course_english_requirements r join ref.english_tests t on t.id = r.english_test_id and t.code = 'OET' where r.status = 'active' limit 1;
  ci := security.course_v3_fields_v1(jsonb_build_object('provider', '{}'::jsonb, 'english_requirements', jsonb_build_array(jsonb_build_object('test_code', 'OET', 'min_overall_score', 300), jsonb_build_object('test_code', 'IELTS'))), v_course);
  if not (ci->'english_requirements'->0 ? 'score_grade') or not (ci->'english_requirements'->1 ? 'subtest_grades') or not (ci ? 'study_load_basis') or not (ci->'provider' ? 'accreditation_crown') then
    raise exception 'post-check: course answer %', left(ci::text, 400); end if;
  if jsonb_array_length(security.consumer_api_check_v1()->'drift') <> 0 then raise exception 'post-check: consumer API drift %', security.consumer_api_check_v1()->'drift'; end if;
  v_o := format('AACSB 58, EQUIS 31, AMBA 13 active | triple crown %s, double crown %s | 2050 Alliance 9 members, refresh queued %s | Monash crown %s | OET course basis %s, crown %s, OET grade %s',
    v_triple, v_double, (select count(*) from search.course_refresh_requests where requested_by = 's798_2050_alliance'), pi->>'accreditation_crown',
    coalesce(ci->>'study_load_basis', 'null'), coalesce(ci->'provider'->>'accreditation_crown', 'null'), coalesce(ci->'english_requirements'->0->>'score_grade', 'null (not held)'));
  perform set_config('cf.diag', v_o, true);
end $$;
