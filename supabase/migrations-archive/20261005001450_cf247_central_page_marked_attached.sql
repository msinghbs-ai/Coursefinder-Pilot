-- CF-247 Decision 254 (5 Oct 2026). A central page the Platform Admin attaches that the search had already found is now
-- marked as attached (found_via manual), so the Universities tab lists it with the pages attached by hand.
-- md5-guarded snippet patch, found exactly once. No text value in this file contains a semicolon.

do $p$
declare v_def text; v_old text; v_new text;
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_provider_central_page(text,jsonb)'::regprocedure) is distinct from '3935573e2c87ea8f7216f9d67dd0bd08' then
    raise exception 'admin_provider_central_page changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_provider_central_page(text,jsonb)'::regprocedure);
  v_old := $s$do update set status = 'found', attempts = 0, rank = 9, updated_at = now()$s$;
  v_new := $s$do update set status = 'found', attempts = 0, rank = 9, found_via = 'manual', updated_at = now()$s$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'conflict snippet not found exactly once'; end if;
  execute replace(v_def, v_old, v_new);
end $p$;
