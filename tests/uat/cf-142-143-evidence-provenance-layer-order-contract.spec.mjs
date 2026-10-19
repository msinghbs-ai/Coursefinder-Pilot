// CF-142/143 targeted source contract — Evidence acquisition provenance and stable L1→L4 navigation.
import fs from'node:fs/promises'
import{execFileSync}from'node:child_process'
import{test,expect}from'@playwright/test'

test.describe('CF-142/143 provenance and navigation order',()=>{
 test('Evidence provenance enhancer and fixed Layer sequence remain wired',async()=>{
  const[index,nav,evidence,migration]=await Promise.all([
   fs.readFile('index.html','utf8'),
   fs.readFile('src/nav-map.js','utf8'),
   fs.readFile('src/EvidenceWorkspace.jsx','utf8'),
   fs.readFile('supabase/migrations-archive/20260904060000_cf_142_evidence_acquisition_provenance.sql','utf8'),
  ])
  // v2.15.107: the fixed Layer 1 > 2 > 3 > 4 order is declared once in nav-map.js (Data pipeline section);
  // the page script that reordered menu buttons (layer2-navigation-restore.js) is gone and nothing injects menu entries.
  // v2.15.252 (Platform Admin, 12 Oct 2026): Layer 3 retired, so the order is Layer 1 > 2 > 4.
  expect(nav).toContain("pages: ['coverage', 'layer1', 'layer2', 'layer4']")
  expect(index).not.toContain('layer2-navigation-restore')
  // v2.15.293 (Platform Admin, 19 Oct 2026: the Evidence panel was bloated and hard to read): the Acquisition provenance box is gone.
  // The panel says how the page was read in one line ("Read on <date>, through Firecrawl | fetched directly") from admin_evidence_summary.
  expect(evidence).not.toContain('Acquisition provenance')
  expect(evidence).not.toContain('AcquisitionProvenance')
  expect(evidence).toContain('api.evidenceSummary(id)')
  expect(evidence).toContain("if(x==='firecrawl')return'through Firecrawl';if(x==='direct')return'fetched directly'")
  expect(index).not.toContain('evidence-acquisition-provenance-entry')
  expect(migration).toContain('admin_evidence_acquisition_provenance')
  expect(migration).toContain("'stored_evidence_derived'")
  expect(migration).toContain("'live_acquisition'")
  const output=execFileSync('npm',['run','build'],{cwd:process.cwd(),env:process.env,encoding:'utf8',timeout:60000,stdio:['ignore','pipe','pipe']})
  expect(output).toContain('built in')
 })
})
