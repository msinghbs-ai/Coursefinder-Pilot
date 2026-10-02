-- CF-247 (Decision 227, 2 Oct 2026). Platform Admin, 19:21, in chat, on the recommended English policies (group 1):
-- "I have reviewed it, if there is differ because its already exists on record ... we should leave as is and apply
-- only to empty or not manually edited records."
-- The eleven policies below are approved as the Platform Admin's decision. That is exactly the approved plan's rule: only
-- courses with no English requirement at all, none set by hand, no review open and no page still to read are written;
-- a course whose value differs is left as it is. The job provider-english-defaults fills them within 10 minutes.
-- The agreement check (more differ than agree, at least 10 compared) passes for every one of them.
update pipeline.provider_policy_proposals
   set status = 'approved', decided_by = '63ba56cb-48d4-4169-98c2-7c4d1f72925b', decided_at = now(), updated_at = now(),
       decision_note = 'Approved by the Platform Admin in chat, 2 Oct 2026 19:21 (recommended group 1): apply only to courses with no English requirement and none set by hand; differences left as they are.'
 where kind = 'english_policy' and status = 'proposed'
   and id in ('b7cb7c7f-3f78-45f1-99f2-6102d48e9afc', '02477254-7804-4f56-a475-841728f0aa95', 'af42548f-0103-490d-9729-cfcedd0c2de9',
              '78c1cbb9-3d0a-4465-8d1d-e158bdc18d7e', '06a9de4b-ec54-414a-afb0-d27c6799775f', '92d127ff-3192-4028-ba6a-14bb574be6ab',
              '1d99be88-95e4-40d5-94da-79af8f7c54a9', '09f9c3c0-f492-4e6b-a2bb-3ee148a44a6a', '2ed2923f-c8b2-4f1e-a2c2-1ac2d13a91a4',
              '7c5820c6-659b-4e3f-b650-1598d5ffb93b', '2d0019eb-a69a-486c-b1d3-29f6fe9269d3');

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('policies', 'approve', 'English policies, recommended group 1 (11 universities)',
        jsonb_build_object('decision', 'Decision 227', 'approved_in', 'chat 2 Oct 2026 19:21'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
