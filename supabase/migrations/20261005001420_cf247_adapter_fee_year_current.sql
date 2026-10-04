-- CF-247 Decision 254 (5 Oct 2026, Platform Admin 07:36): "if no year is mentioned use current year".
-- An adapter fee reading with no year on the page was given the year of the fee already held (or the current year when
-- none was held). It now always takes the current year (Melbourne time). A held fee for another year is not changed.
-- md5-guarded snippet patch, found exactly once. No text value in this file contains a semicolon.

do $p$
declare v_def text; v_old text; v_new text;
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.adapter_overwrite_v1(integer)'::regprocedure) is distinct from '401a5d1960463594de1b711d39d3446c' then
    raise exception 'adapter_overwrite_v1 changed, not patching'; end if;
  v_def := pg_get_functiondef('security.adapter_overwrite_v1(integer)'::regprocedure);
  v_old := $s$v_fy := coalesce(nullif(r.c->'fee'->>'fee_year', '')::int, (select max(f.fee_year) from catalogue.course_fees f where f.course_id = r.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international'), extract(year from now())::int)$s$;
  v_new := $s$v_fy := coalesce(nullif(r.c->'fee'->>'fee_year', '')::int, extract(year from now() at time zone 'Australia/Melbourne')::int)$s$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'fee year snippet not found exactly once'; end if;
  execute replace(v_def, v_old, v_new);
end $p$;
