// Guards: CF-065 targeted source contract — compact Layer 1 operations v2.
// CF-065 targeted source contract — compact Layer 1 operations v2.
import fs from'node:fs/promises'
import{execFileSync}from'node:child_process'
import{test,expect}from'@playwright/test'

test.describe('CF-065 Layer 1 operations v2 source contract',()=>{
  test('country-first operations and Administration configuration stay separated',async()=>{
    const[layer1,shell,versionEntry,index,manifest,current,nav]=await Promise.all([
      fs.readFile('src/layer1-operations-entry.jsx','utf8'),
      fs.readFile('src/mature-main.jsx','utf8'),
      fs.readFile('src/release-history-legacy.js','utf8'),
      fs.readFile('index.html','utf8'),
      fs.readFile('src/release-manifest.js','utf8'),
      fs.readFile('src/ReleaseNotes.jsx','utf8'),
      fs.readFile('src/nav-map.js','utf8'),
    ])
    expect(layer1).toContain('Layer 1 Operations')
    expect(layer1).toContain('Official registers, statistics and rankings by country: health, schedule and the files loaded.')
    expect(layer1).toContain('label="Country"')
    expect(layer1).toContain('label="Dataset"')
    expect(layer1).toContain('label="Status"')
    expect(layer1).toContain('Operational alerts')
    expect(layer1).toContain('export function Layer1SourceSettings()')
    expect(layer1).toContain('Layer 1 source configuration')
    expect(layer1).toContain('Safe maintenance boundary')
    expect(layer1).toContain('return <><style>{STYLES}</style><section className="l1s-shell">')
    expect(layer1).toContain('className="l1s-grid"')
    expect(layer1).toContain('className="l1s-card"')
    expect(layer1).toContain('Source & authority')
    expect(layer1).toContain('Cadence & guardrails')
    expect(layer1).not.toContain('Advanced source configuration')
    // v2.15.246 (bugs 11/10-3, Feature 2): Runs and Source settings are one Sources list (Operator opens it, rank 4; editing the
    // settings in a row stays Platform Admin, rank 6). The old cards remain exported for the legacy pop-up only.
    expect(nav).toContain("layer1: { label: 'Layer 1 Register', slug: 'layer-1-register', icon: 'database', min: 4,") // v2.15.301: one Sources page, registers first
    expect(nav).not.toContain("label: 'Source settings'")
    expect(shell).toContain("{layer==='all'?<SourcesWorkspace/>:<Layer1Sources/>}")
    expect(layer1).toContain('export function Layer1Sources()')
    expect(layer1).toContain('const set=k=>e=>setForm(f=>({...f,[k]:e.target.value})),canEdit=rank>=6')
    // v2.15.291: the shell has no fixed fallback version (it imports the manifest); the legacy history keeps its baseline.
    const candidateVersion=manifest.match(/export const UI_VERSION='([^']+)'/)?.[1]
    expect(shell).not.toMatch(/const UI_VERSION='2\.15\.\d+'/)
    expect(shell).toContain("import{UI_VERSION}from'./release-manifest.js'")
    expect(candidateVersion).toMatch(/^2\.15\.\d+$/)
    expect(manifest).toContain('version:UI_VERSION') // 7 Oct 2026: the manifest is the single version authority
    expect(current).toContain("from'./release-manifest.js'")
    expect(index).toContain('<title>StudySearch PIM Admin</title>')
    expect(index).not.toMatch(/StudySearch PIM Admin v2\.15\.\d+/)
    expect(versionEntry).toContain('Layer 1 source configuration UI restoration')
    const output=execFileSync('npm',['run','build'],{cwd:process.cwd(),env:process.env,encoding:'utf8',timeout:60000,stdio:['ignore','pipe','pipe']})
    expect(output).toContain('built in')
  })
})