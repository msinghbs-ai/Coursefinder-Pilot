do $$
declare
  r record;
begin
  -- Internal domain schemas are server-owned. Browser roles must never depend on
  -- direct schema/table access; they use curated public RPC/API contracts.
  foreach r in array array[]::record[] loop end loop;

  for r in
    select c.oid, n.nspname as schema_name, c.relname as table_name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relkind = 'r'
      and n.nspname in (
        'ref','catalogue','pim','scholarship','integration',
        'pipeline','search','publishing','workflow','security'
      )
  loop
    execute format('alter table %I.%I enable row level security', r.schema_name, r.table_name);
    execute format('revoke all privileges on table %I.%I from anon', r.schema_name, r.table_name);
    execute format('revoke all privileges on table %I.%I from authenticated', r.schema_name, r.table_name);
    execute format('grant all privileges on table %I.%I to service_role', r.schema_name, r.table_name);
  end loop;

  for r in
    select sequence_schema as schema_name, sequence_name
    from information_schema.sequences
    where sequence_schema in (
      'ref','catalogue','pim','scholarship','integration',
      'pipeline','search','publishing','workflow','security'
    )
  loop
    execute format('revoke all privileges on sequence %I.%I from anon', r.schema_name, r.sequence_name);
    execute format('revoke all privileges on sequence %I.%I from authenticated', r.schema_name, r.sequence_name);
    execute format('grant all privileges on sequence %I.%I to service_role', r.schema_name, r.sequence_name);
  end loop;

  -- Remove direct schema traversal for browser roles. SECURITY DEFINER RPCs with
  -- fixed search_path remain the application boundary.
  revoke usage on schema ref, catalogue, pim, scholarship, integration,
    pipeline, search, publishing, workflow, security from anon, authenticated;

  grant usage on schema ref, catalogue, pim, scholarship, integration,
    pipeline, search, publishing, workflow, security to service_role;
end $$;
