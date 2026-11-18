// Guards: S676 AER validation status read (Platform Admin 18 Nov 2026 23:52, Thursday 02:45 check): the status mode also reports why would-admit course reads wait (the machine's admit outcomes, when the waiting reads were last checked, the job's last runs) and stays read only.
// CF-247 S676. scripts/aer-validation-renew.mjs (workflow aer-validation-renew.yml).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'

const V = fs.readFileSync('scripts/aer-validation-renew.mjs', 'utf8')

test('the status read reports admit outcomes, the last check of the waiting reads and the job runs, through the read-only route', () => {
  expect(V).toContain('const [dt] = await read(`select')
  expect(V).toContain("from pipeline.aer_machine_admissions where mode = 'admit' and created_at > ${since} group by 1) z) as admit_outcomes")
  expect(V).toContain("where m.mode = 'shadow' and m.outcome = 'would_admit') as would_admit_checked")
  expect(V).toContain("jobname = 'aer-machine-admission'")
  expect(V.indexOf('const [dt] = await read(')).toBeLessThan(V.indexOf("if (MODE !== 'renew') process.exit(0)"))
  expect(() => execFileSync('node', ['--check', 'scripts/aer-validation-renew.mjs'])).not.toThrow()
})
