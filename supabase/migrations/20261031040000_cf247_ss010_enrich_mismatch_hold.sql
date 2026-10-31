-- CF-247 StudySearch SS-010 decision D5a (Platform Admin 31 Oct 2026 13:30, "Prevent mismatch-page courses from repeatedly re-entering
-- enrichment queues"; admin docs/platform/nz-enrichment-brief/2026-10-31-studysearch-transformation.md §20 and §25).
-- Why: the standing gap queue re-queued courses whose page binding is a mismatch every time the wrong page was read again. In the four days
-- to 31 Oct 2026, 11,332 Enrich items on such courses ended "no correct course page" (or found nothing) and none was filled: 1,600 to 2,200
-- futile items a day that hide the real constraint (a missing course page) behind Enrich numbers.
-- What: the existing central enrichment hold, security.enrich_item_held_v1 (used by the item gate trigger, the standing gap queue and
-- enrichment plans), also holds a course while its page binding is `mismatch` (manual bindings excepted). When a page is bound again the hold
-- ends by itself and the gap queue's existing read_at rule queues the course. Admission rules, provenance, settings and schedules are unchanged.
-- Dry run (live, rolled back): of 19,512 distinct course-fields tried in the last 4 days, held 9,264 before and 16,797 after; 4.8 s for all.
-- Replaces: security.enrich_item_held_v1 (same name; md5-guarded edit)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No new table, job, setting or status. Consumer API untouched.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_once('security.enrich_item_held_v1(uuid,text)', '66be0efc9fd32e4d7920499f90baca07', '688da7aedbb7ee3f09f629b497c25579', array[
 array[$o$  select exists (select 1 from pipeline.enrichment_flags f
$o$, $n$  -- 31 Oct 2026 (StudySearch D5a): a course whose page binding is a mismatch is held until a page is bound again (0 of 11,332 such items filled in 4 days)
  select exists (select 1 from pipeline.coverage_course_pages g where g.course_id = p_course and g.status = 'mismatch' and coalesce(g.basis, '') <> 'manual')
      or exists (select 1 from pipeline.enrichment_flags f
$n$]], array[1]);
