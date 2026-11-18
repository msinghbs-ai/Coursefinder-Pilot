// Guards: destination page facts (Platform Admin 18 Nov 2026 14:23 and 15:32): figures and rules are read from official pages by a pattern with a verbatim quote, evidence and the time read, never typed in; restricted terms are not read; QILT stays gated; a reviewed row is never changed.
// CF-247 S653. supabase/migrations/20261118185000_cf247_destination_page_facts.sql and 20261118186000 (first load), supabase/functions/_shared/cf247-page-facts.js, layer1-destination-geo-loader v1.2.0 mode facts.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { anchorWindows, extractFact, htmlToText, linkWords, parseOccupationGrid, quoteAround, xlsxLinks } from '../../supabase/functions/_shared/cf247-page-facts.js'

const M = fs.readFileSync('supabase/migrations/20261118185000_cf247_destination_page_facts.sql', 'utf8')
const R = fs.readFileSync('supabase/migrations/20261118191000_cf247_destination_page_facts_reader_fix.sql', 'utf8')
const S = fs.readFileSync('supabase/migrations/20261118194000_cf247_destination_page_facts_second_load.sql', 'utf8')
const F = fs.readFileSync('supabase/migrations/20261118186000_cf247_destination_page_facts_first_load.sql', 'utf8')
const E = fs.readFileSync('supabase/functions/layer1-destination-geo-loader/index.ts', 'utf8')

const PAGE = `<html><head><title>Student visa</title><style>.x{color:red}</style></head><body>
<nav>Menu</nav><script>window.dataLayer = [{"price": "AUD 9,999"}]</script>
<h2>Cost</h2><p>From AUD2,000.00&nbsp;for the main applicant. Family members pay more.</p>
<h2>Work</h2><p>You can work up to 48 hours per fortnight while your course is in session.</p>
<p>12 month living costs: You &ndash; AUD29,710</p>
<p>You must have Overseas Student Health Cover (OSHC) for the whole stay.</p></body></html>`

test('the page is reduced to its visible text: scripts, styles and tags go, entities are decoded', () => {
  const t = htmlToText(PAGE)
  expect(t).not.toContain('dataLayer')
  expect(t).not.toContain('color:red')
  expect(t).not.toContain('<p>')
  expect(t).toContain('From AUD2,000.00 for the main applicant.')
  expect(t).toContain('You – AUD29,710')
})

test('a fact keeps its value and a verbatim quote that is found again in the same text', () => {
  const t = htmlToText(PAGE)
  const fee = extractFact(t, { pattern: 'From\\s+AUD\\s?\\$?\\s?([0-9][0-9,]{2,})', kind: 'amount', min: 300, max: 20000 })
  expect(fee).toMatchObject({ found: true, raw: '2,000', value: 2000 })
  expect(t).toContain(fee.quote)
  expect(fee.quote).toContain(fee.match)
  const hours = extractFact(t, { pattern: '([0-9]{2})\\s+hours\\s+(?:per|a|every|each|in\\s+a)\\s+fortnight', kind: 'number', min: 20, max: 80 })
  expect(hours).toMatchObject({ found: true, value: 48 })
  expect(hours.quote).toBe('You can work up to 48 hours per fortnight while your course is in session.')
  const funds = extractFact(t, { pattern: 'living costs?[^.]{0,200}?(?:AUD|A?\\$)\\s?([0-9]{2},?[0-9]{3})', kind: 'amount', min: 15000, max: 80000 })
  expect(funds).toMatchObject({ found: true, value: 29710 })
  const oshc = extractFact(t, { pattern: '(Overseas Student Health Cover)', kind: 'text' })
  expect(oshc).toMatchObject({ found: true, value: 'Overseas Student Health Cover' })
})

test('a miss, an implausible value or a bad pattern writes nothing; the anchor shows what the page says', () => {
  const t = htmlToText(PAGE)
  expect(extractFact(t, { pattern: 'Post-Higher Education Work[^.]{0,240}?up to\\s+([0-9])\\s+years', kind: 'number' }).found).toBe(false)
  expect(extractFact(t, { pattern: '([0-9]{2})\\s+hours', kind: 'number', min: 50, max: 80 })).toMatchObject({ found: false })
  expect(extractFact(t, { pattern: '([', kind: 'number' }).reason).toMatch(/bad pattern/)
  const w = anchorWindows(t, 'fortnight')
  expect(w).toHaveLength(1)
  expect(w[0]).toContain('48 hours per fortnight')
  expect(quoteAround('One. Two three four. Five.', 9, 14)).toBe('Two three four.')
})

test('the JSA workbook is found by its link text and loads only from the columns its header names', () => {
  const links = xlsxLinks('<a href="/sites/default/files/2025-11/OSCA%20Occupation%20data%20-%202021%20Census.xlsx">OSCA Occupation data - 2021 Census.xlsx</a><a href="/x.pdf">PDF</a>',
    'https://www.jobsandskills.gov.au/data/labour-market-insights')
  expect(links).toEqual([{ href: 'https://www.jobsandskills.gov.au/sites/default/files/2025-11/OSCA%20Occupation%20data%20-%202021%20Census.xlsx', text: 'OSCA Occupation data - 2021 Census.xlsx' }])
  const g = parseOccupationGrid([['Occupation data'], [], ['OSCA code', 'OSCA occupation', "Employed ('000)", 'Median weekly earnings ($)'],
    [211111, 'Accountant', 12.5, 1850], ['', 'Total', 999, 1], ['2232', 'ICT Business Analyst', '3.2', '2,100']])
  expect(g.header).toMatchObject({ row: 2, code: 'OSCA code', title: 'OSCA occupation', thousands: true })
  expect(g.rows).toEqual([
    { code: '211111', title: 'Accountant', median_weekly_earnings: 1850, employment_count: 12500 },
    { code: '2232', title: 'ICT Business Analyst', median_weekly_earnings: 2100, employment_count: 3200 },
  ])
  expect(parseOccupationGrid([['Region', 'Value'], ['NSW', 1]])).toEqual({ header: null, rows: [] })
})

test('the migration: facts as data, terms recorded, restricted editions not read, QILT untouched, reviewed rows kept, nothing dropped', () => {
  expect(M).toContain('create table if not exists destination.page_facts (')
  expect(M).toContain("comment on table destination.page_facts is")
  expect(M).toContain("('Fair Work Ombudsman National Minimum Wage', 'restricted',")
  expect(M).toContain("('Home Affairs Student visa (subclass 500) and Temporary Graduate visa (subclass 485) pages', 'approved', 'CC BY 3.0 AU',")
  expect(M).toContain("('JSA OSCA Occupation data (2021 Census)', 'approved', 'CC BY 4.0',")
  expect(M).toContain("where f.status = 'active' and f.kind <> 'workbook' and e.terms_status <> 'restricted'")
  expect(M).toContain("raise exception 'post-check: QILT stays gated'")
  expect(M).toContain("last_reason = 'The page now says something different from the approved rule; a person decides'")
  expect(M).toContain("v_jkept := v_jkept + 1;  -- approved, published, superseded or withdrawn: never changed by a load")
  expect(M).toContain("v_cap := security.pipeline_num_v1('destination.career_rows_max', 3000)::int;")
  expect(M).toContain("if md5(v_src) <> '4d86b440f24f10e16707a777153fba62' then")
  expect(M).toContain("('destination-page-facts-load', 'layer1-destination-geo-loader', jsonb_build_object('mode', 'facts'))")
  expect(M).not.toContain("security.destination_job_run_now_v1('destination-page-facts-load',")  // migrations apply before functions deploy
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
  expect(M).not.toMatch(/website_v2_|website_edge_|zoho_edge_|website_api_v2_/)
})

test('the loader: mode facts reads the pages and the workbook through the shared reader', () => {
  expect(E).toMatch(/const VERSION = "layer1-destination-geo-loader-v1\.([2-9]|[1-9][0-9])\.[0-9]+";/)
  expect(E).toMatch(/import \{ anchorWindows, extractFact, [^}]*htmlToText, linkWords, parseOccupationGrid, xlsxLinks \} from "\.\.\/_shared\/cf247-page-facts\.js";/)
  expect(E).toContain('const link = links.find((l) => re.test(linkWords(l)));')
  expect(E).toMatch(/if \(clean\(body\.mode\) === "facts"\) return await facts\(service, runId, trigger, started.*\);/)  // v1.4.0 adds the scope
  expect(E).toContain('await rpc(service, "svc_destination_page_facts_load_v1", { p_payload: { run_id: runId, trigger, pages, jsa } });')
  expect(E).toMatch(/const path = `destination\/page-facts\/\$\{host\}\/\$\{hash\}[^`]*\.html`;/)  // v1.3.0 marks a rendered copy
})

test('the first load is asked for only after the loader that knows mode facts is deployed', () => {
  expect(F).toContain("raise exception 'the page-facts load (20261118185000) is not applied';")
  expect(F).toContain("v_run := security.destination_job_run_now_v1('destination-page-facts-load',")
  expect(F).not.toMatch(/^\s*(delete from|drop |truncate )/im)
  expect(S).toContain("raise exception 'the page-facts reader fix (20261118191000) is not applied';")
  expect(S).toContain("v_run := security.destination_job_run_now_v1('destination-page-facts-load',")
  expect(S).not.toMatch(/^\s*(delete from|drop |truncate )/im)
})

test('regression (first live run, 18 Nov 2026): a self-closing tag never swallows the page, and JSA download routes are found', () => {
  const page = '<html><head><title>T</title><script src="a.js"/></head><body><svg class="i"/><nav>Menu</nav><template id="t"/>' +
    '<p>You can work up to 48 hours per fortnight.</p><svg><path d="M0"/></svg><script>var x = "</div>"</script><p>From AUD2,000.</p></body></html>'
  const t = htmlToText(page)
  expect(t).toContain('You can work up to 48 hours per fortnight.')
  expect(t).toContain('From AUD2,000.')
  expect(t).not.toContain('var x')
  expect(t).not.toContain('T Menu')
  const links = xlsxLinks("<a class='d' href='/download/21600/osca-occupation-data-2021-census/4300/osca-occupation-data-2021-census/xlsx'><span>XLSX</span> 2.1 MB</a>" +
    '<a href=/download/1/report/2/report/pdf>PDF</a>', 'https://www.jobsandskills.gov.au/data/labour-market-insights')
  expect(links).toHaveLength(1)
  expect(links[0].href).toBe('https://www.jobsandskills.gov.au/download/21600/osca-occupation-data-2021-census/4300/osca-occupation-data-2021-census/xlsx')
  expect(new RegExp('OSCA\\s+Occupation\\s+data', 'i').test(linkWords(links[0]))).toBe(true)
  expect(R).toContain("select pg_temp.cf_edit('security.destination_page_facts_load_v1(jsonb)'::regprocedure, 'f6c8e940310ba8d8f5bef70a3e746348',")
  expect(R).not.toMatch(/^\s*(delete from|drop |truncate )/im)
})
