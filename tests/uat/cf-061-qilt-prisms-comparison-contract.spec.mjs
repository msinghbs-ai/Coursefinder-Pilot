import fs from'node:fs/promises'
import{execFileSync}from'node:child_process'
import{test,expect}from'@playwright/test'
import{writeRunEnvironment}from'./support/runtime-evidence.mjs'

// Permanent CF-061 source/build contract.
test.describe('CF-061 QILT PRISMS comparison source/server contract',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-061-qilt-prisms-comparison-contract',change_control:'CF-CHG-20260901-061'})})

 test('builds bounded comparison UX without mutating governed authority',async()=>{
  const[ui,context,shell,migration,version,index,manifest,current]=await Promise.all([
   fs.readFile('src/ComparisonWorkspace.jsx','utf8'),
   fs.readFile('src/ContextualInsights.jsx','utf8'),
   fs.readFile('src/mature-main.jsx','utf8'),
   Promise.all([fs.readFile('supabase/migrations/20260901133212_cf_061_contextual_compare_qilt_prisms.sql','utf8'),fs.readFile('supabase/migrations/20260901134059_cf_061_contextual_compare_provider_city_fix.sql','utf8'),fs.readFile('supabase/migrations/20260901134137_cf_061_contextual_insights_study_area_code_fix.sql','utf8')]).then(xs=>xs.join('\n')),
   fs.readFile('src/pim-version-entry.js','utf8'),
   fs.readFile('index.html','utf8'),
   fs.readFile('src/release-manifest.js','utf8'),
   fs.readFile('src/release-currentness-entry.js','utf8'),
  ])

  expect(ui).toContain('const MAX=6')
  expect(ui).toContain('Search universities or providers')
  expect(ui).toContain("adminRead('providers_page'")
  expect(ui).toContain('provider_id:scopedCourse?providerId:null')
  expect(ui).toContain('Choose any governed provider first')
  expect(ui).toContain('Showing the first governed courses for')
  expect(ui).toContain("adminRead('contextual_compare'")
  expect(ui).toContain('Like-for-like QILT rows only')
  expect(ui).toContain('International student flow')
  expect(ui).toContain('PRISMS')
  expect(ui).toContain('National benchmark')
  expect(ui).toContain('confidence_low')
  expect(ui).toContain('confidence_high')
  expect(ui).toMatch(/@media\(max-width:760px\)/)
  expect(ui).not.toMatch(/\.rpc\(|functions\.invoke\(|\bupdate\b|\bdelete\b|\bpublish\b/i)

  expect(context).toContain('confidence_low')
  expect(context).toContain('response_count')
  expect(context).toContain('National benchmark')

  expect(shell).toContain("import ComparisonWorkspace from'./ComparisonWorkspace'")
  expect(shell).toContain("if(page==='Compare')return <ComparisonWorkspace")
  expect(shell).toContain("navigate?.('Compare',{type,ids:data.id})")
  const fallbackVersion=shell.match(/const UI_VERSION='([^']+)'/)?.[1]
  const historyVersion=version.match(/const VERSION='([^']+)'/)?.[1]
  const candidateVersion=manifest.match(/export const UI_VERSION='([^']+)'/)?.[1]
  expect(fallbackVersion).toMatch(/^2\.15\.\d+$/)
  expect(historyVersion).toBe(fallbackVersion)
  expect(candidateVersion).toMatch(/^2\.15\.\d+$/)
  expect(manifest).toContain(`version:'${fallbackVersion}'`)
  expect(current).toContain("from'./release-manifest.js'")
  expect(index).toContain('<title>Coursefinder PIM Admin</title>')
  expect(index).not.toMatch(/Coursefinder PIM Admin v2\.15\.\d+/)

  expect(migration).toContain('security.admin_contextual_insights_v2')
  expect(migration).toContain('security.admin_contextual_compare')
  expect(migration).toContain("p_operation='contextual_compare'")
  expect(migration).toContain('confidence_low')
  expect(migration).toContain('confidence_high')
  expect(migration).toContain('maximum six comparison entities')
  expect(migration).toContain("'city',p.primary_city")
  expect(migration).toContain('esa.external_code study_area_code')
  expect(migration).toContain("catalogue reader role required")
  expect(migration).not.toMatch(/\b(delete|truncate)\s+from\b/i)
  expect(migration).not.toMatch(/\bupdate\s+(catalogue|search|publication)\./i)

  expect(version).toContain('Course comparison provider coverage correction')

  const output=execFileSync('npm',['run','build'],{cwd:process.cwd(),env:process.env,encoding:'utf8',timeout:60000,stdio:['ignore','pipe','pipe']})
  expect(output).toContain('built in')
 })
})