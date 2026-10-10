-- M2.4.4 — expose Layer 3 operational alerts through the existing governed Admin read boundary.
-- The underlying security function still enforces authenticated pipeline-operator rank >=4.

do $$
declare v_def text; v_oid oid;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='admin_read'
    and pg_get_function_identity_arguments(p.oid)='p_operation text, p_args jsonb'
  limit 1;
  if v_oid is null then raise exception 'public.admin_read(text,jsonb) not found'; end if;
  select pg_get_functiondef(v_oid) into v_def;
  if position('layer3_ops_alerts' in v_def)=0 then
    if position('if p_operation=''layer2_ops_alerts'' then return security.layer2_operational_alerts_read(); end if;' in v_def)=0 then
      raise exception 'Layer 2 alert dispatch marker not found';
    end if;
    v_def:=replace(
      v_def,
      'if p_operation=''layer2_ops_alerts'' then return security.layer2_operational_alerts_read(); end if;',
      'if p_operation=''layer2_ops_alerts'' then return security.layer2_operational_alerts_read(); end if;'||chr(10)||
      ' if p_operation=''layer3_ops_alerts'' then return security.layer3_operational_alerts_read(); end if;'
    );
    execute v_def;
  end if;
end $$;

comment on function public.admin_read(text,jsonb) is
'Governed Admin read dispatcher. M2.4.4 includes rank-gated Layer 3 operational alerts through layer3_ops_alerts.';
