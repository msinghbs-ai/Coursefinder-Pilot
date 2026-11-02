// Guards: AU export (Platform Admin 2 Nov 2026 11:10)
// The complete AU catalogue export (§1, §3, §4) and its snapshot method (Platform Admin 11:18: measure first; one continuous REPEATABLE
// READ READ ONLY snapshot only when the estimate is well under 5 minutes, otherwise one short snapshot per dataset; never idle inside a
// transaction across admission windows; production impact recorded before execution). This spec holds the contract: every SQL text is a
// single read-only select with keyset pagination, transactions are REPEATABLE READ READ ONLY with a statement time-out and no wait inside
// them, and the workflow confirms the project ref, keeps data and credentials out of logs and git, and keeps the artifact 14 days.
// The behaviour is run on isolated fixtures by tests/fixtures/au-catalogue-export/run.sh (scratch PostgreSQL, live baseline table
// definitions, a select-only role, both snapshot modes, every manifest check) and at live scale by scale.sh under a 512 MB heap (run
// 41377240304, 2 Nov 2026, ran out of heap verifying: verification and the derived sheets now stream). G2, G3 and housekeeping are guarded
// centrally (s32, s57, s42).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { allSql, datasets, boundarySql, pageSql, sets } from '../../scripts/export/au-catalogue-queries.mjs'
import { cronMinutes, rangeMinutes, tensMinutes, quietGaps, intervalQuiet, redact, toCsv } from '../../scripts/export/au-catalogue-export.mjs'
import { parseCsv, CsvParser } from '../../scripts/export/csv.mjs'
import { compare, fieldStates, STATE_FIELDS, RECON_FIELDS } from '../../scripts/export/au-catalogue-derived.mjs'

const driver = fs.readFileSync('scripts/export/au-catalogue-export.mjs', 'utf8')
const wf = fs.readFileSync('.github/workflows/au-catalogue-export.yml', 'utf8')
const WRITES = /\b(insert|update|delete|merge|upsert|truncate|create|alter|drop|grant|revoke|comment|call|do|lock|vacuum|analyze|refresh|reindex|cluster|notify|listen|nextval|setval|pg_advisory_lock|set_config|lo_import|pg_read_file|dblink)\b/i
const ALLOWED_FUNCTIONS = new Set(['security.region_fallback_countries_v1'])

test('every SQL text the export can run is one read-only select, and calls no function that could write', () => {
  const all = allSql('AU', ['course_id', 'provider_id', 'search_tsv', 'search_text', 'official_course_url'])
  expect(all.length).toBeGreaterThan(100)
  for (const sql of all) {
    const body = sql.replace(/'(?:[^']|'')*'/g, "''")
    expect(body.trim(), sql.slice(0, 120)).toMatch(/^select\s/i)
    expect(body, sql.slice(0, 120)).not.toContain(';')
    expect(body, sql.slice(0, 120)).not.toMatch(WRITES)
    expect(body, sql.slice(0, 120)).not.toMatch(/\bfor\s+(update|share|no key update|key share)\b/i)
    for (const [, fn] of body.matchAll(/\b((?:security|search|pipeline|public|api|scholarship|catalogue|cron)\.[a-z0-9_]+)\s*\(/gi)) {
      expect(ALLOWED_FUNCTIONS.has(fn.toLowerCase()), `function ${fn}`).toBe(true)
    }
  }
})

test('the driver opens only REPEATABLE READ READ ONLY transactions, with a statement time-out, and never waits inside one', () => {
  expect(driver).toContain("const TXN_BEGIN = 'begin isolation level repeatable read read only'")
  expect(driver).toContain("if (snap.read_only !== 'on' || snap.isolation !== 'repeatable read')")
  expect(driver).toMatch(/set local statement_timeout = '\$\{Number\(stmtTimeoutS\)\}s'; set local lock_timeout = '5s'; set local idle_in_transaction_session_timeout = '60s'/)
  // every literal statement sent outside the query module is a transaction control or a local setting
  const sent = [...driver.matchAll(/pg\.exec\(([`'])((?:\\.|(?!\1).)*)\1/g)].map((m) => m[2])
  expect(sent.length).toBeGreaterThan(5)
  for (const s of sent) expect(s, s).toMatch(/^(\$\{TXN_BEGIN\};( set local statement_timeout = '\$\{C\.statementTimeoutS\}s';)?|set local [^;]+;( set local [^;]+;)*|commit;|rollback;|\$\{aborted \? 'rollback;' : 'commit;'\}|copy \(\$\{sql\}\) to stdout with \(format csv, header true\) \\\\g '\$\{file\}')$/)
  // no begin other than the read-only one
  for (const m of driver.matchAll(/\bbegin\s+(?!isolation level repeatable read read only)/gi)) throw new Error(`other begin: ${m[0]}`)
  // between each snapshot start and its end there is no wait or sleep (11:18: no transaction idle across admission windows)
  let i = 0, blocks = 0
  while ((i = driver.indexOf('await beginSnapshot(pg', i + 1)) > 0) {
    const end = driver.indexOf("commit;", i)
    const block = driver.slice(i, end)
    expect(block).not.toMatch(/\bwait\(|\bsleep\(/)
    blocks++
  }
  expect(blocks).toBe(3) // single, per_dataset page group, final checks
  // the measure counts and the calibration page are their own short read-only transactions
  expect(driver).toContain("await pg.exec(`${TXN_BEGIN}; set local statement_timeout = '${C.statementTimeoutS}s';`)")
  // the single snapshot falls back to per_dataset after SINGLE_ABORT_S, rolled back
  expect(driver).toContain("(Date.now() - t0) / 1000 > C.singleAbortS")
  expect(driver).toContain("await pg.exec(aborted ? 'rollback;' : 'commit;')")
})

test('every dataset is read by keyset pagination on its unique key, never by offset', () => {
  const D = datasets('AU', ['course_id', 'search_tsv'])
  const names = D.map((d) => d.name)
  for (const n of ['courses', 'course_fees', 'course_intakes', 'course_entry_requirements', 'english_requirements', 'course_scholarships', 'scholarship_master',
    'provider_rankings', 'provider_entry_matrices', 'course_links', 'course_campuses', 'course_identifiers', 'course_pages_held', 'search_course_documents', 'layer4_course_review_items']) {
    expect(names).toContain(n)
  }
  for (const d of D.filter((x) => x.key)) {
    const b = boundarySql(d, null, 2000), b2 = boundarySql(d, d.key.map(() => 'k'), 2000), p = pageSql(d, d.key.map(() => 'a'), d.key.map(() => 'b'))
    expect(b).toContain(`order by ${d.key.join(', ')} limit 2000`)
    expect(b2).toContain(`${d.key.length === 1 ? d.key[0] : `(${d.key.join(', ')})`} > `)
    expect(p).toMatch(/ > .* and .* <= /s)
    expect(p).toContain(`order by ${d.key.join(', ')}`)
    for (const s of [b, b2, p]) expect(s).not.toMatch(/\boffset\b/i)
  }
  // AU is decided by the provider's country, so every AU course is held whatever its lifecycle or publication status
  expect(sets('AU').AUC).toBe("(select c.id from catalogue.courses c where c.provider_id in (select p.id from catalogue.providers p where p.country_id = (select co.id from ref.countries co where co.iso_alpha2 = 'AU')))")
  expect(D.find((d) => d.name === 'courses').where).not.toMatch(/lifecycle_status|publication_status/)
  expect(() => sets("AU'; --")).toThrow()
})

test('the API v2 population flag uses the projection itself, and the consumer rules are written on each dataset', () => {
  const D = datasets('AU', ['course_id'])
  const c = D.find((d) => d.name === 'courses')
  expect(c.select).toContain('exists (select 1 from search.course_documents d0 where d0.course_id = c.id) as x_in_website_api_v2')
  expect(c.select).toContain("p.publication_status = 'published'")
  // served = a projection row and no active Layer 4 search block (the live course item returns null for a blocked course)
  const served = "c.id not in (select b.course_id from security.layer4_search_blocked_courses b where b.course_id is not null)) as x_consumer_visible"
  expect(c.select).toContain(served)
  for (const n of ['course_fees', 'course_intakes', 'english_requirements', 'course_scholarships', 'course_links', 'course_entry_requirements', 'course_campuses']) {
    expect(D.find((x) => x.name === n).select, n).toMatch(/not in \(select b\.course_id from security\.layer4_search_blocked_courses b where b\.course_id is not null\)\)[^,]*(\) )?/)
  }
  expect(D.find((d) => d.name === 'search_course_documents').select).not.toMatch(/search_tsv|search_text/)
  for (const n of ['course_fees', 'course_intakes', 'english_requirements', 'course_scholarships', 'course_links', 'course_entry_requirements']) {
    const d = D.find((x) => x.name === n)
    expect(d.select, n).toContain('as x_consumer_visible')
    expect(d.visibleRule, n).toMatch(/x_consumer_visible/)
  }
  for (const n of ['course_fees', 'course_intakes', 'english_requirements', 'course_links', 'course_entry_requirements', 'provider_entry_matrices']) {
    expect(D.find((x) => x.name === n).select, n).toContain('as x_admission_state')
  }
})

test('the workflow is dispatched by hand, confirms the project ref, keeps data and credentials out of logs and git, and keeps the artifact 14 days', () => {
  expect(wf).toMatch(/^on:\n  workflow_dispatch:\n/m)
  expect(wf).not.toMatch(/^\s+(push|pull_request|schedule):/m)
  expect(wf).toContain('if [ "$PROJECT_REF" != "${{ vars.SUPABASE_PROJECT_REF }}" ]; then echo "Typed project ref does not match SUPABASE_PROJECT_REF"; exit 1; fi')
  expect(wf).toContain('PGPASSWORD: ${{ secrets.SUPABASE_DB_PASSWORD }}')
  expect(wf).toContain('echo "PGPORT=5432"')
  expect(wf).toContain('retention-days: 14')
  expect(wf).toContain('uses: actions/upload-artifact@v4')
  expect(wf).toContain('contents: read')
  expect(wf).not.toMatch(/contents: write|git (push|commit|add)|set -x|--verbose/)
  // nothing prints the password, the connection, or a CSV
  expect(wf).not.toMatch(/echo[^\n]*\$\{?(PGPASSWORD|PGHOST|PGUSER|cfg)\b/)
  expect(wf).not.toMatch(/(cat|head|tail|less|column)\s+[^\n]*\.csv/)
  expect(wf).toContain('run: node scripts/export/au-catalogue-export.mjs')
  expect(wf).toContain('GIT_SHA: ${{ github.sha }}')
  // the export log carries counts and md5s; an error message has its quoted values removed
  expect(redact(`ERROR:  invalid input syntax for type uuid: "abc-secret"\nDETAIL: x`)).toBe('ERROR:  invalid input syntax for type uuid: …')
  expect(driver).not.toMatch(/console\.log\([^)]*\b(rows|data)\[/)
})

test('pacing: cron minutes, quiet gaps and the "finish before the next busy minute" rule', () => {
  expect([...cronMinutes('*/10 * * * *')]).toEqual([0, 10, 20, 30, 40, 50])
  expect([...cronMinutes('3-59/10 * * * *')]).toEqual([3, 13, 23, 33, 43, 53])
  expect([...cronMinutes('37 * * * *')]).toEqual([37])
  expect([...cronMinutes('5,25 * * * *')]).toEqual([5, 25])
  expect([...rangeMinutes('35-42,47-48')]).toEqual([35, 36, 37, 38, 39, 40, 41, 42, 47, 48])
  expect([...tensMinutes('6-8')].slice(0, 6)).toEqual([6, 7, 8, 16, 17, 18])
  const busy = new Set([...cronMinutes('3-59/10 * * * *'), ...cronMinutes('5-59/10 * * * *'), ...cronMinutes('9-59/10 * * * *'), ...rangeMinutes('35-42,47-48')])
  const gaps = quietGaps(busy)
  expect(gaps.every((g) => g.length > 0 && !busy.has(g.start))).toBe(true)
  expect(gaps.reduce((a, g) => a + g.length, 0)).toBe(60 - busy.size)
  // 10:12:00 UTC is minute 12 in Melbourne too (whole-hour offset): quiet for 30 s; not for 90 s (minute 13 is busy)
  expect(intervalQuiet(new Date('2026-11-02T10:12:00Z'), 30, busy, 'Australia/Melbourne', '')).toBe(true)
  expect(intervalQuiet(new Date('2026-11-02T10:12:00Z'), 90, busy, 'Australia/Melbourne', '')).toBe(false)
  // the daily peak 06:50-07:15 AEDT (19:50-20:15 UTC on 1 Nov)
  expect(intervalQuiet(new Date('2026-11-01T19:51:00Z'), 10, new Set(), 'Australia/Melbourne', '06:50-07:15')).toBe(false)
})

test('CSV: null stays empty, the empty string stays "", quotes and new lines survive', () => {
  const csv = toCsv(['id', 'a', 'b'], [['1', null, ''], ['2', 'x, "y"\nz', '0']])
  expect(csv).toBe('id,a,b\n1,,""\n2,"x, ""y""\nz",0\n')
  const rows = parseCsv(csv)
  expect(rows).toEqual([{ id: '1', a: null, b: '' }, { id: '2', a: 'x, "y"\nz', b: '0' }])
  expect(rows.header).toEqual(['id', 'a', 'b'])
})

test('field states: only what the data supports; Layer 4 pending only from a real pending item; null is never "not applicable"', () => {
  expect(compare(null, '')).toBe('both_null')
  expect(compare('41000.00', '41000')).toBe('equal')
  expect(compare('a', null)).toBe('db_only')
  expect(RECON_FIELDS.map((f) => f[0])).toEqual(expect.arrayContaining(['item.title', 'item.tuition.amount', 'item.official_url', 'item.intakes (options)', 'item.english_requirements', 'item.scholarship_count']))
  const course = (id, extra = {}) => ({ id, stable_key: id, x_website_search_blocked: 'f', x_in_website_api_v2: 't', description: null, ...extra })
  const empty = { course_links: [], course_fees: [], course_intakes: [], english_requirements: [], course_entry_requirements: [], course_scholarships: [], course_campuses: [] }
  const data = { ...empty, courses: [course('c1'), course('c2'), course('c3'), course('c4', { x_website_search_blocked: 't' })],
    english_requirements: [{ course_id: 'c1', status: 'active', x_admission_state: 'admitted', x_consumer_visible: 't' }, { course_id: 'c4', status: 'active', x_admission_state: 'admitted', x_consumer_visible: 'f' }],
    course_entry_requirements: [{ course_id: 'c3', status: 'proposed', x_admission_state: 'held' }],
    layer4_course_review_items: [{ entity_id: 'c2', field_code: 'course_english', status: 'pending', decided_at: null }, { entity_id: 'c3', field_code: 'course_english', status: 'rejected', decided_at: '2026-11-01' }] }
  const { header, rows } = fieldStates(data)
  const st = (c, f) => rows.find((r) => r[0] === c && r[2] === f)[header.indexOf('state')]
  expect(st('c1', 'english')).toBe('available')
  expect(st('c2', 'english')).toBe('layer4_pending')
  expect(st('c3', 'english')).toBe('rejected')
  expect(st('c3', 'entry_requirements')).toBe('processing')
  expect(st('c4', 'english')).toBe('quality_held')
  expect(st('c1', 'description')).toBe('missing')
  expect(rows.some((r) => r[header.indexOf('state')] === 'not_applicable')).toBe(false)
  expect(rows.length).toBe(4 * STATE_FIELDS.length)
})

test('the fixture run covers both snapshot modes as a select-only role and checks the database is unchanged', () => {
  const run = fs.readFileSync('tests/fixtures/au-catalogue-export/run.sh', 'utf8')
  expect(run).toContain('create role au_export_reader')
  expect(run).toContain('grant select on all tables')
  expect(run).not.toMatch(/grant (insert|update|delete|all)/i)
  expect(run).toContain('for mode in single fallback; do')
  expect(run).toContain('FORCE_SINGLE_ABORT=1')
  expect(run).toContain('[ "$before" = "$after" ] || { echo "row counts changed"; exit 1; }')
  expect(run).toContain('row data printed in the log')
  expect(fs.readFileSync('tests/fixtures/au-catalogue-export/schema.mjs', 'utf8')).toContain("live-capture/baseline/schema.sql")
})

test('verification and the derived sheets stream: no dataset is held in memory (run 41377240304 ran out of heap)', () => {
  // the files are joined as bytes and read back record by record; the derived sheets merge-join courses and projection rows in id order
  expect(driver).not.toMatch(/parseCsv|readFileSync\([^)]*csv|const data = \{\}|data\[d\.name\]/)
  expect(driver).toContain('await eachRecord(file, (rec, hdr) => {')
  expect(driver).toContain("for await (const c of records(path.join(csvDir, 'courses.csv'))) {")
  expect(driver).toContain("while (doc && doc.course_id < c.id)")
  expect(driver).toContain("check('courses are in id order (the reconciliation merge-join needs it)', coursesSorted")
  expect(driver).toContain('manifest.memory = { max_rss_mb: Math.round(process.resourceUsage().maxRSS / 1024)')
  // a ceiling below the default, not a raise
  expect(wf).toContain('NODE_OPTIONS: --max-old-space-size=2048')
  const scale = fs.readFileSync('tests/fixtures/au-catalogue-export/scale.sh', 'utf8')
  expect(scale).toContain('NODE_OPTIONS=--max-old-space-size=${SCALE_HEAP_MB:-512}')
  expect(scale).toContain('${SCALE_RSS_MB:-2048}')
  expect(fs.readFileSync('tests/fixtures/au-catalogue-export/scale.sql', 'utf8')).toMatch(/26,912 courses, 179,621 fees, 101,422 scholarship links/)
})

test('the CSV reader gives the same records whatever the chunk boundaries (quotes, new lines, multi-byte characters)', () => {
  const text = 'id,a,b\n1,,""\n2,"x, ""y""\nz",0\n3,é漢,"q"\n'
  const want = [['id', 'a', 'b'], ['1', null, ''], ['2', 'x, "y"\nz', '0'], ['3', 'é漢', 'q']]
  const bytes = Buffer.from(text)
  for (let k = 1; k < bytes.length; k++) {
    const out = []; const p = new CsvParser((r) => out.push(r))
    p.push(bytes.subarray(0, k)); p.push(bytes.subarray(k)); p.end()
    expect(out, `split at ${k}`).toEqual(want)
  }
})

test('each dataset records its snapshot times, and per-dataset snapshots are checked to have stayed inside quiet minutes', () => {
  expect(driver).toContain("manifest.snapshots.push({ id: ++sid, scope: d.name, started_at: new Date(t0).toISOString(), quiet_room_s: room, budget_s: budget, ...snap })")
  expect(driver).toContain('snapshot_detail: st.snapshots.map((id) =>')
  expect(driver).toContain("check('per-dataset snapshots stayed inside quiet minutes', crossed.length === 0")
  // a page group commits before its budget, which leaves a statement time-out of quiet room after the last page starts
  expect(driver).toContain('const budget = Math.min(C.txnBudgetS, Math.max(5, room - C.statementTimeoutS))')
  expect(driver).toContain('do { await pageOnce(d) } while (!state[d.name].done && (Date.now() - t0) / 1000 < budget)')
})
