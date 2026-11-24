-- CF-247 S3-AER NZ-only source recovery, 24 Nov 2026; AER-FU-09 / Admin #1025.
-- WITT's old registered prospectus path returned "gone". The first-party 2026
-- international prospectus is NOT an academic country matrix; the provider
-- explicitly directs applicants to each programme's academic regulations.
-- The Bachelor of Applied Management (Level 7) entry page below prints
-- NCEA Level 3 subject and credit minima, University Entrance or relevant
-- equivalent pathways. Live catalogue course 19244bd4-3692-4334-bfd4-151c25c9dead
-- is the exact programme identity; it still needs the normal link verifier.
-- Existing security.aer_source_check_v1 confirms official_host on witt.ac.nz.
-- This registers a NEW candidate in the EXISTING pipeline, leaving the old
-- failed source untouched. An actual PDF capture, source/edition suitability,
-- content hash, extraction and admissions remain subject to existing readers.
-- G3, manual locks, AI/Firecrawl spending rules and cron are unchanged.
-- Never claim this source supplies applicant-country equivalences or a completed admission.
set local lock_timeout = '5s';
do $guards$
declare v jsonb;
begin
  v := security.consumer_api_check_v1();
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48
     or jsonb_array_length(coalesce(v->'drift','[]'::jsonb)) <> 0 then
    raise exception 'G3 consumer contract changed: %', v;
  end if;
  if (select count(*) from cron.job where active) > 140 then
    raise exception 'active cron ceiling breached';
  end if;
  v := security.aer_source_check_v1(
    'fd76fddc-fc8e-496d-bf89-c466d8efeb17'::uuid,
    'https://www.witt.ac.nz/study/administration-and-business-management/business-and-management/bachelor-of-applied-management-level-7',
    array['course_specific']::text[], 'url', null, null
  );
  if coalesce((v->>'ok')::boolean,false) is not true
     or v->>'ownership' <> 'official_host' then
    raise exception 'WITT official source validation refused: %', v;
  end if;
end $guards$;

insert into pipeline.entry_matrix_sources(provider_id,url,title,rank,found_via)
select 'fd76fddc-fc8e-496d-bf89-c466d8efeb17'::uuid,
       'https://www.witt.ac.nz/study/administration-and-business-management/business-and-management/bachelor-of-applied-management-level-7',
       'WITT Bachelor of Applied Management Level 7 — official academic entry criteria and equivalence',
       1,'manual'
where exists (
  select 1 from catalogue.providers p join ref.countries c on c.id=p.country_id
  where p.id='fd76fddc-fc8e-496d-bf89-c466d8efeb17'::uuid
    and c.iso_alpha2='NZ'
)
on conflict(provider_id,url) do nothing;

-- Only a source candidate registration. Existing permitted fetch/read dispatchers
-- must acquire the bytes into immutable evidence before any extraction is claimed.

-- Existing claimed NZ providers with previously stored general or unread sources:
-- Open Polytechnic programme source IDs refer to live catalogue courses OP7001,
-- 2264 (Graduate Certificate in Business), and 3466 respectively; no inferred
-- source-to-course link is created. Reader must prove exact link or hold.
-- first-party course/programme documents supplement, never overwrite, their old
-- sources. No country/qualification equivalence is inferred from generic levels.
do $sources$
declare r record; v jsonb;
begin
  for r in
    select * from (values
      ('5e1a25b3-94d3-4e9a-8cc1-98dacd3bfd62'::uuid,
       'https://www.nzma.ac.nz/courses/pharmacy-overview/combined-international',
       'NZMA Pharmacy Levels 3 to 5 International programme — printed NCEA Level 2 or equivalent prerequisite'),
      ('5e1a25b3-94d3-4e9a-8cc1-98dacd3bfd62'::uuid,
       'https://www.nzma.ac.nz/courses/pharmacy-overview/introduction-to-pharmacy-level-3',
       'NZMA Pharmacy Introduction Level 3 International programme — printed NCEA Level 2 prerequisite'),
      ('29fabe13-e9fe-497c-ae2b-bd6d08b5c46b'::uuid,
       'https://www.whitecliffe.ac.nz/wp-content/uploads/2026/03/Entry-requirements-3.pdf',
       'Whitecliffe official academic entry requirements programme matrix 2026'),
      ('fe2e938f-4e46-427f-ac1b-73a650b1a14d'::uuid,
       'https://nzse.ac.nz/wp-content/uploads/2026/11/InternationalProspectus-2027-NZSEG.pdf',
       'NZSE 2027 international programme prospectus with course-specific entry criteria'),
      ('f6b3e3a9-cc45-4770-8fb6-0d068f50732f'::uuid,
       'https://www.openpolytechnic.ac.nz/qualifications-and-courses/op7411-graduate-certificate-in-business/tab/QT02/',
       'Open Polytechnic Graduate Certificate in Business — published Bachelor degree entry prerequisite'),
      ('f6b3e3a9-cc45-4770-8fb6-0d068f50732f'::uuid,
       'https://www.openpolytechnic.ac.nz/qualifications-and-courses/op700101-bachelor-of-business/tab/QT02/',
       'Open Polytechnic Bachelor of Business — published University Entrance or approved diploma prerequisite'),
      ('f6b3e3a9-cc45-4770-8fb6-0d068f50732f'::uuid,
       'https://www.openpolytechnic.ac.nz/qualifications-and-courses/nz3466-new-zealand-diploma-in-library-and-information-studies-level-5/tab/QT02/',
       'Open Polytechnic NZ Diploma Library & Information Studies L5 — published UE/Level 4/overseas equivalent')
    ) as src(provider_id,url,title)
  loop
    if not exists(select 1 from catalogue.providers p join ref.countries c on c.id=p.country_id
                 where p.id=r.provider_id and c.iso_alpha2='NZ') then
      raise exception 'NZ identity scope lost for source %',r.url;
    end if;
    v := security.aer_source_check_v1(r.provider_id,r.url,array['course_specific']::text[],'url',null,null);
    if coalesce((v->>'ok')::boolean,false) is not true or v->>'ownership'<>'official_host' then
      raise exception 'official NZ source refused for %: %',r.url,v;
    end if;
    insert into pipeline.entry_matrix_sources(provider_id,url,title,rank,found_via)
    values (r.provider_id,r.url,left(r.title,200),1,'manual')
    on conflict(provider_id,url) do nothing;
  end loop;
end $sources$;

-- Extraction and machine checks must still prove the printed programme, a valid
-- source quote and named applicant scope. No row here is an admission.
