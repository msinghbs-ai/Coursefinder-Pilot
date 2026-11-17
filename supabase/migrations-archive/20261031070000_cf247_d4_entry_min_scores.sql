-- Consumer API change approved: Platform Admin, 31 Oct 2026 13:30 (StudySearch decision D4: "Proceed with the additive entry.min_scores[] enhancement. Preserve the existing min_score field and its behaviour … Do not infer unstated scores or grading scales … No removal, renaming or retyping of existing fields is authorised"; admin 2026-10-31-studysearch-d1-d6-approval.md, record §16.1 and §28) — additive key inside entry only
-- CF-247 StudySearch D4 / SS-009: the course detail's entry object gains `min_scores`, every admitted entry score as printed.
-- Why (record §16): 24 courses (Monash) publish several genuine alternative entry routes (ATAR, IB, GCE A Level, foundation and diploma
-- pathways); `min_score` shows one of them, chosen by audience and last update, and 2 courses with scores return min_score null.
-- What (security.entry_course_payload_v1, one md5-guarded single-line edit): `entry.min_scores` is an array of
-- {score, basis, audience, scale, quote, source_url, as_at} from the course's active requirement rows that hold a score (any kind), each as
-- admitted: the number and the provider's own words; `scale` only when a scale was recorded (null otherwise, never inferred); identical rows
-- (same audience, basis, score and quote) shown once; order: international, all, domestic, then basis, score, quote. Always present; [] when
-- none. `min_score` and `min_score_basis` are unchanged, rule and values.
-- Proof (live, rolled back, 31 Oct 2026): 41 courses with scores: every other part of the Website course response identical; 116 items
-- (24 courses with more than one); 5 other courses: identical with min_scores []. Sample 0101331 matches the approved proposal (§16.1).
-- Replaces: security.entry_course_payload_v1 (same name; md5-guarded edit)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No new table, job, setting or status. The consumer API baseline is re-taken.

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

select pg_temp.edit_once('security.entry_course_payload_v1(uuid,text)', '80fdfabb84a90fab25df36970dea696a', '691bbba7958ebcd35ac332879c27d341', array[
 array[$o$'min_score_basis', (select s.min_entry_score_basis from s),$o$, $n$'min_score_basis', (select s.min_entry_score_basis from s),
    -- StudySearch D4 (31 Oct 2026): every admitted entry score as printed, additive; min_score and min_score_basis are unchanged
    'min_scores', coalesce((select jsonb_agg(jsonb_build_object('score', m.min_entry_score, 'basis', m.min_entry_score_basis, 'audience', m.audience,
                      'scale', m.grade_scale, 'quote', m.quote, 'source_url', m.source_url, 'as_at', m.as_at)
                    order by case m.audience when 'international' then 0 when 'all' then 1 else 2 end, m.min_entry_score_basis, m.min_entry_score, m.quote)
                  from (select distinct on (r.audience, r.min_entry_score_basis, r.min_entry_score, r.quote) r.* from r where r.min_entry_score is not null
                         order by r.audience, r.min_entry_score_basis, r.min_entry_score, r.quote, r.updated_at desc) m), '[]'::jsonb),$n$]],
 array[1]);

select security.consumer_api_rebaseline_v1('D4 (31 Oct 2026): additive entry.min_scores[] (security.entry_course_payload_v1); approved Platform Admin 31 Oct 2026 13:30, record §28');
