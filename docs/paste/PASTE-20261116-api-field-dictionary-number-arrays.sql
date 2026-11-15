-- =====================================================================================================================================
-- PASTE FILE for the Platform Admin (SQL editor, project fxcwkweaxjtknorudmwp ONLY; never coursefinder-demo). A migration drops nothing
-- (CLAUDE.md housekeeping); widening a CHECK constraint means dropping and re-adding it, so it comes to you as this file.
-- Why: ref.api_field_dictionary.data_type (20261115190000) allows string, integer, number, boolean, date, timestamptz, object, array<string>
-- and array<object>. Two v3 fields are lists of numbers: reference ranking_systems[].editions (edition years) on the website and on Zoho.
-- They are held back in docs/api/v3/field-dictionary.json (pending_fields) until the type list also allows array<integer> and array<number>.
-- What it does: one transaction. Replaces the data_type check with the same list plus array<integer> and array<number>. No row changes; the
-- table holds only values the old list allowed, so the new constraint validates at once. Nothing else is touched.
-- After it: a small migration loads the two pending fields (and widens security.api_field_dictionary_sync_v1's own type list to match).
-- Replaces: the check constraint on ref.api_field_dictionary.data_type. Retires: nothing.
-- Rollback: re-run PART A with the two array<integer>/array<number> values removed (only if no row uses them).
-- =====================================================================================================================================

-- PART A
begin;
set local lock_timeout = '5s';
do $p$
declare v_name text;
begin
  select conname into v_name from pg_constraint
   where conrelid = 'ref.api_field_dictionary'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%data_type%array<object>%';
  if v_name is null then raise exception 'the data_type check was not found: stop and report'; end if;
  execute format('alter table ref.api_field_dictionary drop constraint %I', v_name);
end $p$;
alter table ref.api_field_dictionary add constraint api_field_dictionary_data_type_check
  check (data_type in ('string', 'integer', 'number', 'boolean', 'date', 'timestamptz', 'object', 'array<string>', 'array<object>', 'array<integer>', 'array<number>'));
select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid = 'ref.api_field_dictionary'::regclass and contype = 'c' and conname = 'api_field_dictionary_data_type_check';
commit;
