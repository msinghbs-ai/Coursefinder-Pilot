-- CF-239 targeted recovery follow-up
-- Fix the exact targeted UAT failures without changing governed budgets or data semantics.

-- public.admin_read is SECURITY INVOKER. Private helpers it calls must remain executable
-- by authenticated callers while retaining their own authentication/rank checks.
grant execute on function security.admin_evidence_page_default_fast(jsonb) to authenticated, service_role;
revoke execute on function security.admin_evidence_page_default_fast(jsonb) from public, anon;

-- Narrow indexes support the existing Layer 2 overview projection without scanning wide rows.
create index if not exists evidence_artifacts_layer2_overview_idx
  on pipeline.evidence_artifacts (review_state, retention_class, captured_at desc)
  where (metadata->>'layer')='2';

create index if not exists courses_provider_with_url_idx
  on catalogue.courses (provider_id, id)
  where course_url is not null and course_url <> '';

-- Reuse the already-governed Layer 2 overview implementation exactly. The failure evidence
-- showed material planner/JIT overhead; disabling JIT for this read removes that overhead
-- without changing any returned field, count, role requirement or operational semantics.
create or replace function security.admin_layer2_ops_overview_fast()
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog, security
set jit = off
as $function$
  select security.admin_layer2_ops_read('layer2_ops_overview','{}'::jsonb)
$function$;

revoke all on function security.admin_layer2_ops_overview_fast() from public, anon;
grant execute on function security.admin_layer2_ops_overview_fast() to authenticated, service_role;

-- Keep public.admin_read SECURITY INVOKER and preserve every existing dispatch route.
-- Replace only the Layer 2 overview branch, with a guarded source-definition rewrite so
-- the migration fails closed if the expected dispatcher contract is no longer present.
do $migration$
declare
  v_oid oid;
  v_definition text;
  v_old text := 'if p_operation in (''layer2_ops_overview'',''layer2_ops_run_detail'') then return security.admin_layer2_ops_read(p_operation,p_args); end if;';
  v_new text := 'if p_operation=''layer2_ops_overview'' then return security.admin_layer2_ops_overview_fast(); end if;' || E'\n ' || 'if p_operation=''layer2_ops_run_detail'' then return security.admin_layer2_ops_read(p_operation,p_args); end if;';
begin
  select p.oid into v_oid
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='admin_read'
    and pg_get_function_identity_arguments(p.oid)='p_operation text, p_args jsonb';

  if v_oid is null then
    raise exception 'CF-239: public.admin_read(text,jsonb) not found';
  end if;

  select pg_get_functiondef(v_oid) into v_definition;
  if position(v_old in v_definition)=0 then
    raise exception 'CF-239: expected Layer 2 dispatcher branch not found; refusing ungoverned rewrite';
  end if;

  v_definition := replace(v_definition,v_old,v_new);
  execute v_definition;
end
$migration$;
