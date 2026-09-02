// CF-065 targeted source contract — compact Layer 1 operations v2.
import fs from'node:fs/promises'
import{execFileSync}from'node:child_process'
import{test,expect}from'@playwright/test'

test.describe('CF-065 Layer 1 operations v2 source contract',()=>{
  test('country-first operations and Administration configuration stay separated',async()=>{
    const[layer1,shell,versionEntry,index]=await Promise.all([
      fs.readFile('src/layer1-operations-entry.jsx','utf8'),
      fs.readFile('src/mature-main.jsx','utf8'),
      fs.readFile('src/pim-version-entry.js','utf8'),
      fs.readFile('index.html','utf8'),
    ])
    expect(layer1).toContain('Layer 1 Operations')
    expect(layer1).toContain('Operate governed regulatory, statistical and ranking ingestion by country, source health, schedule and Evidence.')
    expect(layer1).toContain('label="Country"')
    expect(layer1).toContain('label="Dataset"')
    expect(layer1).toContain('label="Status"')
    expect(layer1).toContain('Operational alerts')
    expect(layer1).toContain('export function Layer1SourceSettings()')
    expect(layer1).toContain('Layer 1 source configuration')
    expect(layer1).toContain('Safe maintenance boundary')
    expect(layer1).not.toContain('Advanced source configuration')
    expect(shell).toContain("item('Layer 1 — Operations',Database,4)")
    expect(shell).toContain("['layer1-sources','Layer 1 sources',Database,rank>=6]")
    expect(shell).toContain("tool==='layer1-sources'&&rank>=6&&<Layer1SourceSettings/>")
    const shellVersion=shell.match(/const UI_VERSION='([^']+)'/)?.[1]
    const releaseVersion=versionEntry.match(/const VERSION='([^']+)'/)?.[1]
    expect(shellVersion).toMatch(/^2\\.15\\.\\d+$/)
    expect(releaseVersion).toBe(shellVersion)
    expect(index).toContain(`Coursefinder PIM Admin v${shellVersion}`)
    expect(versionEntry).toContain(`version:'${shellVersion}'`)
    expect(versionEntry).toContain('Layer 1 Operations naming and navigation alignment')
    const output=execFileSync('npm',['run','build'],{cwd:process.cwd(),env:process.env,encoding:'utf8',timeout:60000,stdio:['ignore','pipe','pipe']})
    expect(output).toContain('built in')
  })
})
