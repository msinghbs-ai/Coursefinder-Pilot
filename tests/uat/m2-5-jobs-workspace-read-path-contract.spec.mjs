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
    const[shell,ops,supa,versionEntry,index,releaseTest]=await Promise.all([
      fs.readFile('src/mature-main.jsx','utf8'),
      fs.readFile('src/pipeline-ops-entry.jsx','utf8'),
      fs.readFile('src/lib/supabase.js','utf8'),
      fs.readFile('src/pim-version-entry.js','utf8'),
      fs.readFile('index.html','utf8'),
      fs.readFile('tests/uat/release-notes-deployed.spec.mjs','utf8'),
    ])

    expect(shell).toContain("import{JobsWorkspace,SourcesWorkspace}from'./pipeline-ops-entry'")
    expect(shell).toContain("if(page==='Jobs'&&rank>=4)return <JobsWorkspace/>")
    expect(shell).toContain("if(page==='Sources'&&rank>=4)return <SourcesWorkspace/>")
    expect(shell).not.toContain('OperationalList operation="jobs"')
    expect(shell).not.toContain('OperationalList operation="sources"')

    expect(ops).toContain('export function JobsWorkspace(){')
    expect(ops).toContain('export function SourcesWorkspace(){')
    expect(ops).toContain("adminRead('pipeline_filters')")
    expect(ops).toContain("adminRead('pipeline_jobs_page'")
    expect(ops).toContain("adminRead('pipeline_job_detail'")
    expect(ops).toContain('Server-paged execution history')
    expect(ops).toContain('<th>Created</th>')
    expect(ops).toContain('Evidence linked or referenced by this job')
    expect(ops).toContain('No generic mutation is exposed by this console.')

    expect(supa).not.toContain("if (route === operation) return []")
    expect(supa).not.toContain("Jobs/Sources routes are owned by the Pipeline Ops overlay")
    expect(supa).toContain("Jobs/Sources are canonical shell workspaces again")

    const shellVersion=shell.match(/const UI_VERSION='([^']+)'/)?.[1]
    const releaseVersion=versionEntry.match(/const VERSION='([^']+)'/)?.[1]
    expect(shellVersion).toBe('2.15.20')
    expect(releaseVersion).toBe(shellVersion)
    expect(index).toContain('Coursefinder PIM Admin v2.15.20')
    expect(versionEntry).toContain("version:'2.15.20'")
    expect(versionEntry).toContain('Pipeline Jobs workspace restoration')
    expect(releaseTest).toContain('v2.15.20')

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
