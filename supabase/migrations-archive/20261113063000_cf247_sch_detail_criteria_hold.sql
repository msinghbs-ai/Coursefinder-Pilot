-- CF-247 F-SCH redesign R1 first-cohort check (live 12 Nov 2026 17:05 AEDT, 12 version 3 extractions, US$0.0079): descriptions, payment basis,
-- application method, duration and nationality filled as designed (no wrong value seen). The eligibility conditions written as published passages
-- (criterion type published_eligibility_narrative, read by the consumer API as eligibility_summary) are not safe yet: a passage that lists who is
-- NOT eligible ("International exchange students", "International students commencing an online mode course") reads as a condition without its
-- heading, and a site-wide line ("Most scholarships require a minimum GPA of 4.0") is not this scholarship's condition. Until exclusions and their
-- headings are represented, the detail fill writes no eligibility conditions, and the ones it wrote are superseded (kept, not deleted).
-- Replaces: the eligibility-condition part of security.scholarship_detail_apply_v1 (held). Retires: nothing.

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('security.scholarship_detail_apply_v1(bigint)', '476dbc9eefac8a3567adc690d6576b04', array[
  array[$o$  if jsonb_array_length(coalesce(c->'criteria', '[]')) > 0
     and not exists$o$,
        $n$  -- held (20261113063000): a passage listing who is not eligible, or a site-wide line, must not read as this scholarship's condition
  if false and jsonb_array_length(coalesce(c->'criteria', '[]')) > 0
     and not exists$n$]
], array[1]);

update scholarship.criteria set status = 'superseded'
 where status = 'active' and criterion_type = 'published_eligibility_narrative' and value_json->>'by' = 'sch-extract-v3';

update scholarship.criterion_groups set label = 'Published eligibility (held 20261113063000)'
 where group_code like 'sch-extract-v3:%' and label = 'Published eligibility';

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('scholarships', 'sch_detail_criteria_held', 'Scholarship detail fill: eligibility conditions held; the passages written are superseded',
        jsonb_build_object('why', 'exclusion lists and site-wide lines read as conditions', 'migration', '20261113063000'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
