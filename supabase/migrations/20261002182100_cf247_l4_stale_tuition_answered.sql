-- CF-247 (2 Oct 2026). Platform Admin, 15:02, with screenshots of the UQ page and a Layer 4 tuition review: "Uq website
-- clearly shows $10,520 how is the json getting additional fees not even listen on the page?"
-- Found: the UQ page carries two views, domestic and international, and remembers which one a visitor chose. $10,520
-- (2026) is the domestic view (a Commonwealth supported place); AUD $60,952 (2027) is the international view and the
-- page's own "Fees A$60952" summary. The catalogue already holds A$60,952 as the international tuition, which is correct.
-- The review item was left by the retired Layer 2 pipeline (extractor layer2-course-fact-extract-v2.4, 26 Aug), which
-- could not tell the two views apart. Four such items are still waiting although the fee already recorded is one of
-- the fees they found on the page, and the current reader independently reads the same amount from the same page.
-- They are closed as superseded (kept, with the reason); nothing in the catalogue changes and no value entered by hand
-- is touched.
update pipeline.layer4_review_items r
   set status = 'superseded', decided_at = now(),
       layer3_state = coalesce(r.layer3_state, '{}'::jsonb) || jsonb_build_object('superseded', jsonb_build_object(
         'reason', 'Already answered: the fee recorded for this course is one of the fees found on this page (retired Layer 2 pipeline item).',
         'recorded_amount', (select f.amount from catalogue.course_fees f where f.course_id = r.entity_id and f.fee_type = 'provider_current_tuition' and f.status = 'active' order by f.created_at desc limit 1),
         'at', now(), 'ref', 'CF-247 2 Oct 2026 15:02'))
 where r.status = 'pending' and r.field_code = 'provider_current_tuition_validation'
   and r.layer2_state->>'extraction_worker' like 'layer2-course-fact-extract%'
   and exists (select 1 from catalogue.course_fees f
                where f.course_id = r.entity_id and f.fee_type = 'provider_current_tuition' and f.status = 'active'
                  and exists (select 1 from jsonb_array_elements(coalesce(r.layer2_state->'fee_candidates', '[]'::jsonb)) c
                               where (c->>'amount')::numeric = f.amount)
                  and exists (select 1 from pipeline.coverage_course_pages g
                               where g.course_id = r.entity_id and g.read_status = 'read' and (g.candidates->'fee'->>'value')::numeric = f.amount));
