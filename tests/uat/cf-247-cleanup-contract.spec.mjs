// CF-247 clean-up of the old system (Platform Admin, 9 Oct 2026). Each batch removes only what is switched off or unused.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const batch1 = ['cf212-qs-endpoint-verify', 'cf212-qs-evidence-upload', 'cf212-qs-page-probe', 'cf213-qs-meta-probe', 'cf231-qs2026-revalidate-once',
  'cricos-depth-inspect', 'layer1-au-full-gate', 'layer1-depth-uat', 'layer1-nz-gate-uat', 'layer1-nz-source-inspect', 'layer1-runtime-uat',
  'layer2-course-discover', 'layer2-trial-control', 'layer3-benchmark-go5', 'layer4-course-resolve', 'ranking-qs-2027-binary-recovery',
  'ranking-qs-2027-publish-recovery', 'ranking-qs-backfill-once', 'ranking-qs-backfill-trigger-once', 'ranking-qs-source-recovery',
  'ranking-qs-static-backfill-year', 'ranking-qs-upload-recovery', 'scholarship-course-fill-control', 'search-vector-gate']

test('batch 1: retired functions have no source, are on the retired list and are not deployable', () => {
  const wf = fs.readFileSync('.github/workflows/deploy-edge-functions.yml', 'utf8')
  const retired = wf.match(/RETIRED="([^"]*)"/)[1].split(/\s+/).filter(Boolean)
  for (const f of batch1) {
    expect(fs.existsSync(`supabase/functions/${f}`), f).toBe(false)
    expect(retired, f).toContain(f)
    expect(wf, f).not.toContain(`[${f}]=`)
  }
})

test('batch 1: old cron jobs removed only while switched off; functions and history kept', () => {
  const m = fs.readFileSync('supabase/migrations/20261008005200_cf247_cleanup_batch1_old_cron_jobs.sql', 'utf8')
  expect(m).toContain("if exists (select 1 from cron.job where jobname = j and active) then")
  expect(m).toContain('perform cron.unschedule(j);')
  expect(m).not.toMatch(/delete\s+from|drop\s+(table|function|schema)|truncate/i)
  for (const j of ['coursefinder-layer2-fanout-scheduler', 'coursefinder-layer2-qualification-finalizer', 'coursefinder-layer2-qualification-scheduler',
    'coursefinder-layer2-refresh-dispatcher', 'coursefinder-layer2-wave-scheduler', 'layer2-auto-discovery', 'layer2-stale-wave-closer', 'layer3-tuition-enqueue'])
    expect(m, j).toContain(`'${j}'`)
})
