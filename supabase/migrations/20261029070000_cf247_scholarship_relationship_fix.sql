-- CF-247 scholarship relationship fix (Platform Admin mandate 29 Oct 2026 12:23, section A2: "Diagnose and fix DP020's empty
-- scholarship relationship ... Fix any demonstrated identity, query or relationship defect through existing scholarship mechanisms").
-- Trace (live, 29 Oct 2026) for RMIT University Diploma of Commerce (DP020, course b365fde8-d003-4ef6-80c3-4136fbd5587a, CRICOS 111278B,
-- provider 8e1adb6c-e069-43db-9584-bd054255e702): identity is sound (stable key course:cricos:00122a:111278b, same provider as every
-- linked scholarship); scholarship.course_mappings holds 9 mapped rows for the course, 6 of them published and active; 2 review
-- candidates, both superseded; no "Check scholarships for this course" task has run for it (1 such task on the platform, done, 11 Oct).
-- Two defects were demonstrated:
-- 1. Query defect: public.admin_read's course_detail branch no longer returns course_scholarships. It was wired in on 30 Aug 2026
--    (m2_4_4 course fill) and lost when admin_read was rebuilt on 14 Oct 2026 (20261014013200); the Course detail blade reads
--    data.course_scholarships, so every course showed "No published scholarship is linked to this course yet". The existing
--    security.admin_course_scholarships(uuid) is attached again, unchanged.
-- 2. Relationship defect: scholarship pages read with the level "postgraduate_research" map to no study level in
--    security.scholarship_level_codes (it knows only "research"), so security.scholarship_sweep_apply_v1 linked those scholarships by
--    field alone, to every level: 13,584 mapped rows across 214 scholarships, among them two RMIT PhD scholarships linked to DP020.
--    "postgraduate_research" now means the research levels, and a page whose stated levels are all unrecognised links no course by field
--    alone (it is recorded as levels_not_recognised). Existing links are corrected by the existing mechanism when a page is applied again
--    (the sweep, or "Check scholarships for this course"); this migration re-applies nothing and deletes nothing.
-- Replaces: public.admin_read, security.scholarship_level_codes, security.scholarship_sweep_apply_v1 (same names, md5-guarded edits)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No new table, job, setting or status. The consumer API is not touched (Decision 266): admin_read
-- is the admin read, and the website and Zoho functions are unchanged.

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

-- ---------------------------------------------------------------- 1. the Course detail read carries the course's scholarships again
select pg_temp.edit_n('public.admin_read(text,jsonb)', 'f7f3ebded941a60b391fa8b7c8e91805', array[
  array[$o$||jsonb_build_object('display_code',security.course_display_code_v1(v_id));end if;$o$,
        $n$||jsonb_build_object('display_code',security.course_display_code_v1(v_id))||jsonb_build_object('course_scholarships',security.admin_course_scholarships(v_id));end if;$n$]
], array[1]);

-- ---------------------------------------------------------------- 2. "postgraduate_research" is a research level
select pg_temp.edit_n('security.scholarship_level_codes(jsonb)', '902fac0f6dd4912db8d1b4465ed7275b', array[
  array[$o$    when 'research' then array['masters_research','doctorate']$o$,
        $n$    when 'research' then array['masters_research','doctorate']
    when 'postgraduate_research' then array['masters_research','doctorate']$n$]
], array[1]);

-- ---------------------------------------------------------------- 3. stated levels that map to none never become a field-only link
select pg_temp.edit_n('security.scholarship_sweep_apply_v1(uuid)', '7189ffebb3e5449b1af4a364731a7687', array[
  array[$o$    if cardinality(v_codes)>0 or cardinality(v_fields)>0 then$o$,
        $n$    if jsonb_typeof(f->'levels')='array' and jsonb_array_length(f->'levels')>0 and cardinality(v_codes)=0 then
      -- 29 Oct 2026 (mandate A2): the page states levels this reader does not know; a field alone would link every level
      v_changes:=v_changes||'levels_not_recognised'::text;
    elsif cardinality(v_codes)>0 or cardinality(v_fields)>0 then$n$]
], array[1]);

-- ---------------------------------------------------------------- post-checks
do $$
declare v_a text := pg_get_functiondef('public.admin_read(text,jsonb)'::regprocedure);
        v_s text := pg_get_functiondef('security.scholarship_sweep_apply_v1(uuid)'::regprocedure);
begin
  if position('''course_scholarships'',security.admin_course_scholarships(v_id)' in v_a) = 0 then raise exception 'post-check: course_detail does not carry course_scholarships'; end if;
  if security.scholarship_level_codes('["postgraduate_research"]'::jsonb) <> array['doctorate','masters_research'] then raise exception 'post-check: postgraduate_research is not a research level'; end if;
  if security.scholarship_level_codes('["pathway"]'::jsonb) <> array['advanced_diploma','certificate_iv','diploma','non_aqf_award'] then raise exception 'post-check: pathway levels changed'; end if;
  if position('levels_not_recognised' in v_s) = 0 then raise exception 'post-check: sweep still links by field when no stated level is recognised'; end if;
end $$;
