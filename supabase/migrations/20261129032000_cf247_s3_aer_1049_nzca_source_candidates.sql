-- CF-247 S3 / Admin #1049, named NZ/CA acquisition-only Wave 1, 25 Nov 2026.
-- Replaces: nothing. Extends existing source/reader pipeline only.
-- Retires: nothing. Preserves existing readers, locks and queues.
-- Steps 1-2 only. Exact provider cohort from Admin Execution Register.
-- Registers 21 scope-appropriate first-party source CANDIDATES within the existing
-- entry matrix source table, never claims source bytes were stored. Nine named
-- providers are HELD:NO_PROVED_APPLICABLE_SOURCE (six NZ plus three unsuitable domestic/apprenticeship/closed-intake sources; Admin #1049).
-- Never create source/evidence IDs or hashes before existing acquisition completes.
-- No reader, AI, matrix admission, consumer API, new queue/cron, spending or
-- Canadian country-wide activation. All existing IDs, claims and locks retained.
set local lock_timeout='5s';
set local statement_timeout='120s';

do $guard$
declare g jsonb := security.consumer_api_check_v1();
begin
 if (g->>'functions')::int <> 75 or (g->>'relations')::int <> 48
   or jsonb_array_length(coalesce(g->'drift','[]'::jsonb))<>0 then
    raise exception 'G3 drift: %',g;
 end if;
 if (select count(*) from cron.job where active)>140 then
   raise exception 'active cron ceiling exceeded';
 end if;
end $guard$;

do $register$
declare r record; check_result jsonb;
begin
 for r in select * from (values
('ea5a3fa6-31f4-4553-9cfd-6bff49c36a6b'::uuid,'NZ','https://www.eit.ac.nz/programmes/bachelor-of-nursing/','EIT Bachelor of Nursing published academic entry criteria'),
('38f8ea71-2269-407c-aab6-68a5f09fc01a'::uuid,'NZ','https://www.toiohomai.ac.nz/study/course/bachelor-nursing','Toi Ohomai Bachelor of Nursing academic entry criteria'),
('d72e0120-a3a2-4909-8ddf-bcad1ec60150'::uuid,'NZ','https://www.northtec.ac.nz/info/understanding-qualifications','NorthTec published qualification-level entry criteria'),
('5c067273-5f41-4da0-a16c-b2eac17f4306'::uuid,'NZ','https://www.wananga.ac.nz/study/degrees/bachelor-of-education/entry-requirements/','Awanuiarangi Bachelor of Education university entrance and qualifications'),
('0ede4eef-4117-4362-8a64-131efcb31c38'::uuid,'NZ','https://www.temahiako.org.nz/qualifications/core-service-sector-skills-micro-credential-level-3','Te Mahi Ako Level 3 microcredential workplace entry conditions'),
('425b1fad-a4ef-4a21-8590-c7fa9b671107'::uuid,'CA','https://www.canadorecollege.ca/programs/entrepreneurship-management/how-to-apply','Canadore international secondary study equivalency and programme admission guide'),
('d5a30625-74a1-43ff-83bb-81b2bf587cb2'::uuid,'CA','https://cotr.bc.ca/enrolment-services/registration-and-admissions/course-equivalency/','College of the Rockies published academic equivalencies'),
('60b274ad-14cf-4343-9e1a-9779fd5466b1'::uuid,'CA','https://www.bcit.ca/programs/airline-and-flight-operations-commercial-pilot-fixed-wing-diploma-full-time-100adipma/','BCIT course-specific academic admission thresholds'),
('9e46baf2-694b-4d79-889e-b956d144c930'::uuid,'CA','https://burmanu.ca/admissionrequirements/international','Burman international academic admissions by school system'),
('6cc65e88-af6c-4fa9-b4a8-512d37b01d4f'::uuid,'CA','https://selkirk.ca/international/international-students/apply','Selkirk international direct entry and programme prerequisites'),
('8bcdcee6-a7cb-4731-83cc-4f116e423914'::uuid,'CA','https://ecuad.ca/degree-programs/undergraduate/apply/application-requirements/','Emily Carr international secondary qualifications GPA and A level equivalencies'),
('5a2a154f-1e11-4851-aa96-0a172ba5314d'::uuid,'CA','https://www.vcc.ca/international-student/apply-to-vcc/admission-requirement/','VCC international academic and Grade 12 equivalency requirements'),
('ea8e3df4-564a-4b12-907d-c8af9d38865e'::uuid,'CA','https://www.auarts.ca/future-students/international-students/international-applicants-admission-requirements','AUArts British BTEC USA and general international qualification equivalencies'),
('21818449-895c-45eb-82a6-b91bee0cece0'::uuid,'CA','https://www.nwpolytech.ca/admission/academic-program-requirements','Northwestern Polytechnic programme subject and minimum score matrix'),
('1386ffc1-e991-463c-bb22-39380cca67a1'::uuid,'CA','https://www.nic.bc.ca/admissions/international-students/admission-requirements/index.html','North Island College international programme admission requirements'),
('0af6c3f4-752e-42e3-b818-74c2eaf31671'::uuid,'CA','https://www.mohawkcollege.ca/international-students/apply-to-mohawk/how-to-apply','Mohawk international OSSD academic equivalency and programme guide'),
('b0f95837-8e85-4936-8166-b40b48e1044f'::uuid,'CA','https://www.jibc.ca/procedure/admissions','JIBC documented academic entry procedure and Grade 12 equivalencies'),
('ca2dacb0-297a-4067-a899-59eb7b381ae6'::uuid,'CA','https://www.yukonu.ca/international/future-students/admission','Yukon University international programme academic minimum matrix'),
('3a48beb7-d61f-468c-b93c-6fa61ab96921'::uuid,'CA','https://www.coastmountaincollege.ca/programs/study/information-technology','Coast Mountain College IT programme academic requirements'),
('a29ecd44-67c5-4839-820e-3a5778dbc1df'::uuid,'CA','https://www.oldscollege.ca/admissions/international-admissions/index.html','Olds College international senior secondary academic credentials'),
('e7af5ef9-f719-4b94-b6b5-abf88071b9ce'::uuid,'CA','https://cnc.bc.ca/oreg/admission-requirements','College of New Caledonia general academic and credential equivalency policy')
 ) x(provider_id,country,url,title)
 loop
   if not exists(select 1 from catalogue.providers p join ref.countries c
                 on c.id=p.country_id where p.id=r.provider_id
                 and c.iso_alpha2=r.country and r.country in ('NZ','CA')) then
     raise exception 'provider country mismatch %',r.provider_id;
   end if;
   check_result:=security.aer_source_check_v1(r.provider_id,r.url,
     array['course_specific']::text[],'url',null,null);
   if coalesce((check_result->>'ok')::boolean,false) is not true
      or check_result->>'ownership'<>'official_host' then
     raise exception 'source official-host check failed %: %',r.provider_id,check_result;
   end if;
   insert into pipeline.entry_matrix_sources(provider_id,url,title,rank,found_via)
   values(r.provider_id,r.url,left(r.title,200),1,'manual')
   on conflict(provider_id,url) do nothing;
 end loop;
end $register$;
-- NO claims of fetched/evidenced pages. Existing authorised fetch/record
-- route must later populate evidence_id/content_hash/storage_path and satisfy
-- provider/edition/qualification scope checks before Step 2 is complete.
