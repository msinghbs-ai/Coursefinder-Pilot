// Guards: CF-093 Scheduled Tasks runtime health contract
import{test,expect}from'@playwright/test'
import fs from'node:fs'

test.describe('CF-093 Scheduled Tasks runtime health contract',()=>{
 test('uses governed Jobs data without manufacturing missing telemetry',async()=>{
  // SS-020 follow-up (4 Nov 2026): the Refresh schedules section retired; the runtime health panel stays on Scheduled jobs › Automations
  const shell=fs.readFileSync('src/mature-main.jsx','utf8')
  const runtime=fs.readFileSync('src/ScheduledRuntimeHealth.jsx','utf8')
  expect(shell).toContain("const ScheduledRuntimeHealth=lazyPage(()=>import('./ScheduledRuntimeHealth'))")
  expect(shell).toContain('<Automations onError={err}/><ScheduledRuntimeHealth onNavigate={hash=>{location.hash=hash}}/>')
  expect(runtime).toContain("import'./scheduled-jobs-config.css'")
  expect(runtime).toContain("const UNKNOWN='Unavailable'")
  expect(runtime).toContain('const queueWait=j=>secondsBetween(j?.created_at,j?.started_at)')
  expect(runtime).toContain('const runDuration=j=>secondsBetween(j?.started_at,j?.completed_at)')
  expect(runtime).toContain('Terminal Jobs missing completion timestamp')
  expect(runtime).toContain('attempt_count')
  expect(runtime).toContain('is intentionally not treated as retry count')
  expect(runtime).toContain("onNavigate('#jobs')")
  expect(runtime).toContain("onNavigate('#evidence')")
  expect(runtime).not.toContain('completed_at||')
  expect(runtime).not.toContain('started_at||')
  expect(runtime).not.toContain('Date.now()')
 })
})
