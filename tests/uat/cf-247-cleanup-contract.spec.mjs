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

// Batch 2 (Platform Admin, 9 Oct 2026): the old data-admission system's screens, functions and leftovers.
const batch2 = ['layer2-extract', 'layer2-course-fact-extract', 'layer3-interpret', 'layer2-v2-diagnostic', 'layer2-sync-control',
  'layer2-config-control', 'layer2-acquire', 'layer2-batch-runner', 'layer2-scholarship-extract-v2', 'scholarship-scope-job-execute',
  'scholarship-runtime-control']
const batch2Ui = ['src/layer2-platform-entry.jsx', 'src/layer2-platform.css', 'src/Layer2AutomationSettings.jsx', 'src/Layer2DispatcherTuning.jsx',
  'src/layer2-dispatcher-tuning.css', 'src/scheduler-workflow-builder-entry.jsx', 'src/scheduler-workflow-builder.css',
  'src/layer2-provider-onboarding.jsx', 'src/ScholarshipRuntimeWorkspace.jsx', 'src/scholarship-runtime.css']
const srcFiles = dir => fs.readdirSync(dir, { withFileTypes: true }).flatMap(e => e.isDirectory() ? srcFiles(`${dir}/${e.name}`) : [`${dir}/${e.name}`])

test('batch 2: retired functions have no source, are on the retired list and are not deployable', () => {
  const wf = fs.readFileSync('.github/workflows/deploy-edge-functions.yml', 'utf8')
  const retired = wf.match(/RETIRED="([^"]*)"/)[1].split(/\s+/).filter(Boolean)
  for (const f of batch2) {
    expect(fs.existsSync(`supabase/functions/${f}`), f).toBe(false)
    expect(retired, f).toContain(f)
    expect(wf, f).not.toContain(`[${f}]=`)
  }
})

test('batch 2: removed screens are gone and nothing in src/ or the edge functions still calls them', () => {
  for (const f of batch2Ui) expect(fs.existsSync(f), f).toBe(false)
  expect(fs.existsSync('20260926160000_layer2_stale_wave_closer.sql')).toBe(false)
  expect(fs.readFileSync('index.html', 'utf8')).not.toContain('scheduler-workflow-builder')
  const names = new RegExp(`(^|[^a-z0-9-])(${batch2.join('|')})([^a-z0-9-]|$)`)
  for (const f of [...srcFiles('src'), ...srcFiles('supabase/functions')].filter(f => /\.(jsx?|tsx?|css)$/.test(f))) {
    const s = fs.readFileSync(f, 'utf8')
    expect(s, f).not.toMatch(names)
    expect(s, f).not.toContain('current_layer2_wave')
    expect(s, f).not.toContain('layer3_source_pattern_queue')
    for (const ui of batch2Ui) expect(s, f).not.toContain(`./${ui.slice(4).replace(/\.(jsx|css)$/, '')}`)
  }
})

test('batch 2: Providers › Onboarding points to the Adapter builder; Refresh schedules and the provider registry stay', () => {
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(main).toContain("onClick={()=>navigate('layer2',{tab:'builder'})}>Open the Adapter builder</button>")
  expect(main).toContain("const Layer2ProviderConfig=lazyPage(()=>import('./layer2-provider-entry'),'Console')")
  expect(main).toContain("const RefreshWorkspace=lazyPage(()=>import('./m2-3-intelligence-entry'),'Refresh')")
  expect(fs.readFileSync('src/layer2-provider-entry.jsx', 'utf8')).toContain("functions.invoke('layer2-provider-control'")
  const nav = fs.readFileSync('src/nav-map.js', 'utf8')
  expect(nav).toContain("{ key: 'builder', label: 'Adapter builder', min: 5 }")
})

test('batch 4: old database functions dropped behind md5 guards; tables and history kept; four dormant functions retired', () => {
  const m = fs.readFileSync('supabase/migrations/20261008005600_cf247_cleanup_batch4_old_database.sql', 'utf8')
  expect((m.match(/^drop function /gim) || []).length).toBe(15)
  expect(m).not.toMatch(/^drop function [^;]*\bcascade\b/im)
  expect(m).not.toMatch(/drop\s+(table|schema|view)|truncate/i)
  expect(m).toContain("6e6f2d16653913617191a1520f26143f")
  const wf = fs.readFileSync('.github/workflows/deploy-edge-functions.yml', 'utf8')
  const retired = wf.match(/RETIRED="([^"]*)"/)[1].split(/\s+/).filter(Boolean)
  for (const f of ['layer2-extract-v2', 'layer2-course-fact-extract-v2', 'layer2-scholarship-extract', 'layer2-scholarship-catalogue-enumerate']) {
    expect(fs.existsSync(`supabase/functions/${f}`), f).toBe(false)
    expect(retired, f).toContain(f)
    expect(wf, f).not.toContain(`[${f}]=`)
  }
  for (const f of ['layer2-provider-page-fanout', 'layer2-provider-asset-promote', 'layer2-hotcourses-directory-parse', 'layer2-acquire-v2'])
    expect(fs.existsSync(`supabase/functions/${f}`), f).toBe(true)
})
