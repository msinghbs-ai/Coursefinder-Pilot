import fs from'node:fs/promises'
import{execFileSync}from'node:child_process'
import{test,expect}from'@playwright/test'
import{writeRunEnvironment}from'./support/runtime-evidence.mjs'

// CF-058 targeted source/build validation trigger — rerun after full managed-run JSX restoration.
test.describe('M2.5 Platform maturity Administration source/server contract',()=>{
  test.beforeAll(async()=>{
    await writeRunEnvironment({
      suite:'m2-5-platform-maturity-admin-contract',
      change_control:'CF-CHG-20260901-058',
    })
  })

  test('builds and preserves governed Administration/platform boundaries',async()=>{
    const[component,css,shell,migration,versionEntry,index,releaseTest]=await Promise.all([
      fs.readFile('src/platform-maturity-entry.jsx','utf8'),
      fs.readFile('src/platform-maturity.css','utf8'),
      fs.readFile('src/mature-main.jsx','utf8'),
      fs.readFile('supabase/migrations/20260901220500_m2_5_platform_maturity_admin_read_surface.sql','utf8'),
      fs.readFile('src/pim-version-entry.js','utf8'),
      fs.readFile('index.html','utf8'),
      fs.readFile('tests/uat/release-notes-deployed.spec.mjs','utf8'),
    ])

    expect(component).toContain('data-platform-maturity="true"')
    for(const op of[
      'platform_readiness','platform_capacity','platform_environment_gates',
      'platform_uat_catalogue','platform_workloads','platform_retention','platform_active_blocks',
    ]) expect(component).toContain("adminRead('"+op+"'")
    expect(component).toContain("supabase.rpc('layer4_block_decide'")
    expect(component).toContain("supabase.rpc('layer4_block_state'")
    expect(component).toContain('not vendor hard quota')
    expect(component).toContain('No destructive purge action exists in this workspace.')
    expect(component).toContain('Production boundary remains closed')
    expect(component).not.toMatch(/supabase\.rpc\(['"](?:.*production.*enable|.*purge|.*delete)/i)
    expect(component).not.toMatch(/functions\.invoke\([^)]*(?:production|purge|delete)/i)

    expect(shell).toContain("import PlatformMaturity from'./platform-maturity-entry'")
    expect(shell).toContain("<PlatformMaturity rank={rank} onError={onError}/>")
    expect(shell).not.toContain("{tool==='platform'&&rank>=6&&<div className=\"m-legacy-host\"><RegulatorySettings")
    expect(shell).toContain("action=\"Open PIM\" onClick={()=>selectTool('pim')}")
    expect(shell).toContain("const UI_VERSION='2.15.18'")
    expect(index).toContain('Coursefinder PIM Admin v2.15.18')
    expect(versionEntry).toContain("const VERSION='2.15.18'")
    expect(versionEntry).toContain("version:'2.15.18'")
    expect(versionEntry).toContain('Platform maturity Administration workspace')
    expect(releaseTest).toContain('v2.15.18')
    expect(releaseTest).toContain('[data-release-version="2.15.18"]')

    expect(css).toContain('.pm-table-wrap')
    expect(css).toContain('overflow-x:auto')
    expect(css).toMatch(/@media\(max-width:1100px\)/)
    expect(css).toMatch(/@media\(max-width:760px\)/)
    expect(css).toMatch(/\.pm-block-layout\{grid-template-columns:1fr\}/)

    expect(migration).toContain('create or replace function security.admin_platform_maturity_read')
    expect(migration).toContain("if v_rank<4 then raise exception 'pipeline_operator role required'")
    for(const op of[
      'platform_readiness','platform_capacity','platform_environment_gates',
      'platform_uat_catalogue','platform_workloads','platform_retention','platform_active_blocks',
    ]) expect(migration).toContain("p_operation='"+op+"'")
    expect(migration).toContain("'data_quality_overview','data_quality_exceptions','data_quality_quarantine'")
    expect(migration).not.toContain('vault_secret_id')
    expect(migration).not.toContain('secret_env_key')
    expect(migration).not.toContain('approval_evidence')
    expect(migration).not.toMatch(/\b(delete|truncate)\s+from\b/i)
    expect(migration).not.toMatch(/\bupdate\s+pipeline\.(?:environment_source_gates|layer2_provider_environment_gates|layer3_profile_environment_gates)\b/i)

    const output=execFileSync('npm',['run','build'],{
      cwd:process.cwd(),
      env:process.env,
      encoding:'utf8',
      timeout:60000,
      stdio:['ignore','pipe','pipe'],
    })
    expect(output).toContain('built in')
  })
})
