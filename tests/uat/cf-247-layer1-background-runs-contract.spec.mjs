import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// Decision 155 (part 1): Layer 1 runs are advanced in the background and the card shows live truth.
test('Layer 1 background runs: driver-safe control, live card status, readable failures',async()=>{
  const control=fs.readFileSync('supabase/functions/layer1-operations-control/index.ts','utf8')
  expect(control).toContain('const VERSION="layer1-operations-control-v1.3.0"')
  expect(control).toContain('svc_layer1_run_claim')
  expect(control).toContain('svc_pilot_consume_nonce",{p_function:FN')
  expect(control).toContain('internal callers may only continue a run')
  expect(control).toContain('const RETRY_MINUTES=[1,2,4,8,15]')
  expect(control).toContain('p_stage:"retry_waiting"')
  // workers are called with the service identity, never a user's sign-in token
  expect(control).not.toMatch(/authorization:`Bearer \$\{token\}`/)
  const nz=fs.readFileSync('supabase/functions/layer1-nz-live/index.ts','utf8')
  expect(nz).toContain('const VERSION="layer1-nz-live-v1.2.0"')
  expect(nz).toContain('svc_layer1_evidence_by_hash')
  expect(nz).toContain('if(doApply&&!hasMore)catalogueStats')
  const card=fs.readFileSync('src/layer1-operations-entry.jsx','utf8')
  expect(card).toContain('function RunStatus(')
  expect(card).toContain('<RunStatus source={source} rank={rank} busy={busy} onRetry={retry}/>')
  expect(card).toContain("const done=Math.max(0,Number(r?.resume_cursor||0))")
  expect(card).toContain('Runs in the background. You can close this page')
  expect(card).toContain("idempotency_key:`run:${source.source_id}:${mode}:${Date.now()}`")
  expect(card).not.toContain('progress_percent')
  // ranking family card: operational edition is the newest ingested one, titled with its year (CF-068)
  expect(card).toContain('const current=xs.find(x=>x.edition_is_current!==false&&hasData(x))')
  expect(card).toContain('source_label:`${rankingFamilyLabel(current)}${current.edition_year?` ${current.edition_year}`:\'\'}`')
  const flow=fs.readFileSync('.github/workflows/deploy-edge-functions.yml','utf8')
  for(const f of ['[layer1-operations-control]=false','[layer1-nz-live]=true','[layer1-register-etl]=true'])expect(flow).toContain(f)
  const mig=fs.readFileSync('supabase/migrations/20260927030000_layer1_background_run_driver.sql','utf8')
  expect(mig).toContain("cron.schedule('layer1-run-driver'")
})
