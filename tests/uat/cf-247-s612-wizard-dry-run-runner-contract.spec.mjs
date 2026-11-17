// Guards: Wave 2 admission (Platform Admin 18 Nov 2026 07:34, drafts "mapped, sample-tested, and admitted"): the induction wizard's step 5 runs the dry run through layer1-declarative-runner once the draft has an AI-built parser spec; it writes nothing and switches nothing on, and the screen says when the source address is a landing page rather than a file
// CF-247 S612 (was s599; renumbered 18 Nov 2026 so s599 stays with S2 - BOOST). src/Layer1InductionWizard.jsx.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const W = fs.readFileSync('src/Layer1InductionWizard.jsx', 'utf8')

test('step 5 runs the dry run through the declarative runner, only with a parser spec and only on an open draft', () => {
  expect(W).toContain("export const RUNNER='layer1-declarative-runner'")
  expect(W).toContain("call(RUNNER,{action:'dry_run',induction_id:id})")
  expect(W).toContain('disabled={!id||closed||!f.parser_spec||busy!==\'\'} onClick={dryRun} data-l1i-dry-run-start')
  expect(W).toContain('data-l1i-dry-refresh>Check again</Button>')
  expect(W).not.toMatch(/admin_layer1_induction_activate'[^\n]*dryRun/)
})

test('the screen says what the dry run reads and when a parser spec is still missing', () => {
  expect(W).toContain("label={f.parser_spec?'Ready for a dry run':'Waiting for a reader'}")
  expect(W).toContain('The dry run reads a CSV, XLSX or JSON file, or a table on a web page when the connector is Web pages. If the source address is a landing page, enter the address of the file itself in step 2.')
  expect(W).toContain('use AI Auto-Map in step 3 with a sample of the file')
})
