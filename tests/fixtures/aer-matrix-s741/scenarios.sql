-- S741 scenarios after the migration (applied twice). Every line prints PASS or FAIL; run.sh fails on FAIL or ERROR.
create or replace function t.chk(p text, ok boolean) returns void language plpgsql as $f$ begin raise notice '%', case when coalesce(ok, false) then 'PASS ' else 'FAIL ' end || p; end $f$;
create or replace function t.x(p text) returns jsonb language sql stable as $f$ select security.aer_matrix_machine_exclusions_v1((select run_id from t.cases where name = p)) $f$;
create or replace function t.b(p text) returns jsonb language sql stable as $f$ select x from t.before_s741 where name = p $f$;
create or replace function t.held(p text) returns text language sql stable as $f$ select string_agg(k, ',' order by k) from jsonb_object_keys(t.x(p)->'by_rule') k $f$;
create or replace function t.linked(p text) returns text language sql stable as $f$
  select string_agg(c.canonical_title, ',') from jsonb_array_elements(t.x(p)->'course_links') l join catalogue.courses c on c.id = (l->>'course_id')::uuid $f$;
select t.chk('B0 before S741: every award or title case is held course_unlinked, the training package and age cases no_minimum (checked before the link), plain completion passes',
  not exists (select 1 from t.before_s741 where name ~ '^LK' and not (x->'by_rule') ? 'course_unlinked')
  and not exists (select 1 from t.before_s741 where name ~ '^(TP|CP[1-5])' and not (x->'by_rule') ? 'no_minimum')
  and (select x->'by_rule' from t.before_s741 where name = 'CP6_plain_completion') = '{}'::jsonb);
select t.chk('LK1 "Diploma Program" + "Business" links the one "Diploma of Business"', t.linked('LK1_award_field') = 'Diploma of Business' and t.held('LK1_award_field') is null);
select t.chk('LK2 "&" in the label matches "&" in the title (the linker''s own title key)', t.linked('LK2_ampersand') = 'Diploma of Arts & Creative Industries');
select t.chk('LK3 an exact title with an active twin "(Accelerated)" is refused', t.linked('LK3_twin_exact') is null and t.held('LK3_twin_exact') = 'course_unlinked');
select t.chk('LK4 only twins "(52 weeks)" and "(34 weeks)": no link', t.linked('LK4_twins_only') is null and t.held('LK4_twins_only') = 'course_unlinked');
select t.chk('LK5 a stream label "[Nursing]" is never linked by award', t.linked('LK5_stream') is null and t.held('LK5_stream') = 'course_unlinked');
select t.chk('LK6 a person''s "no catalogue course" decision stands', t.linked('LK6_person_rejected') is null and t.held('LK6_person_rejected') = 'course_unlinked');
select t.chk('LK7 "Advanced Diploma" links the Advanced Diploma, not the Diploma', t.linked('LK7_advanced') = 'Advanced Diploma of Leadership');
select t.chk('LK8 Pass and Honours stay apart: "Bachelor of Design" with an active "(Honours)" is refused', t.linked('LK8_honours_twin') is null);
select t.chk('LK9 an inactive course is never linked', t.linked('LK9_inactive') is null);
select t.chk('LK10 a level that names no award of the list ("Undergraduate") links nothing', t.linked('LK10_level_names_no_award') is null);
select t.chk('TP1 a training package code before the exact title links the one course, and the row is completion-only (age, CRICOS code, duration, English clause)',
  t.linked('TP1_code_title') = 'Certificate III in Painting and Decorating' and t.held('TP1_code_title') is null and jsonb_array_length(t.x('TP1_code_title')->'completion_only_ids') = 1);
select t.chk('TP2 two active records of one title: no link (the row, now completion-only, waits on the course)', t.linked('TP2_two_records') is null and t.held('TP2_two_records') = 'course_unlinked');
select t.chk('CP1 "18-years of Age" and the English clause are not scores: completion-only', t.held('CP1_age_english') is null and jsonb_array_length(t.x('CP1_age_english')->'completion_only_ids') = 1);
select t.chk('CP2 a percentage after the English clause keeps the row held (no_minimum)', t.held('CP2_score_after_english') = 'no_minimum');
select t.chk('CP3 an "average" after the English clause keeps the row held', t.held('CP3_average_after_english') = 'no_minimum');
select t.chk('CP4 a score before the English clause keeps the row held', t.held('CP4_score_before') = 'no_minimum');
select t.chk('CP5 no completion words: held as before', t.held('CP5_no_completion_words') = 'no_minimum');
select t.chk('CP6 plain completion was and is completion-only', t.b('CP6_plain_completion')->'by_rule' = '{}'::jsonb and t.held('CP6_plain_completion') is null);
update pipeline.platform_toolset_settings set value = '0' where key in ('aer.matrix_completion_clauses_on', 'aer.matrix_course_link_rules_on');
select t.chk('OFF both switches at 0 restore the 18 Nov result for every case exactly',
  not exists (select 1 from t.before_s741 b where b.x is distinct from (t.x(b.name) - 'course_links')) and not exists (select 1 from t.cases c where jsonb_array_length(t.x(c.name)->'course_links') > 0));
update pipeline.platform_toolset_settings set value = '1' where key in ('aer.matrix_completion_clauses_on', 'aer.matrix_course_link_rules_on');
do $$ begin raise notice 's741: scenarios finished'; end $$;
