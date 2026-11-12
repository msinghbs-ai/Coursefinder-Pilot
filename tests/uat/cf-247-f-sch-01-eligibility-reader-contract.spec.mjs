// Guards: F-SCH.01 scholarship eligibility reader and flow guard: a scholarship refused only for "international not stated" is read again (page, then one linked eligibility page on the same site) before it can go to a person; a proven sentence is acted on only by the existing admission rule and only once sch_elig.apply_on is switched on (shadow first); the flow guard raises one integration issue per cause that stops admission (Platform Admin 12 Nov 2026 09:25 "make sure platform is autonomous ... self sustaining")
// No network and no AI: the worker's pure functions (eligibility.ts) run on page fixtures; the worker and the migration are read as text.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { eligibilityLinks, eligibilityOutcome, linkedPageNote, siteOf } from '../../supabase/functions/coverage-sweep/eligibility.ts'

const m = fs.readFileSync('supabase/migrations/20261113030000_cf247_sch_eligibility_reader_and_flow_guard.sql', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const PAGE = 'https://www.unisa.edu.au/student-life/scholarships/vc-international-scholarship/'
const HTML = `<nav><a href="/">Home</a><a href="https://www.facebook.com/unisa">Facebook</a></nav><main><h1>VC International Scholarship</h1>
<a href="#apply">Jump</a><a href="/student-life/scholarships/vc-international-scholarship/">This page</a>
<a href="/media/terms-and-conditions.pdf">Terms and conditions (PDF)</a>
<a href="https://international.unisa.edu.au/scholarships/eligibility">Check your eligibility</a>
<a href='/student-life/scholarships/how-to-apply/'>Apply</a><a href="https://otheruni.edu.au/terms">Terms</a><a href="mailto:x@unisa.edu.au">Contact</a>
<a href="/student-life/scholarships/conditions/" title="Scholarship conditions">Read more</a></main>`

test('the link finder: eligibility or conditions pages on the same site only, best first, never the page itself, a file or another site', () => {
  expect(siteOf('international.unisa.edu.au')).toBe('unisa.edu.au')
  expect(siteOf('www.auckland.ac.nz')).toBe('auckland.ac.nz')
  expect(siteOf('coned.georgebrown.ca')).toBe('georgebrown.ca')
  const all = eligibilityLinks(HTML, PAGE, 5)
  expect(all).toEqual(['https://international.unisa.edu.au/scholarships/eligibility', 'https://www.unisa.edu.au/student-life/scholarships/conditions/',
                       'https://www.unisa.edu.au/student-life/scholarships/how-to-apply/'])
  expect(eligibilityLinks(HTML, PAGE, 1)).toEqual([all[0]])
  expect(eligibilityLinks(HTML, PAGE, 0)).toEqual([])
  expect(eligibilityLinks("<a href='/news/'>News</a>", PAGE, 2)).toEqual([])
  expect(eligibilityLinks(HTML, 'not a url', 1)).toEqual([])
})

test('a linked page is asked about that scholarship only; the outcome is proven (page or linked), silent or unread', () => {
  const req = { messages: [{ role: 'system', content: 's' }, { role: 'user', content: 'Scholarship: X' }] }
  const n = linkedPageNote(req, 'VC International Scholarship', PAGE)
  expect(n.messages[1].content).toContain('This page is linked from the page of the scholarship "VC International Scholarship"')
  expect(n.messages[1].content).toContain('If the page is about other scholarships, answer "not_stated".')
  expect(req.messages[1].content).toBe('Scholarship: X')
  expect(eligibilityOutcome(null, []).outcome).toBe('unread')
  expect(eligibilityOutcome({ audience_proven: true, audience: 'international' }, []).source).toBe('page')
  const lk = eligibilityOutcome({ audience_proven: false }, [{ url: 'u1', status: 'blocked' }, { url: 'u2', status: 'read', judged: { audience_proven: true, audience: 'both' } }])
  expect([lk.outcome, lk.source, lk.source_url]).toEqual(['proven', 'linked', 'u2'])
  expect(eligibilityOutcome({ audience_proven: false }, [{ url: 'u2', status: 'read', judged: { audience_proven: false } }]).outcome).toBe('silent')
})

test('the worker mode: the re-check question and its proof (sentence on the page, names international or domestic), every lease answered once, the pinned model only', () => {
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.75\.0";/)
  const a = worker.indexOf('if (mode === "scholarship_eligibility")'), b = worker.indexOf('// v0.21.0 (fix 3)', a)
  expect(a).toBeGreaterThan(-1)
  const mode = worker.slice(a, b)
  expect(mode).toContain('rpc("svc_scholarship_eligibility_next"')
  expect(mode).toContain('scholarshipRecheckRequest(it.model')
  expect(mode).toContain('judgeScholarshipRecheck(ans.a')
  expect(mode).toContain('if (d?.model && !String(d.model).startsWith(it.model))')
  expect(mode).toContain('storedHtml(it.storage_path)')
  expect(mode).toContain('eligibilityLinks(html, it.url, Number(it.links_max || 0))')
  expect(mode.match(/await rec\(/g).length).toBeGreaterThanOrEqual(5)
  expect(mode).not.toMatch(/api\.firecrawl\.dev/) // linked pages go through readSch (the scholarship share)
})

test('the migration: the reader and its action ship off, a person gets an eligibility case only after the reader is silent, edits are md5-guarded, nothing is admitted here', () => {
  for (const k of ["'sch_elig.on'", "'sch_elig.apply_on'", "'sch_elig.silent_resolves'"]) expect(m).toMatch(new RegExp(`${k.replace('.', '\\.')}[\\s\\S]*?'number', to_jsonb\\(0\\)`))
  expect(m).toContain("'983b3939e4c8686fa6fcb03752f56370'")
  expect(m).toContain("'a9a207a4e7f9481ee202470f98cb4511'")
  expect(m).toContain("and (e.state = 'failed' or (e.state = 'done' and e.outcome = 'silent'))")
  expect(m).toContain("security.scholarship_admit_from_provider_page_v1(r.candidate_id)")
  expect(m).toContain("if not v_live then")
  expect(m).toContain("coalesce(security.url_on_provider_sites(v_url, r.provider_id), false)")
  expect(m).toContain("security.ai_spend_capture_v1('scholarship_ai', 'delta', '{cost_usd}')")
  expect(m).toContain("v_why := security.ai_use_refusal_v1('scholarship_ai');")
  expect(m).toContain("'international_and_domestic', 'both'")
  expect(m).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(m).not.toMatch(/update pipeline\.platform_toolset_settings/i) // no switch is changed by this change
})

test('the flow guard: one issue per cause with the setting that clears it, cleared when gone, reads and reports only', () => {
  for (const c of ["'lane_full:'", "'recovery_off:'", "'dead_end_scope'", "'admission_stalled'", "'cases_overdue'"]) expect(m).toContain(c)
  for (const s of ['sch_elig.on', 'sch_cov.recover_listings_on', 'sch_cov.recover_register_pages_on', 'sch_cov.recover_stored_reads_on', 'retry.scholarship_transient_recover_on']) expect(m).toContain(`('${s}', (select count(*)`)
  expect(m).toContain("'fingerprint', 'sch_flow:' || (x->>'code')")
  expect(m).toContain("set condition_cleared_at = now()")
  expect(m).toContain("perform cron.schedule('scholarship-flow-guard', '43 * * * *', 'select security.scholarship_flow_guard_v1()');")
  expect(m).toContain("perform cron.schedule('scholarship-eligibility', '4-59/10 * * * *', 'select security.scholarship_eligibility_fire_v1()');")
})
