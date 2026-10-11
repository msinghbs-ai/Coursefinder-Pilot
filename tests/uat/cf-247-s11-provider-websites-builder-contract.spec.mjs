// CF-247 v2.15.245 (S11): Platform Admin bugs 11/10-2. Consumer searches build the blocked list once (Fix 7); the Adapters list
// styles no longer start with "ad-" (ad blockers hid them, Fix 1); verified websites go on the provider record and every provider
// without one is searched (Fix 3, Features 2-3); central pages found by Firecrawl (Feature 4); the builder is numbered 1.x/2.x/3.x/4
// with readable text, a course list and two new tasks (Fixes 2, 5, 6, Feature 1); a cut-off proposal is asked again once (Fix 4).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = p => fs.readFileSync(p, 'utf8')
const noDrops = sql => { expect(sql).not.toMatch(/^(drop|delete|truncate)\b/im); expect(sql).not.toMatch(/^alter table .* drop /im) }

test('Fix 7: consumer course searches look up the blocked list by hash; nothing else changes', () => {
  const sql = read('supabase/migrations/20261011009300_cf247_consumer_search_blocked_once.sql')
  expect(sql.replace(/--[^\n]*/g, '')).not.toContain('not exists (select 1 from security.layer4_search_blocked_courses')
  expect((sql.match(/not in \(select \w+\.course_id from security\.layer4_search_blocked_courses \w+ where \w+\.course_id is not null\)/g) || []).length).toBe(22)
  for (const md5 of ['973c0ef77272b00b33ff4921c7c88c41', 'f04c4f546b2e7d2605ba957e2c05214e', 'eda3f7c0ad78d5014a24e24501969134']) expect(sql).toContain(md5)
  noDrops(sql)
})

test('Fix 1: no style name in the app starts with "ad-" (ad blockers hide them)', () => {
  for (const f of ['src/AdaptersWorkspace.jsx', 'src/mature.css', 'src/ui-standard.css']) expect(read(f)).not.toMatch(/(^|[^\w-])ad-[a-z]/m)
  expect(read('src/AdaptersWorkspace.jsx')).toContain('className="adp-list"')
})

test('Fix 3 and Features 2-4: websites adopted, every provider searched, central pages found, two task types', () => {
  const sql = read('supabase/migrations/20261011009400_cf247_provider_websites_central_pages_tasks.sql')
  expect(sql).toContain('create or replace function security.provider_website_adopt_v1')
  expect(sql).toContain("l.field = 'website'") // never over a website entered by hand
  expect(sql).toContain('create table if not exists pipeline.provider_central_search')
  expect(sql).toContain("('provider_fill', 'Fill in a provider from its website'")
  expect(sql).toContain("('course_page_find', 'Find course pages with Firecrawl'")
  expect(sql).toContain("select cron.schedule('central-find'")
  expect(sql).toContain("('central-find', 'Layer 2 reading'") // standing rule G1: labelled in Task manager
  expect(sql).toContain('create or replace trigger provider_site_followups')
  expect(sql).toContain("where status = 'no_website' and coalesce(site_evidence->>'note', '') ilike '%budget%'")
  noDrops(sql)
  const w = read('supabase/functions/coverage-sweep/index.ts')
  expect(w).toContain('if (cc !== "AU" || code.length < 5) { out.push(await findCanadianSite(p, cc)); return }')
  expect(w).toContain('useFc("search", p.provider_id, p.name, true)')
  expect(w).toContain('if (mode === "central_find")')
  const c = read('supabase/functions/coverage-sweep/central.ts')
  expect(c).toContain('export function centralCandidates')
  const x = read('supabase/functions/coverage-sweep/extract.ts')
  expect(x).toContain('guelphhumber.ca is not Humber College')
  const f = read('supabase/migrations/20261011009500_cf247_site_rule_humber_task_scope.sql')
  expect(f).toContain("'scope', v_pid::text);")
  expect(read('supabase/migrations/20261011009600_cf247_central_find_record_fix.sql')).toContain("then s.found else p_found end")
})

test('Fix 4: a cut-off proposal is asked again once with a larger limit, and every attempt is recorded', () => {
  const w = read('supabase/functions/coverage-sweep/index.ts')
  expect(w).toContain('for (const maxTokens of [4000, 8000])')
  expect(w).toContain('p_data: { error: err || "no answer", attempts, worker: WORKER }')
  expect(read('src/AdapterBuilderTab.jsx')).toContain('data-proposal-attempts')
})

test('Builder: numbered 1.1 to 3.4 and 4, course list, Fill in from website, capture status on its own', () => {
  const b = read('src/AdapterBuilderTab.jsx')
  for (const n of ['"1.1"', '"1.2"', '"1.3"', '"2.1"', '"2.2"', '"3.1"', '"3.2"', '"3.3"', '"3.4"']) expect(b).toContain(`n=${n}`)
  expect(b).toContain('data-builder-step="4"')
  expect(b).toContain('kind="provider_fill"')
  expect(b).toContain('kind="course_page_find"')
  expect(b).toContain('data-course-list')
  expect(b).toContain('data-capture-status')
  expect(b).not.toContain('captured (${dr.status})')
  expect(read('src/mature.css')).toContain('.ab-builder .ab-text{font-size:var(--cf-fs-lg)')
  expect(read('src/ScholarshipActions.jsx')).toContain('export function ProviderFillAction')
})

test('v0.19.1: a home page behind a gatekeeper is checked through the scraper when a website is verified', () => {
  const w = read('supabase/functions/coverage-sweep/index.ts')
  expect(w).toContain('const viaScraper = async (providerId: string, url: string, cc: string)')
  expect(w).toContain('if (!html || [401, 403, 429, 503].includes(h.status)) { const sc = await viaScraper(p.provider_id, u.origin + "/", cc);')
  expect(w).toContain('const WORKER = "coverage-sweep-worker-v0.19.2"')
})
