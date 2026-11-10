-- HELD (not a migration): forward recovery for 20261110171000 (intake delivery counts in Data Delivery), its one in-place edit: security.data_delivery_v1 (the 'intake_delivery' line).
-- Run only if the Platform Admin decides to take the edit back. It removes ONLY that line from whatever body is live (the keys other streams added, such as aer_sources, stay) and does nothing when the line is not there; it stops, and
-- changes nothing, when the line is not found exactly once. Removing the line from the body 20261110171000 made returns the body it was read as (849453412a8b9a448118e7b87362752a).
-- security.data_delivery_intake_v1 is left in place (nothing calls it once the line is gone); it is dropped by a paste file only on the Platform Admin's say.

do $r$
declare v_sig regprocedure := to_regprocedure('security.data_delivery_v1()'); v_src text; v_def text; v_c int;
        v_line text := $l$
      'intake_delivery', case when s.stream = 'int' then security.data_delivery_intake_v1() end,$l$;
begin
  if v_sig is null then raise exception 'security.data_delivery_v1() is missing'; end if;
  v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
  if position('data_delivery_intake_v1' in v_src) = 0 then raise notice 'security.data_delivery_v1(): no intake key, nothing to remove'; return; end if;
  v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, v_line, ''))) / length(v_line);
  if v_c <> 1 then raise exception 'security.data_delivery_v1(): the intake_delivery line is not found exactly once (found %): nothing changed', v_c; end if;
  execute replace(v_def, v_line, '');
  if position('data_delivery_intake_v1' in (select p.prosrc from pg_proc p where p.oid = v_sig)) > 0 then raise exception 'post-check: the intake key is still in security.data_delivery_v1()'; end if;
end $r$;
