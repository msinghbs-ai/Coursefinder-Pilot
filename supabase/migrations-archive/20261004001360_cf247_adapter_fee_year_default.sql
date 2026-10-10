-- CF-247 Decision 254 (4 Oct 2026). When the page gives the fee without a year, the adapter fee was written with no
-- year, and the fee history kept only the dated fee active, so the same fee was written again on every run. A fee with
-- no year on the page now takes the year of the latest active international fee held, or the current year when none is
-- held. The comparison and the fee key then use that year.
-- md5-guarded, the snippet must be found exactly once. No text value in this file contains a semicolon.

do $p$
declare v_def text := pg_get_functiondef('security.adapter_overwrite_v1(int)'::regprocedure);
        v_old text := $s$v_fy := nullif(r.c->'fee'->>'fee_year', '')::int$s$;
        v_new text := $s$v_fy := coalesce(nullif(r.c->'fee'->>'fee_year', '')::int, (select max(f.fee_year) from catalogue.course_fees f where f.course_id = r.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international'), extract(year from now())::int)$s$;
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.adapter_overwrite_v1(int)'::regprocedure) is distinct from '52b52638ef96a485d2866dfc53ed7854' then
    raise exception 'adapter_overwrite_v1 changed, not replacing'; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'fee year snippet not found exactly once'; end if;
  execute replace(v_def, v_old, v_new);
end $p$;
