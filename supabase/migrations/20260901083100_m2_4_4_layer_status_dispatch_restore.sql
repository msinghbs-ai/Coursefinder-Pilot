-- CF-CHG-20260830-048
-- M2.4.4 A28: restore bounded Dashboard Layer-status dispatcher after A27 reconciliation.

do $$
declare v_oid oid; v_def text;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='admin_read'
    and pg_get_function_identity_arguments(p.oid)='p_operation text, p_args jsonb'
  limit 1;

  if v_oid is null then
    raise exception 'public.admin_read not found';
  end if;

  select pg_get_functiondef(v_oid) into v_def;

  if position('layer_status_summary' in v_def)=0 then
    v_def:=replace(
      v_def,
      'if p_operation=''dashboard'' then return security.admin_dashboard_maturity(); end if;',
      'if p_operation=''dashboard'' then return security.admin_dashboard_maturity(); end if;
 if p_operation=''layer_status_summary'' then return security.admin_layer_status_summary(); end if;'
    );
    execute v_def;
  end if;
end $$;
