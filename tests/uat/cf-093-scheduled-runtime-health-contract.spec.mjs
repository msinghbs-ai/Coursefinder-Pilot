import{test,expect}from'@playwright/test'
import fs from'node:fs'

test.describe('CF-093 Scheduled Tasks runtime health contract',()=>{
 test('uses governed Jobs data without manufacturing missing telemetry',async()=>{
  const workspace=fs.readFileSync('src/ScheduledJobsWorkspace.jsx','utf8')
  const runtime=fs.readFileSync('src/ScheduledRuntimeHealth.jsx','utf8')
  expect(workspace).toContain("import ScheduledRuntimeHealth from'./ScheduledRuntimeHealth'")
  expect(workspace).toContain('<ScheduledRuntimeHealth jobs={jobs} error={panelErrors.jobs} onNavigate={go}/>')
  expect(workspace).toContain('const jobStarted=row=>row?.started_at')
  expect(workspace).toContain('const jobFinished=row=>row?.completed_at')
  expect(runtime).toContain("const UNKNOWN='Unavailable'")
  expect(runtime).toContain('const queueWait=j=>secondsBetween(j?.created_at,j?.started_at)')
  expect(runtime).toContain('const runDuration=j=>secondsBetween(j?.started_at,j?.completed_at)')
  expect(runtime).toContain('const totalDuration=j=>secondsBetween(j?.created_at,j?.completed_at)')
  expect(runtime).toContain('Terminal Jobs missing completion timestamp')
  expect(runtime).toContain('attempt_count')
  expect(runtime).toContain('is intentionally not interpreted as retry count')
  expect(runtime).toContain("onNavigate('#jobs')")
  expect(runtime).toContain("onNavigate('#evidence')")
  expect(runtime).not.toContain('completed_at||')
  expect(runtime).not.toContain('started_at||')
  expect(runtime).not.toContain('Date.now()')
 })
})
