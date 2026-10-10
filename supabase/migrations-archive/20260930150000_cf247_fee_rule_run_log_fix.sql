-- CF-247 fix (1 Oct 2026): approving a fee wording rule failed. The run log row (layer4_mass_operations) uses
-- target_kind 'course_tuition', which the table's check constraint did not allow, so the whole approval rolled back.
-- Platform Admin reported "I tried to run and approve one rule, but nothing happened".
alter table pipeline.layer4_mass_operations drop constraint layer4_mass_operations_target_kind_check;
alter table pipeline.layer4_mass_operations add constraint layer4_mass_operations_target_kind_check
  check (target_kind = any (array['scholarship_course_scope','review_queue','review_batch','course_tuition']));
