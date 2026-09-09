// CF-142/143 targeted source contract — Evidence acquisition provenance and stable L1→L4 navigation.
import fs from'node:fs/promises'
import{execFileSync}from'node:child_process'
import{test,expect}from'@playwright/test'

test.describe('CF-142/143 provenance and navigation order',()=>{
 test('Evidence provenance enhancer and fixed Layer sequence remain wired',async()=>{
  const[index,nav,evidence,migration]=await Promise.all([
   fs.readFile('index.html','utf8'),
   fs.readFile('src/layer2-navigation-restore.js','utf8'),
   fs.readFile('src/evidence-acquisition-provenance-entry.js','utf8'),
   fs.readFile('supabase/migrations/20260904060000_cf_142_evidence_acquisition_provenance.sql','utf8'),
  ])
  expect(nav.indexOf("label:'Layer 1 — Operations'")).toBeLessThan(nav.indexOf("label:'Layer 2 — Enrichment'"))
  expect(nav.indexOf("label:'Layer 2 — Enrichment'")).toBeLessThan(nav.indexOf("label:'Layer 3 — AI Interpretation'"))
  expect(nav.indexOf("label:'Layer 3 — AI Interpretation'")).toBeLessThan(nav.indexOf("label:'Layer 4 — Human Resolution'"))
  expect(nav).toContain("tabs.dataset.cfLayerOrder='L1>L2>L3>L4'")
  expect(nav).toContain("group.dataset.cfLayerOrder='L1>L2>L3>L4'")
  expect(evidence).toContain('Acquisition provenance')
  expect(evidence).toContain('Derived from stored Evidence')
  expect(evidence).toContain('Storage reuse')
  expect(index).toContain('/src/evidence-acquisition-provenance-entry.js')
  expect(migration).toContain('admin_evidence_acquisition_provenance')
  expect(migration).toContain("'stored_evidence_derived'")
  expect(migration).toContain("'live_acquisition'")
  const output=execFileSync('npm',['run','build'],{cwd:process.cwd(),env:process.env,encoding:'utf8',timeout:60000,stdio:['ignore','pipe','pipe']})
  expect(output).toContain('built in')
 })
})
