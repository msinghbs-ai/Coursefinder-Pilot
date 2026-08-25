-- CF-CHG-20260825-038
-- Source IDs are first-class bounded targets after M2.3 refresh source precision.
alter table pipeline.important_dates drop constraint if exists important_dates_check2;
alter table pipeline.important_dates
  add constraint important_dates_bounded_scope_check
  check (
    scope_type='country_reference'
    or source_id is not null
    or source_profile_id is not null
    or entity_id is not null
  );