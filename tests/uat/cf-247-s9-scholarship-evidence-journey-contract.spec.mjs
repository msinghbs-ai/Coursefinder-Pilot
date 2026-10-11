// CF-247 v2.15.243 (S9, Platform Admin 11 Oct 2026): scholarships read through the scraper only; dates, course links with proof,
// the Evidence & extraction journey; Study Australia and national registers retired; legacy scholarship screens removed.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const reader = fs.readFileSync('supabase/functions/coverage-sweep/scholarship.ts', 'utf8')
const m84 = fs.readFileSync('supabase/migrations/20261011008400_cf247_scholarship_evidence_journey.sql', 'utf8')
const m85 = fs.readFileSync('supabase/migrations/20261011008500_cf247_scholarship_course_exclusions.sql', 'utf8')

test('scraper only: no direct read, no fallback, robots.txt not consulted for scholarship pages; a page waits for the scraper', () => {
  expect(worker).toContain('const WORKER = "coverage-sweep-worker-v0.18.2"')
  expect(worker).toContain('const SCH_VERSION = "scholarship-sweep-v0.7.2"')
  const fn = worker.slice(worker.indexOf('const readSch = async'), worker.indexOf('const readSch = async') + 1600)
  expect(fn).toContain('if (!(await useFc("sch_scrape", providerId, url, true))) return none("waiting_scraper");')
  expect(fn).not.toContain('readDirect(')
  expect(fn).not.toContain('robotsAllows(')
  expect(worker).toContain('const pg = await readSch(it.url, it.provider_id);') // scholarship pages and candidates
  expect(worker).toContain('const pg = await readSch(r.url, r.provider_id);') // listing pages
  expect(worker).toContain('if (await useFc("sch_map", p.provider_id, site.origin, true)) {') // site maps through the scraper
  expect(worker).not.toContain('svc_scholarship_search_next') // register search phase retired
  expect(m84).toContain("when p_read_status='waiting_scraper' then now()+interval '1 hour'")
})

test('reader: open, close (rounds) and study start with their words; named and excluded courses; day/month order by country', () => {
  for (const s of ['export function scholarshipDates(', 'export function studyStart(', 'export function namedCourses(', 'const EXCLUDE_CUE =',
    'dates: scholarshipDates(body, new Date(), order),', 'study_start: studyStart(body),', 'named_courses: namedCourses(html, body),', 'levels_text:', 'fields_text:',
    `const order: "dmy" | "mdy" | "none" = /^(USD)$/i.test(currency) ? "mdy" : /^(CAD)$/i.test(currency) ? "none" : "dmy";`]) expect(reader).toContain(s)
})

test('course links from evidence with proof; no link-to-all rule; exclusions honoured; unlinked can be published', () => {
  expect(m84).toContain('alter table scholarship.course_mappings add column if not exists proof jsonb;')
  expect(m84).not.toContain("'rule','all courses open to international students")
  expect(m84).toContain("v_changes:=v_changes||'no_course_named'::text;")
  expect(m84).toContain("-- 11 Oct 2026 (Platform Admin): a scholarship not linked to a course is valid and can be published")
  expect(m84).not.toContain("then 'no linked course' end")
  expect(m84).toContain("perform search.refresh_course_enrichment_scoped_v1(array(select distinct unnest(v_add||v_del)),true);")
  expect(m85).toContain("and not (c.id = any(v_excl))")
  expect(m85).toContain('"security.scholarship_sweep_apply_v1(uuid)": "d64a9fafd63a24c68ac05aa95afbe555"')
})

test('Study Australia and national registers retired; legacy jobs unscheduled; nothing dropped or deleted', () => {
  expect(m84).toContain("select cron.unschedule(j.jobname) from cron.job j where j.jobname in ('coursefinder-scholarship-etl-scheduler', 'coursefinder-scholarship-maintenance',")
  expect(m84).toContain("'register_record_retired'")
  expect(m84).toContain("'reference_code',null::text")
  expect(m84).toContain("update pipeline.scholarship_layer_settings set value = 60000")
  for (const sql of [m84, m85]) expect(sql).not.toMatch(/^(drop|delete|truncate)\b/im)
  expect(fs.existsSync('supabase/functions/scholarships-au-etl')).toBe(false)
  expect(fs.existsSync('supabase/functions/scholarship-ai-control')).toBe(false)
  expect(fs.readFileSync('supabase/functions/layer1-operations-control/index.ts', 'utf8')).toContain('function registerFeed(_code:string):string|null{return null;}')
  for (const f of ['src/SourceComparison.jsx', 'src/ScholarshipAiControl.jsx', 'src/layer4-scope-rules-entry.jsx']) expect(fs.existsSync(f)).toBe(false)
  expect(fs.readFileSync('src/mature-main.jsx', 'utf8')).not.toContain('data-sr-compare')
  expect(fs.readFileSync('src/ScholarshipCoverage.jsx', 'utf8')).not.toContain('study_australia')
  expect(fs.readFileSync('src/nav-map.js', 'utf8')).not.toMatch(/layer3:[^\n]*\n(?:[^\n]*\n){2}\s*\{ key: 'scholarships'/)
})

test('record shows the dates and the Evidence & extraction journey (mocked)', async ({ page }) => {
  const ui = fs.readFileSync('src/ScholarshipRecord.jsx', 'utf8')
  for (const s of ["{k:'open',label:'Applications open'", "{k:'close',label:'Applications close'", "{k:'start',label:'Study start'", '<EvidenceJourney d={d}/>',
    "step('read','2. Read through the scraper'", "step('saved','3. Saved copy'", "step('facts','5. What was read from the page'", "step('applied','6. What it changed'",
    "data-sr-proof", "Excluded by the page:"]) expect(ui).toContain(s)
})

test('course titles: bullets end a title; long titles match by containment (migration 8800)', () => {
  const m88 = fs.readFileSync('supabase/migrations/20261011008800_cf247_scholarship_course_title_match.sql', 'utf8')
  expect(m88).toContain('create or replace function security.scholarship_course_title_match_v1(p_named text, p_canonical text, p_display text)')
  expect(m88).toContain("security.scholarship_course_title_match_v1(x->>'title', c.canonical_title, c.display_title)")
  expect(m88).toContain('"security.scholarship_sweep_apply_v1(uuid)": "a5431127dd4c5c85ac33b5e92dcbcb02"')
  expect(m88).not.toMatch(/^(drop|delete|truncate)\b/im)
  expect(reader).toContain('[.;:,\\n|•⦁·▪●‚]')
})
