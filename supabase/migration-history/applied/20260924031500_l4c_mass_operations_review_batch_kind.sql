-- L4-C: allow the new batch kind in the mass-operation audit log.
-- Found by a rolled-back proof run: layer4_batch_decide_v1 failed at its audit insert
-- because target_kind only allowed 'scholarship_course_scope' and 'review_queue'.
-- Existing values are unchanged; 'review_batch' is added.
alter table pipeline.layer4_mass_operations drop constraint if exists layer4_mass_operations_target_kind_check;
alter table pipeline.layer4_mass_operations add constraint layer4_mass_operations_target_kind_check
  check (target_kind = any (array['scholarship_course_scope'::text,'review_queue'::text,'review_batch'::text]));
