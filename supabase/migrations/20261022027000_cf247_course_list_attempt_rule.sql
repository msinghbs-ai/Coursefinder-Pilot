-- CF-247 (22 Oct 2026). First live check of the course list reader (University of Waikato qualifications list, 103 course links from 10
-- list pages): the AI page match did not prepare Waikato's courses again. Each already had more attempts than the attempt cap, so "the cap
-- plus one after a list read" still held them. After each read of the provider's course list, a course without a page now gets one more
-- attempt whatever it had before (once: the attempt is newer than the read, so the next waits for the next weekly read).
-- Replaces: security.coverage_ai_match_prepare_v1 (one attempt after a list read, whatever the earlier count). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_once('security.coverage_ai_match_prepare_v1(integer,integer)', '5be3eba0b29f7cc6a620f63165586927', array[
  [$o$         and (select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) < v_cap + security.course_list_bonus_v1(co.id, co.provider_id)  -- 22 Oct 2026: one more after a course list read
       group by 1)$o$,
   $n$         and ((select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) < v_cap
              or security.course_list_bonus_v1(co.id, co.provider_id) = 1)  -- 22 Oct 2026: one more after each course list read, whatever the earlier count
       group by 1)$n$],
  [$o$         and (select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) < v_cap + security.course_list_bonus_v1(co.id, co.provider_id)
       order by$o$,
   $n$         and ((select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) < v_cap
              or security.course_list_bonus_v1(co.id, co.provider_id) = 1)
       order by$n$]]);
