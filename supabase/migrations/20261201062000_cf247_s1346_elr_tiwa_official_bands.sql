-- CF-247 s1346 (S1-ELR, addenda PC-20261128-TIWA-INSTITUTION-S1-ELR, PC-20261128-1050-S1-ELR and PC-20261128-DOT-STORAGE-IMPLEMENT-S1-ELR,
-- SS-Programme-Control 28 Nov 2026): the IELTS band minima that TAFE International Western Australia (TIWA, CRICOS provider 00020G) states on
-- its official admission requirements page, for four existing IELTS rows that hold no band minimum. English language requirements only.
--
-- Source: https://www.tafeinternational.wa.edu.au/tafe-courses/tafe-admission-requirements ("Last updated on September 9, 2026"), captured
-- by DOT 27 Nov 2026 23:44 UTC (plain HTTP, sha256 80b2fa34344ffd9a96ea9e0a04778cd8b88d86003cf0fc5b477393f67c7d9c83, institutional package
-- DOT-TIWA-00020G). The same page is the source of the approved TIWA English policy e53f450b (stored copy ba83a96a, 2 Oct 2026). It states:
--   "The basic level of English proficiency required for entry into most TAFE courses is the equivalent of Academic IELTS 6.0, with no band
--    lower than 5.0." and, under "Courses with higher English requirements":
--   "Nursing: IELTS 7.0 (Academic) with no band below 7.0, excluding writing where the minimum is 6.5".
-- Found live (rolled back, 28 Nov 2026 12:30 AEDT): 102 active TIWA courses, 88 with English. 76 hold IELTS 6.0 with every band 5.0 and five
-- Early Childhood and maritime courses hold their course-page bands; these four rows hold an IELTS overall with no band:
--   * Diploma of Nursing 111837J, IELTS 7.0 (row 61986991; its PTE 66 and TOEFL iBT 94 rows are left as they are: the page gives no Nursing
--     equivalents). The approved policy's Nursing exception reads 6.5 in every band, which is not what the page prints; it never wrote a row.
--   * Certificate IV in Business 107276E, Certificate IV in Electronics and Communications 119536B, Certificate III in Carpentry 121507M: IELTS
--     6.0, the page's standard level, which is 6.0 with no band lower than 5.0 (the approved policy e53f450b gives the same default). None is in
--     the page's higher-requirement list (Early Childhood Education and Care, Nursing).
-- Change: the band minima on those four rows; the overall scores are unchanged. Every row is guarded against its current value, no manual lock
-- and no pending English Layer 4 item. Not changed and held: Certificate IV in Preparation for Health and Nursing Studies 111816C (IELTS 7.0
-- from its course page; the page's "Nursing" entry does not name it), the equivalent tests the page lists (the approved policy carries IELTS
-- only, and a person decides a new reading), the 14 courses with no stored course page, CELPIP (overall 161, quarantined) and OET (1210).
-- The four courses are unpublished, so no consumer output changes until they are published.
-- G1: no job. G2: no operational value. G3: no consumer object changed (checked). Manual locks and active cron checked unchanged. Spend: none.
-- Replaces: the band-less IELTS rows of these four TIWA courses.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1(); v_n int;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  -- the four IELTS rows are exactly as read: active, overall as stated, no band minimum
  select count(*) into v_n from catalogue.course_english_requirements x
   where x.status = 'active' and coalesce(x.component_scores, '{}'::jsonb) = '{}'::jsonb
     and ((x.id = '61986991-2851-40de-91d2-24241e4a0732' and x.course_id = 'd5e51eb6-445f-4f1f-a7c5-f65c5b0935ea' and x.overall_score = 7.00)
       or (x.id = '0321767a-b91b-4711-91fb-548560337bb8' and x.course_id = 'c663bd18-92b2-4933-bfa9-e23b10826361' and x.overall_score = 6.00)
       or (x.id = '7a026fca-da0b-4c1a-b63f-6588a22aac52' and x.course_id = '7862ae1d-1667-43af-9dc2-94dcb9507f35' and x.overall_score = 6.00)
       or (x.id = 'cd920ac5-a0e4-4690-b23d-431109ee5b16' and x.course_id = '8557d538-f56d-4e27-b31d-083eae8f85e6' and x.overall_score = 6.00));
  if v_n <> 4 then raise exception 'guard: the rows are not as read (found % of 4); nothing changed', v_n; end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity_id in ('d5e51eb6-445f-4f1f-a7c5-f65c5b0935ea', 'c663bd18-92b2-4933-bfa9-e23b10826361',
                                                                           '7862ae1d-1667-43af-9dc2-94dcb9507f35', '8557d538-f56d-4e27-b31d-083eae8f85e6')
              and l.field in ('english', 'english_requirements', 'course_english'))
     or exists (select 1 from pipeline.layer4_review_items i where i.entity_id in ('d5e51eb6-445f-4f1f-a7c5-f65c5b0935ea', 'c663bd18-92b2-4933-bfa9-e23b10826361',
                                                                                    '7862ae1d-1667-43af-9dc2-94dcb9507f35', '8557d538-f56d-4e27-b31d-083eae8f85e6')
              and i.field_code = 'course_english' and i.status = 'pending') then
    raise exception 'guard: an English lock or pending Layer 4 item exists; nothing changed';
  end if;
end $g$;
create temp table s1346_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1346_cron on commit drop as select count(*) n from cron.job where active;

-- 1. Diploma of Nursing 111837J: the Nursing band minima the page prints. Overall unchanged.
update catalogue.course_english_requirements x
   set component_scores = '{"listening": 7.0, "reading": 7.0, "writing": 6.5, "speaking": 7.0}'::jsonb,
       notes = coalesce(x.notes, '') || ' | Component minima added 28 Nov 2026 from the official TIWA admission requirements page (last updated 9 Sep 2026): "Nursing: IELTS 7.0 (Academic) with no band below 7.0, excluding writing where the minimum is 6.5"',
       last_verified_at = now()
 where x.id = '61986991-2851-40de-91d2-24241e4a0732';

-- 2. The three courses at the page's standard level: IELTS 6.0 with no band lower than 5.0. Overall unchanged.
update catalogue.course_english_requirements x
   set component_scores = '{"listening": 5.0, "reading": 5.0, "writing": 5.0, "speaking": 5.0}'::jsonb,
       notes = coalesce(x.notes, '') || ' | Component minima added 28 Nov 2026 from the official TIWA admission requirements page (last updated 9 Sep 2026): "The basic level of English proficiency required for entry into most TAFE courses is the equivalent of Academic IELTS 6.0, with no band lower than 5.0"',
       last_verified_at = now()
 where x.id in ('0321767a-b91b-4711-91fb-548560337bb8', '7a026fca-da0b-4c1a-b63f-6588a22aac52', 'cd920ac5-a0e4-4690-b23d-431109ee5b16');

-- 3. Search documents for the four courses.
select search.refresh_course_enrichment_scoped_v1(array['d5e51eb6-445f-4f1f-a7c5-f65c5b0935ea', 'c663bd18-92b2-4933-bfa9-e23b10826361',
                                                        '7862ae1d-1667-43af-9dc2-94dcb9507f35', '8557d538-f56d-4e27-b31d-083eae8f85e6']::uuid[], true);

do $c$
declare v jsonb; v_n int;
begin
  select count(*) into v_n from catalogue.course_english_requirements x
   where x.id in ('61986991-2851-40de-91d2-24241e4a0732', '0321767a-b91b-4711-91fb-548560337bb8', '7a026fca-da0b-4c1a-b63f-6588a22aac52', 'cd920ac5-a0e4-4690-b23d-431109ee5b16')
     and x.status = 'active'
     and (select count(*) from jsonb_object_keys(x.component_scores) k where k in ('listening', 'reading', 'writing', 'speaking')) = 4;
  if v_n <> 4 then raise exception 'post-check: expected 4 active rows with four component minima, found %', v_n; end if;
  if (select count(*) from cron.job where active) <> (select n from s1346_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1346_locks) then raise exception 'post-check: the manual locks changed'; end if;
  v := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
end $c$;
