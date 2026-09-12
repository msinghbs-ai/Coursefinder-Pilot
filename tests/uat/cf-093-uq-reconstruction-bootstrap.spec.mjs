import{test,expect}from'@playwright/test'
import fs from'node:fs'

const bootstrapPath='supabase/migrations/20260912005000_cf_093_uq_discovery_strategy_reconstruction_bootstrap.sql'
const immutablePath='supabase/migrations/20260912005948_cf_093_uq_native_program_discovery_profile.sql'
const bootstrap=fs.readFileSync(bootstrapPath,'utf8')
const immutable=fs.readFileSync(immutablePath,'utf8')

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
