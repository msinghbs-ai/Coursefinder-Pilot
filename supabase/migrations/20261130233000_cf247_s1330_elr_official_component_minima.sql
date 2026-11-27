-- CF-247 s1330 (S1-ELR, SS-Programme-Control P0 28 Nov 2026 07:07 AEDT; feedback FB-6.C10-02, FB-6.C01-02, FB-6.C13-03, FB-6.C04-03 and
-- FB-4B.3-02): the English requirement of five reported courses as their official course pages state it. RMIT Master of Marketing (MC197,
-- CRICOS 077512F) and Bachelor of Business (BP343, 106623K); Deakin Master of Health Management (114205F); Victoria University Bachelor of
-- Business (092944A) and Bachelor of Early Childhood Education and Leadership (105139H).
-- English language requirements only; the academic entry correction stays under FB-6.C10-01 (S1-AER-Claude).
--
-- Found live (rolled back, 28 Nov 2026 07:20 AEDT): each course holds IELTS 6.5, PTE 58 and TOEFL iBT 79 (CF-245 replay, Sep 2026) with no
-- component minima, and no Cambridge row; the website and Zoho reads return min_band_score null for all three. No manual lock and no pending
-- Layer 4 item on either course.
-- Official pages, read 28 Nov 2026 (plain HTTP, $0), the same wording on both:
--   "IELTS (Academic): minimum overall band of 6.5 (with no individual band below 6.0)"
--   "Pearson Test of English (Academic) (PTE (A)): minimum score of 58 (with no communication band less than 50)"
--   "TOEFL (Internet Based Test - IBT) for Australia: minimum overall score of 79 (with minimum of 13 in Reading, 12 in Listening, 18 in Speaking and 21 in Writing)"
--   "Cambridge English: Advanced (CAE): minimum of 176 with no less than 169 in any component."
-- Deakin 114205F (deakin.edu.au/course/master-health-management-international): "IELTS overall score of 6.5 (with no band score less than 6.0)
--   in each component of test"; held IELTS 6.5 with no component minima. No PTE or TOEFL stated on the page.
-- VU 092944A (vu.edu.au/courses/bachelor-of-business-bbns/international): "IELTS (or equivalent): Overall score or 6.0 (with no band less than
--   6.0 in Listening, Reading, Writing and Speaking)"; held IELTS 6.0 with no component minima.
-- VU 105139H (vu.edu.au/courses/bachelor-of-early-childhood-education-and-leadership-ebcl/international): "IELTS (or equivalent): Overall score
--   or 6.5 (with no band less than 6.0 in Listening, Reading, Writing and Speaking)"; held IELTS 6.5 with no component minima.
-- Change: the stated component minima are added to the nine existing rows (overall scores unchanged); the two RMIT CAE rows are added, insert
-- only. Nothing is inferred: only these five verified courses change; no PTE or TOEFL is added where the page does not state it. Every row is guarded against its current value; anything else stops the file.
-- Rehearsed rolled back (28 Nov 2026): website_v2_course and zoho_v2_course then return, for the RMIT courses, IELTS 6.5 band 6.0, PTE 58
-- band 50, TOEFL iBT 79 band 12, CAE 176 band 169; for Deakin and VU, IELTS with band 6.0.
-- G1: no job. G2: no operational value. G3: no consumer object changed (checked). Manual locks and active cron checked unchanged. Spend: none.
-- Replaces: the overall-only English rows of these five courses.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1330_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1330_cron on commit drop as select count(*) n from cron.job where active;

-- Guard: the rows are exactly what this correction was written against (overall scores as published, no component minima held, no CAE row,
-- no manual English lock, no pending English Layer 4 item). Anything else stops the whole file.
do $g$
declare r record; v_n int;
begin
  for r in select * from (values
    ('3da7a32e-e0af-421b-9319-c77ec8814878'::uuid, 'e0016887-5587-4153-80b8-971c012c7e72'::uuid, 'IELTS', 6.50),
    ('ae19c911-6835-4f21-ad25-ed53a237bd84'::uuid, 'e0016887-5587-4153-80b8-971c012c7e72'::uuid, 'PTE', 58.00),
    ('4eefa29b-3bba-49ef-ae72-33add7685cd1'::uuid, 'e0016887-5587-4153-80b8-971c012c7e72'::uuid, 'TOEFL_IBT', 79.00),
    ('e07854c8-e6ae-43a4-ab99-994ceb0e6a24'::uuid, 'cfdfa6ab-b297-4cf3-814e-4fb3ca482241'::uuid, 'IELTS', 6.50),
    ('8ee6fdb1-6249-446c-8516-f148045def57'::uuid, 'cfdfa6ab-b297-4cf3-814e-4fb3ca482241'::uuid, 'PTE', 58.00),
    ('f5701cb8-6af7-4790-864f-b2633b96c924'::uuid, 'cfdfa6ab-b297-4cf3-814e-4fb3ca482241'::uuid, 'TOEFL_IBT', 79.00),
    ('d554261d-f1ee-4485-bd95-0f6228d352b6'::uuid, 'ff0bdf22-ba3b-47e5-b583-4714bd4abeb3'::uuid, 'IELTS', 6.50),
    ('9c9879c6-cc93-4ce8-8de1-3b5f33018013'::uuid, '99f6b2c2-ab8f-42c0-b91a-76670356c792'::uuid, 'IELTS', 6.00),
    ('0142f16f-ba05-453c-8a26-90ea6942dda7'::uuid, 'd75b54d3-a88c-4a48-a41a-b62d9b4d9386'::uuid, 'IELTS', 6.50)) v(rid, cid, code, o) loop
    select count(*) into v_n from catalogue.course_english_requirements x join ref.english_tests t on t.id = x.english_test_id
     where x.id = r.rid and x.course_id = r.cid and t.code = r.code and x.overall_score = r.o and x.status = 'active' and coalesce(x.component_scores, '{}'::jsonb) = '{}'::jsonb;
    if v_n <> 1 then raise exception 'guard: row % (% %) is not as expected; nothing changed', r.rid, r.code, r.o; end if;
  end loop;
  if exists (select 1 from catalogue.course_english_requirements x join ref.english_tests t on t.id = x.english_test_id
              where x.course_id in ('e0016887-5587-4153-80b8-971c012c7e72', 'cfdfa6ab-b297-4cf3-814e-4fb3ca482241') and t.code = 'CAE') then
    raise exception 'guard: a CAE row already exists; nothing changed';
  end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity_id in ('e0016887-5587-4153-80b8-971c012c7e72', 'cfdfa6ab-b297-4cf3-814e-4fb3ca482241', 'ff0bdf22-ba3b-47e5-b583-4714bd4abeb3', '99f6b2c2-ab8f-42c0-b91a-76670356c792', 'd75b54d3-a88c-4a48-a41a-b62d9b4d9386')
              and l.field in ('english', 'english_requirements', 'course_english')) then
    raise exception 'guard: an English manual lock exists; nothing changed';
  end if;
  if exists (select 1 from pipeline.layer4_review_items i where i.entity_id in ('e0016887-5587-4153-80b8-971c012c7e72', 'cfdfa6ab-b297-4cf3-814e-4fb3ca482241', 'ff0bdf22-ba3b-47e5-b583-4714bd4abeb3', '99f6b2c2-ab8f-42c0-b91a-76670356c792', 'd75b54d3-a88c-4a48-a41a-b62d9b4d9386')
              and i.field_code = 'course_english' and i.status = 'pending') then
    raise exception 'guard: an English Layer 4 item is pending; nothing changed';
  end if;
end $g$;

-- 1. Component minima on the existing rows. Overall scores are not changed.
update catalogue.course_english_requirements x
   set component_scores = v.comp,
       notes = coalesce(x.notes, '') || ' | Component minima added 28 Nov 2026 from the official course page (' || v.fb || '): ' || v.quote,
       last_verified_at = now()
  from (values
    ('3da7a32e-e0af-421b-9319-c77ec8814878'::uuid, '{"listening": 6.0, "reading": 6.0, "writing": 6.0, "speaking": 6.0}'::jsonb, '"IELTS (Academic): minimum overall band of 6.5 (with no individual band below 6.0)"', 'RMIT; FB-6.C10-02, FB-6.C01-02'),
    ('e07854c8-e6ae-43a4-ab99-994ceb0e6a24'::uuid, '{"listening": 6.0, "reading": 6.0, "writing": 6.0, "speaking": 6.0}'::jsonb, '"IELTS (Academic): minimum overall band of 6.5 (with no individual band below 6.0)"', 'RMIT; FB-6.C10-02, FB-6.C01-02'),
    ('ae19c911-6835-4f21-ad25-ed53a237bd84'::uuid, '{"listening": 50, "reading": 50, "writing": 50, "speaking": 50}'::jsonb, '"Pearson Test of English (Academic) (PTE (A)): minimum score of 58 (with no communication band less than 50)"', 'RMIT; FB-6.C10-02, FB-6.C01-02'),
    ('8ee6fdb1-6249-446c-8516-f148045def57'::uuid, '{"listening": 50, "reading": 50, "writing": 50, "speaking": 50}'::jsonb, '"Pearson Test of English (Academic) (PTE (A)): minimum score of 58 (with no communication band less than 50)"', 'RMIT; FB-6.C10-02, FB-6.C01-02'),
    ('4eefa29b-3bba-49ef-ae72-33add7685cd1'::uuid, '{"listening": 12, "reading": 13, "writing": 21, "speaking": 18}'::jsonb, '"TOEFL (Internet Based Test - IBT) for Australia: minimum overall score of 79 (with minimum of 13 in Reading, 12 in Listening, 18 in Speaking and 21 in Writing)"', 'RMIT; FB-6.C10-02, FB-6.C01-02'),
    ('f5701cb8-6af7-4790-864f-b2633b96c924'::uuid, '{"listening": 12, "reading": 13, "writing": 21, "speaking": 18}'::jsonb, '"TOEFL (Internet Based Test - IBT) for Australia: minimum overall score of 79 (with minimum of 13 in Reading, 12 in Listening, 18 in Speaking and 21 in Writing)"', 'RMIT; FB-6.C10-02, FB-6.C01-02'),
    ('d554261d-f1ee-4485-bd95-0f6228d352b6'::uuid, '{"listening": 6.0, "reading": 6.0, "writing": 6.0, "speaking": 6.0}'::jsonb, '"IELTS overall score of 6.5 (with no band score less than 6.0) in each component of test"', 'Deakin; FB-6.C13-03'),
    ('9c9879c6-cc93-4ce8-8de1-3b5f33018013'::uuid, '{"listening": 6.0, "reading": 6.0, "writing": 6.0, "speaking": 6.0}'::jsonb, '"IELTS (or equivalent): Overall score or 6.0 (with no band less than 6.0 in Listening, Reading, Writing and Speaking)"', 'Victoria University; FB-6.C04-03'),
    ('0142f16f-ba05-453c-8a26-90ea6942dda7'::uuid, '{"listening": 6.0, "reading": 6.0, "writing": 6.0, "speaking": 6.0}'::jsonb, '"IELTS (or equivalent): Overall score or 6.5 (with no band less than 6.0 in Listening, Reading, Writing and Speaking)"', 'Victoria University; FB-4B.3-02')) v(rid, comp, quote, fb)
 where x.id = v.rid;

-- 2. The Cambridge (CAE) requirement the same pages state, beside the IELTS row (same source and stored copy). Insert only.
insert into catalogue.course_english_requirements (course_id, english_test_id, overall_score, component_scores, notes, source_id, evidence_id, confidence,
                                                   source_requirement_key, status, last_verified_at)
select i.course_id, t.id, 176, '{"listening": 169, "reading": 169, "writing": 169, "speaking": 169}'::jsonb,
       'Official RMIT course page, checked 28 Nov 2026 (FB-6.C10-02, FB-6.C01-02): "Cambridge English: Advanced (CAE): minimum of 176 with no less than 169 in any component."',
       i.source_id, i.evidence_id, i.confidence, 'official-page:' || lower(split_part(c.stable_key, ':', 4)) || ':cae', 'active', now()
  from catalogue.course_english_requirements i join catalogue.courses c on c.id = i.course_id cross join ref.english_tests t
 where t.code = 'CAE' and i.id in ('3da7a32e-e0af-421b-9319-c77ec8814878', 'e07854c8-e6ae-43a4-ab99-994ceb0e6a24')
on conflict (course_id, english_test_id) do nothing;

-- 3. Search documents for the two courses.
select search.refresh_course_enrichment_scoped_v1(array['e0016887-5587-4153-80b8-971c012c7e72', 'cfdfa6ab-b297-4cf3-814e-4fb3ca482241', 'ff0bdf22-ba3b-47e5-b583-4714bd4abeb3', '99f6b2c2-ab8f-42c0-b91a-76670356c792', 'd75b54d3-a88c-4a48-a41a-b62d9b4d9386']::uuid[], true);

do $c$
declare v jsonb; v_n int;
begin
  select count(*) into v_n from catalogue.course_english_requirements x join ref.english_tests t on t.id = x.english_test_id
   where x.course_id in ('e0016887-5587-4153-80b8-971c012c7e72', 'cfdfa6ab-b297-4cf3-814e-4fb3ca482241', 'ff0bdf22-ba3b-47e5-b583-4714bd4abeb3', '99f6b2c2-ab8f-42c0-b91a-76670356c792', 'd75b54d3-a88c-4a48-a41a-b62d9b4d9386') and x.status = 'active'
     and (select count(*) from jsonb_object_keys(x.component_scores) k where k in ('listening', 'reading', 'writing', 'speaking')) = 4;
  if v_n <> 11 then raise exception 'post-check: expected 11 active rows with four component minima, found %', v_n; end if;
  if (select count(*) from cron.job where active) <> (select n from s1330_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1330_locks) then raise exception 'post-check: the manual locks changed'; end if;
  v := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
end $c$;
