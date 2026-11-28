-- CF-247 s1336 (S1-ELR, instruction PC-20261128-0931-S1-ELR, SS-Programme-Control 28 Nov 2026): the official equivalent English tests of
-- Swinburne Bachelor of Business (CRICOS 063366D, 088382J; feedback FB-6.C02-02) and the IELTS band minimum of Victoria University Bachelor of
-- Early Childhood Education and Leadership (CRICOS 115486F, provider record 02475D; feedback FB-4B.3-02). English language requirements only.
--
-- Found live (rolled back, 28 Nov 2026 10:00 AEDT):
--   * Swinburne 063366D and 088382J hold IELTS 6.0 with all four bands 6.0 (course page), and no other test. The course page states that IELTS
--     "or equivalent measures available at English language requirements" (swinburne.edu.au/study/international/apply/entry-requirements/).
--     That official page's row "Undergraduate: other bachelor degrees" gives IELTS 6.0 with no band under 6.0, PTE Academic 50 with no
--     communicative skill under 50, TOEFL iBT 64 with Reading 13, Listening 12, Speaking 18 and Writing 21, and Cambridge C1 Advanced 169 with
--     none under 169. Bachelor of Business is not in that page's higher-requirement groups (education, exercise and sport science, law,
--     psychological sciences, psychology honours, professional degrees) or its named higher-requirement courses. Its IELTS row equals the
--     course's own IELTS. Read 28 Nov 2026 (plain HTTP, $0).
--   * The stored elr-central reading of that page gave misaligned undergraduate values (PTE 66, partial IELTS bands), so it was rightly never
--     applied; nothing here comes from it.
--   * Swinburne's approved policy 94f140fa gives IELTS only, so s1047 inheritance had nothing to add.
--   * VU 115486F holds IELTS 6.5 with no band minimum (policy row). The official course page names both CRICOS codes ("CRICOS:105139H,
--     115486F"), and its international page states "IELTS (or equivalent): Overall score or 6.5 (with no band less than 6.0 in Listening,
--     Reading, Writing and Speaking)". It states no PTE or TOEFL score, so none is added. 105139H was corrected the same way in s1330.
-- Change: PTE, TOEFL iBT and CAE rows for the two Swinburne courses (insert only; same source and stored copy as each course's IELTS row);
-- the IELTS band minimum 6.0 on the VU 115486F row (overall unchanged). Every row is guarded against its current value, no manual lock and no
-- pending English Layer 4 item. Nothing inferred: only these three verified courses change.
-- G1: no job. G2: no operational value. G3: no consumer object changed (checked). Manual locks and active cron checked unchanged. Spend: none.
-- Replaces: the IELTS-only English of the two Swinburne courses and the band-less IELTS row of VU 115486F.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1(); v_n int;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  -- the two Swinburne IELTS rows and the VU row are exactly as read
  select count(*) into v_n from catalogue.course_english_requirements x
   where x.status = 'active' and ((x.id in ('49ae6649-43ba-480a-8ac6-389cd8b40052', 'e066eb22-8bab-48a8-9261-59bd713923cd') and x.overall_score = 6.00
          and x.component_scores = '{"reading": 6, "writing": 6, "speaking": 6, "listening": 6}'::jsonb)
       or (x.id = '245cc917-07f0-4f6e-9587-754a0bf1614e' and x.overall_score = 6.50 and coalesce(x.component_scores, '{}'::jsonb) = '{}'::jsonb));
  if v_n <> 3 then raise exception 'guard: the rows are not as read (found % of 3); nothing changed', v_n; end if;
  if exists (select 1 from catalogue.course_english_requirements x join ref.english_tests t on t.id = x.english_test_id
              where x.course_id in ('eb400b44-56e8-4258-9817-4e7be8fb8431', '6cc924de-88cd-4143-bad9-efda3dfb7d9c') and t.code in ('PTE', 'TOEFL_IBT', 'CAE')) then
    raise exception 'guard: a Swinburne PTE, TOEFL or CAE row already exists; nothing changed';
  end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity_id in ('eb400b44-56e8-4258-9817-4e7be8fb8431', '6cc924de-88cd-4143-bad9-efda3dfb7d9c', '272a8517-482d-40e2-a8ff-feaf7fe29608')
              and l.field in ('english', 'english_requirements', 'course_english'))
     or exists (select 1 from pipeline.layer4_review_items i where i.entity_id in ('eb400b44-56e8-4258-9817-4e7be8fb8431', '6cc924de-88cd-4143-bad9-efda3dfb7d9c', '272a8517-482d-40e2-a8ff-feaf7fe29608')
              and i.field_code = 'course_english' and i.status = 'pending') then
    raise exception 'guard: an English lock or pending Layer 4 item exists; nothing changed';
  end if;
end $g$;
create temp table s1336_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1336_cron on commit drop as select count(*) n from cron.job where active;

-- 1. Swinburne: the official equivalent tests of "Undergraduate: other bachelor degrees", beside each course's IELTS row. Insert only.
insert into catalogue.course_english_requirements (course_id, english_test_id, overall_score, component_scores, notes, source_id, evidence_id, confidence,
                                                   source_requirement_key, status, last_verified_at)
select i.course_id, t.id, v.o, v.comp,
       'Official Swinburne international English requirements page, row "Undergraduate: other bachelor degrees", checked 28 Nov 2026 (FB-6.C02-02): ' || v.quote
       || ' The course page refers to these equivalent measures.',
       i.source_id, i.evidence_id, i.confidence, 'official-page:' || lower(split_part(c.stable_key, ':', 4)) || ':' || lower(v.code), 'active', now()
  from catalogue.course_english_requirements i join catalogue.courses c on c.id = i.course_id
  cross join (values
    ('PTE', 50::numeric, '{"listening": 50, "reading": 50, "writing": 50, "speaking": 50}'::jsonb, 'PTE Academic 50, no communicative skill under 50.'),
    ('TOEFL_IBT', 64::numeric, '{"listening": 12, "reading": 13, "writing": 21, "speaking": 18}'::jsonb, 'TOEFL iBT 64, Reading 13, Listening 12, Speaking 18, Writing 21.'),
    ('CAE', 169::numeric, '{"listening": 169, "reading": 169, "writing": 169, "speaking": 169}'::jsonb, 'Cambridge C1 Advanced 169, none under 169.')) v(code, o, comp, quote)
  join ref.english_tests t on t.code = v.code
 where i.id in ('49ae6649-43ba-480a-8ac6-389cd8b40052', 'e066eb22-8bab-48a8-9261-59bd713923cd')
on conflict (course_id, english_test_id) do nothing;

-- 2. VU 115486F: the IELTS band minimum its official course page states. Overall unchanged.
update catalogue.course_english_requirements x
   set component_scores = '{"listening": 6.0, "reading": 6.0, "writing": 6.0, "speaking": 6.0}'::jsonb,
       notes = coalesce(x.notes, '') || ' | Component minima added 28 Nov 2026 from the official course page (VU, CRICOS 105139H and 115486F; FB-4B.3-02): "IELTS (or equivalent): Overall score or 6.5 (with no band less than 6.0 in Listening, Reading, Writing and Speaking)"',
       last_verified_at = now()
 where x.id = '245cc917-07f0-4f6e-9587-754a0bf1614e';

-- 3. Search documents for the three courses.
select search.refresh_course_enrichment_scoped_v1(array['eb400b44-56e8-4258-9817-4e7be8fb8431', '6cc924de-88cd-4143-bad9-efda3dfb7d9c', '272a8517-482d-40e2-a8ff-feaf7fe29608']::uuid[], true);

do $c$
declare v jsonb; v_n int;
begin
  select count(*) into v_n from catalogue.course_english_requirements x
   where x.course_id in ('eb400b44-56e8-4258-9817-4e7be8fb8431', '6cc924de-88cd-4143-bad9-efda3dfb7d9c', '272a8517-482d-40e2-a8ff-feaf7fe29608') and x.status = 'active'
     and (select count(*) from jsonb_object_keys(x.component_scores) k where k in ('listening', 'reading', 'writing', 'speaking')) = 4;
  if v_n <> 9 then raise exception 'post-check: expected 9 active rows with four component minima, found %', v_n; end if;
  if (select count(*) from cron.job where active) <> (select n from s1336_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1336_locks) then raise exception 'post-check: the manual locks changed'; end if;
  v := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
end $c$;
