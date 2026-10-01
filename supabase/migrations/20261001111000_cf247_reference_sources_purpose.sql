-- CF-247 Reference sources: purpose is a required column on pipeline.important_links, so a site saved without a purpose
-- stores an empty purpose instead of failing (found in the rolled-back live test of 20261001110000). md5-guarded edit.
do $do$
declare v_def text; v_new text;
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_reference_source_save(uuid,jsonb,text)'::regprocedure) <> 'cec5599f34749ac4c8e0d10a8a2c836d' then
    raise exception 'public.admin_reference_source_save changed since it was checked; not editing'; end if;
  v_def := pg_get_functiondef('public.admin_reference_source_save(uuid,jsonb,text)'::regprocedure);
  v_new := replace(v_def, $s$nullif(btrim(coalesce(p_fields->>'purpose', '')), '')$s$, $s$btrim(coalesce(p_fields->>'purpose', ''))$s$);
  if v_new = v_def then raise exception 'expected text not found'; end if;
  execute v_new;
end $do$;