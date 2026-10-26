// Weekly deployed run summary for the Monday line (Platform Admin 26 Oct 2026 10:49). Reads the Playwright JSON results of the desktop and
// phone runs and prints markdown: safe specs run and live-acting specs held as two separate counts, then passed / failed / skipped per
// viewport, then each failure. Usage: HELD=<n> node scripts/deployed-weekly-summary.mjs desktop.json phone.json
import fs from 'node:fs'

export function tally(path) {
  if (!path || !fs.existsSync(path)) return { ran: false, tests: 0, passed: 0, failed: 0, skipped: 0, live: 0, failures: [] }
  const r = JSON.parse(fs.readFileSync(path, 'utf8')), out = { ran: true, tests: 0, passed: 0, failed: 0, skipped: 0, live: 0, failures: [] }
  const walk = (s, chain) => {
    for (const sp of s.specs || []) for (const t of sp.tests) {
      const st = t.results?.length ? t.results[t.results.length - 1].status : 'skipped'
      out.tests++
      if (/@live-acting\b/.test(sp.title)) out.live++
      if (st === 'passed') out.passed++
      else if (st === 'skipped') out.skipped++
      else { out.failed++; out.failures.push(`${sp.file} › ${[...chain, sp.title].join(' › ')}`) }
    }
    for (const c of s.suites || []) walk(c, c.title && !c.title.endsWith('.mjs') ? [...chain, c.title] : chain)
  }
  for (const s of r.suites || []) walk(s, [])
  return out
}

if (process.argv[1] && process.argv[1].endsWith('deployed-weekly-summary.mjs')) {
  const d = tally(process.argv[2]), p = tally(process.argv[3]), held = Number(process.env.HELD || 0)
  const date = new Date().toLocaleDateString('en-AU', { timeZone: 'Australia/Melbourne', day: 'numeric', month: 'short', year: 'numeric' })
  const safe = d.tests - d.live
  const lines = [
    `# Deployed weekly run — ${date}`, '',
    `| | Count |`, `|---|---|`,
    `| Safe specs run (tests, desktop) | ${safe} |`,
    `| Live-acting specs run (switch on) | ${d.live} |`,
    `| Live-acting specs held (switch off) | ${held} |`, '',
    `| Viewport | Tests | Passed | Failed | Skipped |`, `|---|---|---|---|---|`,
    `| Desktop | ${d.tests} | ${d.passed} | ${d.failed} | ${d.skipped} |${d.ran ? '' : ' (did not run)'}`,
    `| Phone | ${p.tests} | ${p.passed} | ${p.failed} | ${p.skipped} |${p.ran ? '' : ' (did not run)'}`, '']
  const fails = [...d.failures.map((f) => `- desktop: ${f}`), ...p.failures.map((f) => `- phone: ${f}`)]
  lines.push(fails.length ? '## Failures\n\n' + fails.join('\n') : 'No failures.', '')
  process.stdout.write(lines.join('\n'))
}
