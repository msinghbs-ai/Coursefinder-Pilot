-- CF-247 F-SCH redesign (12 Nov 2026 20:05 AEDT audit): since worker v0.78.0, 110 of 1,085 version 3 scholarship reads stopped at the answer
-- length limit (reading.answer_tokens.scholarship_page 3000; held_partial output_truncated) and 22 gave no answer. The version 3 answer carries every
-- field with its passage; a page with many conditions or benefits needs more room. The limit goes to 4500 (inside its range 1000 to 16000); cost
-- grows only for the answers that use the room, and spend stays inside the scholarship AI daily guard.
-- Replaces: nothing. Retires: nothing.

update pipeline.platform_toolset_settings set value = to_jsonb(4500), updated_at = now(), updated_by = '63ba56cb-48d4-4169-98c2-7c4d1f72925b',
       reason = 'F-SCH redesign 12 Nov 2026: 110 of 1,085 version 3 reads cut at 3000 tokens'
 where toolset_key = 'pipeline' and key = 'reading.answer_tokens.scholarship_page' and value = to_jsonb(3000);

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('scholarships', 'setting_changed', 'reading.answer_tokens.scholarship_page 3000 -> 4500',
        jsonb_build_object('key', 'reading.answer_tokens.scholarship_page', 'from', 3000, 'to', 4500, 'truncated', 110, 'reads', 1085, 'migration', '20261113067000'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
