-- Fixture only: the two Course catalogue registry rows of migration 20261118073000, for the browser-to-PostgreSQL integration test's database (the
-- course-catalogue-columns fixture, built from the registry of 5 Nov 2026). The screen offers 42 columns; a layout naming one the database does not
-- register is refused, as it should be. Spec s597 checks these rows equal the migration's.
insert into pipeline.admin_table_columns(screen, key, grp, label, sort, sort_key, default_visible, default_width, min_width, always_visible) values
 ('courses', 'study_load', 'Course information', 'Study load', 115, null, false, 130, 90, false),
 ('courses', 'empty_reason_code', 'Course information', 'Empty reason', 215, null, false, 210, 120, false)
on conflict (screen, key) do nothing;
