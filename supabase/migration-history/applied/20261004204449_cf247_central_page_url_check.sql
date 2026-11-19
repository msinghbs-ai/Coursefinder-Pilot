-- CF-247 Decision 254 (5 Oct 2026). Fix to 20261005001430: the page address check used a repeat count above 255, which
-- the database refuses at run time. The address is now checked by pattern and length separately.
-- md5-guarded snippet patch, found exactly once. No text value in this file contains a semicolon.

do $p$
declare v_def text; v_old text; v_new text;
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_provider_central_page(text,jsonb)'::regprocedure) is distinct from '0b93556aa7b323a3b594dddb1a5dda2f' then
    raise exception 'admin_provider_central_page changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_provider_central_page(text,jsonb)'::regprocedure);
  v_old := $s$if v_url !~ '^https?://[^ ]{4,500}$' then$s$;
  v_new := $s$if v_url !~ '^https?://[^ ]+$' or length(v_url) not between 12 and 500 then$s$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'address check snippet not found exactly once'; end if;
  execute replace(v_def, v_old, v_new);
end $p$;
