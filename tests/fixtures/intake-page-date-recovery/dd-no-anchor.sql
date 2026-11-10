-- Guards: F-INT Data Delivery (Platform Admin directive 10 Nov 2026 14:02), migration 20261110171000: a Data Delivery body whose provider_ai anchor line is gone, to prove the migration refuses and applies nothing.
do $m$
declare v_sig regprocedure := to_regprocedure('security.data_delivery_v1()'); v_def text := pg_get_functiondef(to_regprocedure('security.data_delivery_v1()'));
        v_old text := $o$      'provider_ai', case when s.stream = 'pdesc' then security.data_delivery_pdesc_v1() end,$o$;
begin
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'anchor not found once in the base'; end if;
  execute replace(v_def, v_old || chr(10), '');
end $m$;
