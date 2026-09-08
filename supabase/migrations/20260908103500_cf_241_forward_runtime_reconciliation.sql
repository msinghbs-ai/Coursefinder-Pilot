-- CF-241 — forward reconciliation of superseded CF-239 admin_read helper routing.
--
-- Scope is intentionally narrow:
--   * restore evidence_page to the governed security.admin_evidence_page implementation;
--   * restore layer2_ops_overview to security.admin_layer2_ops_read;
--   * preserve all other current admin_read routes, including later accepted Course PIM work;
--   * leave CF-239 helper definitions and indexes in place for separate planner/latency review;
--   * do not mutate canonical data.
--
-- This migration is replay-safe across the checked-in pre-CF-239 dispatcher, the live
-- superseded CF-239 dispatcher, and the already-reconciled dispatcher. It fails closed
-- on any other shape rather than guessing.

do $$
declare
  v_oid oid := to_regprocedure('public.admin_read(text,jsonb)');
  v_definition text;
  v_evidence_old constant text := 'if p_operation=''evidence_page'' then return security.admin_evidence_page_default_fast(p_args); end if;';
  v_evidence_checked_in constant text := 'if p_operation in (''evidence_page'',''evidence_filters'',''evidence_detail'',''evidence_observations'',''evidence_entities'') then return security.admin_evidence_read(p_operation,p_args); end if;';
  v_evidence_checked_in_reconciled constant text := 'if p_operation=''evidence_page'' then return security.admin_evidence_page(p_args); end if;' || E'\n ' || 'if p_operation in (''evidence_filters'',''evidence_detail'',''evidence_observations'',''evidence_entities'') then return security.admin_evidence_read(p_operation,p_args); end if;';
  v_evidence_new constant text := 'if p_operation=''evidence_page'' then return security.admin_evidence_page(p_args); end if;';
  v_layer2_old constant text := 'if p_operation=''layer2_ops_overview'' then return security.admin_layer2_ops_overview_fast(); end if;';
  v_layer2_checked_in constant text := 'if p_operation in (''layer2_ops_overview'',''layer2_ops_run_detail'') then return security.admin_layer2_ops_read(p_operation,p_args); end if;';
  v_layer2_checked_in_reconciled constant text := 'if p_operation=''layer2_ops_overview'' then return security.admin_layer2_ops_read(''layer2_ops_overview'',p_args); end if;' || E'\n ' || 'if p_operation=''layer2_ops_run_detail'' then return security.admin_layer2_ops_read(p_operation,p_args); end if;';
  v_layer2_new constant text := 'if p_operation=''layer2_ops_overview'' then return security.admin_layer2_ops_read(''layer2_ops_overview'',p_args); end if;';
begin
  if v_oid is null then
    raise exception 'CF-241: public.admin_read(text,jsonb) is missing' using errcode = '55000';
  end if;

  select pg_get_functiondef(v_oid) into v_definition;

  if position(v_evidence_old in v_definition) > 0 then
    v_definition := replace(v_definition, v_evidence_old, v_evidence_new);
  elsif position(v_evidence_checked_in in v_definition) > 0 then
    v_definition := replace(v_definition, v_evidence_checked_in, v_evidence_checked_in_reconciled);
  elsif position(v_evidence_new in v_definition) = 0 then
    raise exception 'CF-241: evidence_page dispatcher shape is neither checked-in, superseded nor reconciled' using errcode = '55000';
  end if;

  if position(v_layer2_old in v_definition) > 0 then
    v_definition := replace(v_definition, v_layer2_old, v_layer2_new);
  elsif position(v_layer2_checked_in in v_definition) > 0 then
    v_definition := replace(v_definition, v_layer2_checked_in, v_layer2_checked_in_reconciled);
  elsif position(v_layer2_new in v_definition) = 0 then
    raise exception 'CF-241: layer2_ops_overview dispatcher shape is neither checked-in, superseded nor reconciled' using errcode = '55000';
  end if;

  execute v_definition;
end
$$;

comment on function public.admin_read(text,jsonb) is
  'Governed Admin read dispatcher. CF-241 restores pre-CF-239 Evidence and Layer 2 overview routes while preserving later accepted contracts.';
