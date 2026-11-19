-- CF-247 Decision 254 (4 Oct 2026). Two fixes found on the first fee admissions from the Flinders adapter.
--   * A fee was written again on every run when the course also held a fee for another year: the check compared the
--     page's fee with the latest year held, not with the same year. It now compares with the fee held for the same year.
--   * Some Flinders study pages cover several courses (Graduate Certificate, Graduate Diploma and Master on one page),
--     each with its own CRICOS code and block. A pattern anchored on any CRICOS code read the first course's block for
--     every course. Patterns may now hold {code}, which the worker (v0.17.1) replaces with the course's own code, so each
--     course is read from its own block. The Flinders patterns are changed to use it through the adapter save (logged).
-- md5-guarded, the snippet must be found exactly once. No text value in this file contains a semicolon.

do $p$
declare v_def text := pg_get_functiondef('security.adapter_overwrite_v1(int)'::regprocedure);
        v_old text := $s$and r.cur_fee is distinct from v_fee$s$;
        v_new text := $s$and (select f.amount from catalogue.course_fees f where f.course_id = r.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and coalesce(f.fee_year, 0) = coalesce(v_fy, 0) order by f.updated_at desc nulls last limit 1) is distinct from v_fee$s$;
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.adapter_overwrite_v1(int)'::regprocedure) is distinct from '081db7a6cae9e5df0c237a8f0c978d3d' then
    raise exception 'adapter_overwrite_v1 changed, not replacing'; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'fee snippet not found exactly once'; end if;
  execute replace(v_def, v_old, v_new);
end $p$;
