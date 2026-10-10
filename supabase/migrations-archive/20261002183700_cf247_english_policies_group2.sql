-- CF-247 (Decision 227, 2 Oct 2026). Platform Admin, 19:21 and by multiple choice: approve Victoria University and USQ
-- from the checked group ("Apply all ... courses meant for international students are priorities").
--  * Approved now: Victoria University's requirements PDF (6.0 with no band below 6.0 for bachelor degrees, 6.5 with no
--    band below 6.0 for postgraduate; it names 19 courses that need more, which are held back or given their own score)
--    and USQ (6.5 with no band below 6.0 for the majority of degrees; Bachelor of Nursing is named and held back).
--  * Rejected: Victoria University's two web-page versions, which do not name the courses that need more.
--  * Sydney, UNE and Canberra are approved only with the flag step (migration 20261002183710), because their policies
--    do not list the courses that need more; until that step is applied they stay waiting.
--  * As before, only courses with no English requirement and none set by hand are written; differences are left as they are.
update pipeline.provider_policy_proposals
   set status = 'approved', decided_by = '63ba56cb-48d4-4169-98c2-7c4d1f72925b', decided_at = now(), updated_at = now(),
       decision_note = 'Approved by the Platform Admin, 2 Oct 2026 19:21 (group 2): apply to courses with no English requirement and none set by hand.'
 where kind = 'english_policy' and status = 'proposed'
   and id in ('f885a08b-0386-40b8-8400-229e92c3b60b', '0771fa37-ac6a-4b45-8b35-547cd8e398ec');

update pipeline.provider_policy_proposals
   set status = 'rejected', decided_by = '63ba56cb-48d4-4169-98c2-7c4d1f72925b', decided_at = now(), updated_at = now(),
       decision_note = 'Rejected 2 Oct 2026 (group 2): Victoria University''s web page does not name the courses that need more; its requirements PDF is approved instead.'
 where kind = 'english_policy' and status = 'proposed'
   and id in ('d587d93b-a633-4c20-b6b2-f1caefb920cf', '6be01474-5661-4ea6-8a4e-ff929c1f1f09');

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('policies', 'approve', 'English policies, group 2: Victoria University (requirements PDF) and USQ',
        jsonb_build_object('decision', 'Decision 227', 'approved_in', 'chat 2 Oct 2026 19:21'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
