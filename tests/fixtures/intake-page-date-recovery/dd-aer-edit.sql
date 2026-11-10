-- Guards: F-INT Data Delivery (Platform Admin directive 10 Nov 2026 14:02), migration 20261110171000 on top of the AER change (#989, 20261110160000): the AER stream's one anchored line, applied exactly as that migration applies it
--   (inserted after the existing provider_ai line, once, skipped when present), so the fixture can build the Data Delivery body as it is after #989 (body md5 04b560cfb6b79758e2b694c96771be33) and apply the two edits in either order.
do $m$
declare v_src text; v_def text; v_c int; v_sig regprocedure := to_regprocedure('security.data_delivery_v1()');
        v_old text := $o$      'provider_ai', case when s.stream = 'pdesc' then security.data_delivery_pdesc_v1() end,$o$;
        v_new text := $n$      'provider_ai', case when s.stream = 'pdesc' then security.data_delivery_pdesc_v1() end,
      'aer_sources', case when s.stream = 'aer' then security.data_delivery_aer_v1() end,$n$;
begin
  v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
  if position('data_delivery_aer_v1' in v_src) > 0 then return; end if;
  v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception 'anchor found % times', v_c; end if;
  execute replace(v_def, v_old, v_new);
end $m$;
