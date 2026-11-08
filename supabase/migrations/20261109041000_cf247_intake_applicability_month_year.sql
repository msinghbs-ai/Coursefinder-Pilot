-- CF-247 F-INT (valid course intake dates; data population mandate 9 Nov 2026): security.intake_course_applicability_v1 no longer raises 22P02 on "<Month> <Year>" wording.
-- Why (reproduced on the production definition, md5 d3789be9, and in tests/fixtures/intake-self-driving/cases-before.sql):
--   * the function builds one month pattern per month, v_w := '(' || month || '|' || abbreviation || ')\.?', and reads the printed year with
--     (regexp_match(f, '\m' || v_w || ',? (20\d\d)\M'))[1]::int. The month pattern is a CAPTURING group, so group [1] is the month text ("february"),
--     not the year, and the cast to integer raises 22P02 (invalid input syntax for type integer: "february").
--   * It is raised for any offering statement that prints a month followed by a year: 'Start dates: February 2027 intake' and
--     'Start dates 25 January 2027 ...'. The plan calls the function for every course that reaches the calendar gate, so one such page stops the whole
--     hourly intake-dates-apply batch (the batch runs in one transaction). Found by the F-INT evidence analyst, 9 Nov 2026.
-- What: the month pattern becomes a non-capturing group '(?:...)', so [1] is the year group. md5-guarded edit, one change, applied exactly once.
--   Nothing else in the function changes: for wording without a month followed by a year the result is identical (the fixture compares a battery of
--   inputs before and after), and a month of a past year ("February 2023") is still not an offering.
-- Consumer API: unchanged (G3). Only security.intake_course_applicability_v1 is edited.
-- Replaces: md5-guarded edit of security.intake_course_applicability_v1
-- Retires: nothing
-- Nothing is dropped or deleted.

create or replace function pg_temp.edit(p_sig text, p_md5 text, p_marker text, p_old text[], p_new text[], p_times int[]) returns text language plpgsql as $e$
declare v text := pg_get_functiondef(p_sig::regprocedure); i int; n int;
begin
  if position(p_marker in v) > 0 then return p_sig || ': already applied'; end if;
  if md5(v) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %, expected %)', p_sig, md5(v), p_md5; end if;
  for i in 1 .. array_length(p_old, 1) loop
    n := (length(v) - length(replace(v, p_old[i], ''))) / length(p_old[i]);
    if n <> p_times[i] then raise exception '%: edit % must apply exactly % time(s), found %', p_sig, i, p_times[i], n; end if;
    v := replace(v, p_old[i], p_new[i]);
  end loop;
  execute v;
  return p_sig || ': edited';
end $e$;

select pg_temp.edit('security.intake_course_applicability_v1(text,integer,integer,jsonb,boolean,text[],text)', 'd3789be9c8dee10f31868700b11abf89', 'v_w := ''(?:''',
  array[$o$v_w := '(' || v_names[k]$o$],
  array[$n$v_w := '(?:' || v_names[k]$n$],
  array[1]);
comment on function security.intake_course_applicability_v1(text, integer, integer, jsonb, boolean, text[], text) is 'CF-247 (direction 5 Nov 2026 sections 1 and 2; F-INT 9 Nov 2026): the course page must state the intake as its own offering (intake, start, entry or study-period wording; never a personal account or a month of a past year), and a month-only match needs a calendar that applies to the course. The month pattern is a non-capturing group, so a printed year after a month ("February 2027") is read as the year.';
