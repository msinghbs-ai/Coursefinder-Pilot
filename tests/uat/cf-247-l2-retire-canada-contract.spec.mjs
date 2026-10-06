// CF-247 Decision 220 (v2.15.147): the old Layer 2 pipeline is retired (its 7 jobs paused, nothing removed); Layer 2
// Overview lists only actionable items with buttons; History shows daily progress by country; Canada is admitted like
// New Zealand (site found by name, checked by DLI number or the name on its own .ca home page; exact title; CAD).
import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = 'supabase/migrations/20261002181800_cf247_layer2_retire_canada_admission.sql'

test.describe('static contract', () => {
  test('migration pauses the old jobs, adds the Canadian rule and queue, behind md5 guards', async () => {
    const sql = await fs.readFile(MIG, 'utf8')
    for (const j of ['coursefinder-layer2-fanout-scheduler', 'coursefinder-layer2-refresh-dispatcher', 'coursefinder-layer2-qualification-scheduler',
      'coursefinder-layer2-wave-scheduler', 'layer2-auto-discovery', 'coursefinder-layer2-qualification-finalizer', 'layer2-stale-wave-closer']) expect(sql).toContain(`'${j}'`)
    expect(sql).toContain('cron.alter_job(j.jobid, active := false)')
    expect(sql).not.toMatch(/cron\.unschedule|\bdrop\s|delete\s+from|truncate/i)
    expect(sql).not.toContain("'coursefinder-layer2-housekeeping'")
    expect(sql).not.toContain("'layer2-onboarding-snapshot'")
    expect(sql).toContain("'CAD'")
    expect(sql).toContain(`'official_url', '["exact_title"]'::jsonb`)
    expect(sql).toContain(`'tuition',      '["cricos_code"]'::jsonb`)
    expect(sql).toContain("lower(pr.registration_scheme)='ircc_dli'")
    expect(sql).toContain("'search_verified_'||nullif(p_evidence->>'basis','')")
    expect(sql).toContain("v_dom ~ '^[a-z0-9.-]+\\.ca$'")
    expect(sql).toContain("v_cur not in ('AUD','NZD','CAD')")
    expect(sql.match(/md5 guard|is distinct from r\.guard/g)?.length).toBeGreaterThanOrEqual(2)
  })

  test('worker finds Canadian sites by name or DLI, never on an empty code, and reads CAD', async () => {
    const ix = await fs.readFile('supabase/functions/coverage-sweep/index.ts', 'utf8')
    const ex = await fs.readFile('supabase/functions/coverage-sweep/extract.ts', 'utf8')
    expect(ix).toMatch(/coverage-sweep-worker-v0\.(?:9\.[2-9]|1\d\.\d+)/) // v0.9.2 or later
    expect(ix).toContain('findCanadianSite')
    expect(ix).toContain('if (!host.endsWith(".ca")')
    expect(ix).toContain('no CRICOS provider code to check a site against')
    expect(ix).toContain('fee(text, currencyFor(it.country))')
    expect(ix).toContain('["NZ", "CA"].includes(it.country)')
    expect(ex).toContain('export function siteNameMatch')
    expect(ex).toContain('"dli_number"')
    expect(ex).toMatch(/CAD: \{ re:/)
    expect(ex).toContain('country === "CA" ? "CAD"')
  })

  test('Layer 2 screen no longer reads the old alerts or shows the old run lists', async () => {
    const ui = await fs.readFile('src/layer2-operations-entry.jsx', 'utf8')
    expect(ui).not.toContain("adminRead('layer2_ops_alerts')")
    expect(ui).not.toContain('Recent managed runs')
    expect(ui).not.toContain('Recent page fetches')
    expect(ui).toContain('function ActionRequired')
    expect(ui).toContain('function DailyProgress')
    const main = await fs.readFile('src/mature-main.jsx', 'utf8')
    expect(main).toContain('<AdaptersWorkspace rank={rank} onError={err}/>') // v2.15.200: Layer 2 opens Adapters; the old Overview and History screens are no longer routed
  })
})

// v2.15.200 (Decision 254): the Overview and History screens are retired from Layer 2 (see cf-247-adapters-lifecycle-contract.spec.mjs for the Adapters screen).
