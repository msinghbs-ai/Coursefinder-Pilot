// CF-060 targeted validation trigger — canonical Jobs route must remain server-paged.
import fs from'node:fs/promises'
import{execFileSync}from'node:child_process'
import{test,expect}from'@playwright/test'
import{writeRunEnvironment}from'./support/runtime-evidence.mjs'

test.describe('M2.5 Jobs workspace read-path source contract',()=>{
  test.beforeAll(async()=>{
    await writeRunEnvironment({
      suite:'m2-5-jobs-workspace-read-path-contract',
      change_control:'CF-CHG-20260901-060',
    })
  })

  test('canonical Jobs route uses governed paged Pipeline Jobs without route suppression',async()=>{
    const[shell,ops,supa,versionEntry,index,releaseTest,manifest,current]=await Promise.all([
      fs.readFile('src/mature-main.jsx','utf8'),
      fs.readFile('src/pipeline-ops-entry.jsx','utf8'),
      fs.readFile('src/lib/supabase.js','utf8'),
      fs.readFile('src/release-history-legacy.js','utf8'),
      fs.readFile('index.html','utf8'),
      fs.readFile('tests/uat/release-notes-deployed.spec.mjs','utf8'),
      fs.readFile('src/release-manifest.js','utf8'),
      fs.readFile('src/ReleaseNotes.jsx','utf8'),
    ])

    expect(shell).toContain("const JobsWorkspace=lazyPage(()=>import('./pipeline-ops-entry'),'JobsWorkspace')")
    expect(shell).toContain("const SourcesWorkspace=lazyPage(()=>import('./pipeline-ops-entry'),'SourcesWorkspace')")
    // v2.15.107: Jobs is the Scheduled jobs > Jobs tab and Sources the Layer 1 Register > Sources tab (both role rank 4).
    expect(shell).toContain(`tab==='automations'?<div className="m-page-stack"><Automations onError={err}/><RefreshWorkspace onError={err}/></div>:<JobsWorkspace/>`)
    expect(shell).toContain("{layer==='all'?<SourcesWorkspace/>:<Layer1Sources/>}") // v2.15.301: Sources is Layer 1's All layers filter
    expect(shell).not.toContain('OperationalList operation="jobs"')
    expect(shell).not.toContain('OperationalList operation="sources"')

    expect(ops).toContain('export function JobsWorkspace(){')
    expect(ops).toContain('export function SourcesWorkspace(){')
    expect(ops).toContain("adminRead('pipeline_filters')")
    expect(ops).toContain("adminRead('pipeline_jobs_page'")
    expect(ops).toContain("adminRead('pipeline_job_detail'")
    expect(ops).toContain('Every job run, newest first.') // v2.15.227: plain wording
    expect(ops).toContain('<th>Created</th>')
    expect(ops).toContain('Evidence linked or referenced by this job')
    expect(ops).toContain('No generic mutation is exposed by this console.')

    expect(supa).not.toContain("if (route === operation) return []")
    expect(supa).not.toContain("Jobs/Sources routes are owned by the Pipeline Ops overlay")
    expect(supa).toContain("Jobs/Sources are canonical shell workspaces again")

    // v2.15.291: the shell has no fixed fallback version (it imports the manifest); the legacy history keeps its baseline.
    const historyVersion=versionEntry.match(/export const LEGACY_BASELINE='([^']+)'/)?.[1]
    const candidateVersion=manifest.match(/export const UI_VERSION='([^']+)'/)?.[1]
    expect(shell).not.toMatch(/const UI_VERSION='2\.15\.\d+'/)
    expect(shell).toContain("import{UI_VERSION}from'./release-manifest.js'")
    expect(historyVersion).toBe('2.15.78')
    expect(candidateVersion).toMatch(/^2\.15\.\d+$/)
    expect(versionEntry).toContain(`version:'${historyVersion}'`)
    expect(current).toContain("from'./release-manifest.js'")
    expect(index).toContain('<title>StudySearch PIM Admin</title>')
    expect(index).not.toMatch(/StudySearch PIM Admin v2\.15\.\d+/)
    expect(versionEntry).toContain('Pipeline Jobs workspace restoration')
    expect(releaseTest).toContain('release notes @deployed')

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