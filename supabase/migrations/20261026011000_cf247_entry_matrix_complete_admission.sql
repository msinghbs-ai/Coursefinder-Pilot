-- CF-247 AER v1.1, completeness guard at admission (Platform Admin 26 Oct 2026 23:16: "A reviewer must not be able to approve a run that
-- fails it … Never propose a partial read as complete"). Record: admin docs/platform/aer-v1.1-build-log.md.
-- Why: a live rolled-back probe (26 Oct 23:5x) approved the complete China read (22 of 22) with the Gao Kao rows excluded by the reviewer,
-- and 13 rows went active: a complete read admitted in part. #709 checks the verdict; this checks that what is admitted is the whole
-- verdict.
-- 1 entry_matrix_review_apply_v1 (md5-guarded): for a provider under the completeness guard, approval admits a run only when the rows it
--   would make active (proposed, not excluded) are exactly the rows the complete verdict matched; excluding rows, or rows missing since
--   the verdict, refuses the approval (the reviewer rejects the whole run instead). Providers outside the guard (UTS) are unchanged.
-- Replaces: nothing (one function edited in place, md5-guarded)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched. No new status values.

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

select pg_temp.edit_n('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', '9386a7be7726b5f23a3d01436dfeca35', array[
  array[$o$        coalesce(r.result->'completeness'->>'status', 'no verdict') using errcode = '23514';
    end if;$o$,
        $n$        coalesce(r.result->'completeness'->>'status', 'no verdict') using errcode = '23514';
    end if;
    -- complete admission (26 Oct 2026): under the guard, what is admitted is the whole complete read, never a part of it
    if security.entry_completeness_required_v1(r.provider_id)
       and (select count(*) from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed' and not (m.id = any(v_ex)))
           is distinct from nullif(r.result->'completeness'->>'matched', '')::int then
      raise exception 'entry matrix run %: % of the % rows the complete read matched would be admitted; a read is admitted whole or rejected', r.id,
        (select count(*) from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed' and not (m.id = any(v_ex))),
        coalesce(r.result->'completeness'->>'matched', '?') using errcode = '23514';
    end if;$n$]], array[1]);
