-- CF-247 Macquarie staging addresses (handover 3 Nov 2026 Priority 3 item 11). FOR A PLATFORM ADMIN DECISION (spends about 8 Firecrawl credits).
-- Eight active Macquarie scholarships are read from students.mq.edu.au/study/course/overseas/staging/details/... (7 published, 1 unpublished);
-- the pages state start years 2016 to 2019. Stored evidence holds no official (mq.edu.au) page for any of them except the Vice-Chancellor's
-- International Scholarship, already published as a347e086 from the official page (held ref 1184 duplicates it: the duplicate close route).
-- No free read was possible from this session, so no official replacement address can be proposed with provenance.
-- Effect: asks the existing "Read again" route (pipeline.scholarship_pages.requested_at) to read the eight pages now (their scheduled re-read is
-- 12 Nov 2026 to 11 Jan 2027). A page that has moved or now opens elsewhere is recorded in pipeline.scholarship_source_moves (F7) and stored as
-- evidence; nothing is withdrawn, replaced or unpublished by this file. A replacement address is proposed only from an official page held as evidence.
-- PASTE FILE. Not applied by any migration. Sets requested_at on exactly 8 rows. Nothing is deleted.
begin;
do $$
declare v_n int;
  v_ids uuid[] := array['863c8914-a6ec-521d-a7a1-af352d6562f2', '95906adb-c369-51f3-a7d0-894648416ddd', 'f04dd87f-8128-59c9-a21b-b771efc7c2b1', '4ed7a374-6ace-5daf-ad9f-b1ae997e983a',
                        '094b89a5-4b52-5a28-a077-2681fe24ad1f', '6426899a-446b-58bb-adcc-7606efb645f1', 'a9b90b2b-a7c0-59da-a4c3-775f13349ae8', '9184031a-188f-50c7-af48-b1253bc3fdf9']::uuid[];
begin
  select count(*) into v_n from pipeline.scholarship_pages sp join scholarship.scholarships s on s.id = sp.scholarship_id
   where sp.scholarship_id = any (v_ids) and sp.url ~* '^https://students\.mq\.edu\.au/study/course/overseas/staging/details/' and s.lifecycle_status = 'active'
     and s.provider_id = '188103a5-1aba-4f99-bd3e-0416659086d3' and sp.requested_at is null;
  if v_n <> 8 then raise exception 'guard: % of the 8 staging-address scholarships are active, on the staging path and not yet requested; nothing changed', v_n; end if;
  update pipeline.scholarship_pages set requested_at = now() where scholarship_id = any (v_ids) and requested_at is null;
  get diagnostics v_n = row_count;
  if v_n <> 8 then raise exception 'guard: % rows requested, expected 8; rolled back', v_n; end if;
  raise notice 'requested 8 re-reads of Macquarie staging-address scholarships';
end $$;
commit;
