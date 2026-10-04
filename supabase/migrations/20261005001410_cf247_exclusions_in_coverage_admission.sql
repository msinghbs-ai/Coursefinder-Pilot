-- CF-247 Decision 254 (5 Oct 2026). Course exclusions also hold for the coverage admission of intakes and English.
-- Wave 5 (Australian Catholic, Royal Roads) found wrong values the general reader took on pages an adapter confirms
-- (application-open months read as intakes, a scholarship read as the fee). With adapter admission on, the coverage
-- admission (cron coverage-admit-intakes) would still take those intakes. An excluded course and field is now skipped there too.
-- md5-guarded snippet patch, each snippet found exactly once. No text value in this file contains a semicolon.

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.coverage_admission_apply_v1(integer,text,text[])'::regprocedure) is distinct from '33c6c4c477e472c86ca8a74eabab48a1' then
    raise exception 'coverage_admission_apply_v1 changed, not patching'; end if;
  v_def := pg_get_functiondef('security.coverage_admission_apply_v1(integer,text,text[])'::regprocedure);
  v_pairs := array[
    array[$s$if r.props ? 'english' then$s$, $s$if r.props ? 'english' and not security.uni_adapter_excluded(r.course_id, 'english') then$s$],
    array[$s$if r.props ? 'intakes' then$s$, $s$if r.props ? 'intakes' and not security.uni_adapter_excluded(r.course_id, 'intakes') then$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;
