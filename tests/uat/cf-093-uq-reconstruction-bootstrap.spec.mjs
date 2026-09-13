import{test,expect}from'@playwright/test'
import fs from'node:fs'

const bootstrapPath='supabase/migrations/20260912005000_cf_093_uq_discovery_strategy_reconstruction_bootstrap.sql'
const immutablePath='supabase/migrations/20260912005948_cf_093_uq_native_program_discovery_profile.sql'
const bootstrap=fs.readFileSync(bootstrapPath,'utf8')
const immutable=fs.readFileSync(immutablePath,'utf8')
const reconstruction=fs.readFileSync('.github/workflows/cf093-fresh-reconstruction.yml','utf8')

test('CF-093 reconstructs the missing UQ discovery_strategy before immutable 005948',()=>{
 expect(bootstrapPath.localeCompare(immutablePath)).toBeLessThan(0)
 expect(bootstrap).toContain("p.profile_key='au-uq-course-catalogue'")
 expect(bootstrap).toContain("if v_cfg ? 'discovery_strategy' then")
 expect(bootstrap).toContain("jsonb_build_object('type','first_party_search')")
 expect(bootstrap).toContain('security.layer2_validate_profile_config')
 expect(bootstrap).toContain("'CF-093-reconstruction-bootstrap-before-005948'")
 expect(immutable).toContain("'{discovery_strategy,search_url_template}'")
 expect(immutable).toContain("'{discovery_strategy,query_field}'")
 expect(immutable).toContain("'{discovery_strategy,require_url_prefix}'")
})

test('CF-093 preserves applied migration 005948 rather than rewriting its identity',()=>{
 expect(immutablePath).toContain('20260912005948_')
 expect(bootstrap).toContain('official Supabase migration-repair command')
 expect(bootstrap).not.toContain('insert into supabase_migrations.schema_migrations')
 expect(bootstrap).not.toContain('delete from supabase_migrations.schema_migrations')
})

test('CF-093 reconstruction fixture matches accepted scope and route contracts and replays final immutable migrations',()=>{
 expect(reconstruction).toContain('returns table(profile_id uuid,profile_key text,provider_id uuid,provider_name text,course_id uuid,source_url text)')
 expect(reconstruction).toContain('create table pipeline.layer2_acquisition_providers(')
 expect(reconstruction).toContain('create table pipeline.layer2_profile_provider_routes(')
 expect(reconstruction).toContain("create or replace function public.layer2_provider_runtime_config(uuid) returns jsonb")
 expect(reconstruction).toContain('20260913015530_cf_093_scheduler_preview_set_based_terminal_optimization.sql')
 expect(reconstruction).toContain('20260913020222_cf_093_scheduler_route_gap_scope_optimization.sql')
 expect(reconstruction).toContain('20260913020646_cf_093_scheduler_run_bridge_acl_reconcile.sql')
})