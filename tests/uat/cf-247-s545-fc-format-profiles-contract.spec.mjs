// Guards: CF-247 Firecrawl format profiles (Platform Admin 14 Nov 2026 19:19; screen v2.16.2, mock-up accepted 20:13): surcharge formats and onlyCleanContent never sent; rawHtml and markdown from one call kept under one evidence row; stored HTML still converted locally by lean-md-v2
// What a Firecrawl scrape asks for is set per profile on Toolsets and limits › Firecrawl › Format profiles (settings scrape_profiles,
// scrape_profile_lanes, scrape_profile_overrides). Worker v0.99.0 applies the profile inside fcClient (firecrawl.ts); migration 20261114201500
// seeds today's requests plus markdown, checks every save with the same rules, and records the kept formats on the page's evidence row.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { mockAdmin } from './support/admin-mock.mjs'

const DIR = 'supabase/functions/coverage-sweep'
const ix = fs.readFileSync(`${DIR}/index.ts`, 'utf8')
const fcSrc = fs.readFileSync(`${DIR}/firecrawl.ts`, 'utf8')
const mig = fs.readFileSync('supabase/migrations/20261114201500_cf247_firecrawl_format_profiles.sql', 'utf8')
const SURCHARGE = ['json', 'summary', 'question', 'highlights']

async function load(file, tag) {
  const out = path.join(os.tmpdir(), `${tag}-s545-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', [`${DIR}/${file}`, '--bundle', '--format=esm', '--platform=node', `--outfile=${out}`, '--log-level=error'])
  return import(out)
}
function mockFetch(replies) {
  const calls = []
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), body: JSON.parse(init.body) })
    const r = replies.shift()
    return new Response(JSON.stringify(r.json), { status: r.status ?? 200, headers: { 'content-type': 'application/json' } })
  }
  return calls
}
const BIG = '<html><title>Course</title><body><main>' + 'Bachelor of Things. '.repeat(40) + '</main><aside>IELTS 6.5 overall</aside></body></html>'
const both = (extra = {}) => ({ json: { success: true, data: { rawHtml: BIG, markdown: '# Bachelor of Things\n\nIELTS 6.5 overall', metadata: { statusCode: 200, scrapeId: 's1', creditsUsed: 1, cacheState: 'miss', ...extra } } } })
// the seeded set, read from the migration itself
const seed = (key) => JSON.parse(mig.match(new RegExp(`\\('firecrawl', '${key}'[\\s\\S]*?\\$j\\$([\\s\\S]*?)\\$j\\$`))[1])
const SEED = { version: 1, profiles: seed('scrape_profiles'), lanes: seed('scrape_profile_lanes'), overrides: [] }

test('surcharge formats and onlyCleanContent are refused by the worker check and never sent by the client', async () => {
  const { checkProfile, checkProfiles, applyProfile, FC_FORMATS } = await load('firecrawl.ts', 'fc')
  expect(FC_FORMATS).toEqual(['markdown', 'rawHtml', 'html', 'links', 'screenshot'])
  for (const f of SURCHARGE) expect(checkProfile({ formats: ['markdown', f] }, 'p').join(' ')).toContain(`format ${f} is never sent`)
  expect(checkProfile({ formats: ['markdown'], onlyCleanContent: true }, 'p').join(' ')).toContain('onlyCleanContent is never sent')
  expect(checkProfile({ formats: ['markdown'], onlyCleanContent: false }, 'p')).not.toEqual([])
  expect(checkProfile({ formats: ['screenshot'] }, 'p').join(' ')).toContain('a screenshot alone is not a page read')
  expect(checkProfile({ formats: ['markdown'], crawl: { maxDepth: 2 } }, 'p').join(' ')).toContain('maxDiscoveryDepth, not maxDepth')
  expect(checkProfile({ formats: ['markdown'], waitFor: 70000 }, 'p').join(' ')).toContain('0 to 60,000 ms')
  expect(checkProfile({ formats: ['markdown'], actions: [{ type: 'executeJavascript' }] }, 'p').join(' ')).toContain('not allowed')
  expect(checkProfiles({ ...SEED, lanes: { course_read: 'nope' } }).join(' ')).toContain('profile nope does not exist')
  // whatever reaches the client, a surcharge format or onlyCleanContent is taken out of the request
  const sent = applyProfile({ url: 'u', formats: ['rawHtml', 'json', { type: 'json', prompt: 'x' }, 'summary'], onlyCleanContent: true }, null, false)
  expect(sent).toEqual({ url: 'u', formats: ['rawHtml'] })
  const viaProfile = applyProfile({ url: 'u', formats: ['rawHtml'] }, { formats: ['markdown', 'question', 'highlights'] }, false)
  expect(viaProfile.formats).toEqual(['markdown'])
})

test('the server check refuses the same, every save goes through it, and the migration proves it on apply', () => {
  expect(mig).toContain("v_formats text[] := array['markdown', 'rawHtml', 'html', 'links', 'screenshot'];")
  expect(mig).toContain("onlyCleanContent is never sent (an AI pass over the page)")
  expect(mig).toContain("v_errs := security.fc_scrape_profiles_check_v1(p_profiles, coalesce(p_lanes, '{}'::jsonb), coalesce(p_overrides, '[]'::jsonb));")
  expect(mig).toContain("raise exception 'post-check: surcharge formats and onlyCleanContent are refused'")
  for (const f of SURCHARGE) expect(mig).toContain(`"${f}"`)
  // Platform Admin saves with a reason; the generic editor never writes a set of values as text
  expect(mig).toMatch(/admin_fc_profiles_set_v1[\s\S]{0,600}coalesce\(v_rank, 0\) < 6[\s\S]{0,200}length\(v_reason\) < 4/)
  expect(mig).toContain("if v_set.kind = 'json' or (v_set.toolset_key = 'firecrawl' and v_set.key = 'scrape_profiles_version') then")
  // md5-guarded edits of the live text, nothing dropped or deleted, Replaces/Retires lines
  expect(mig).toContain("select pg_temp.edit_once('public.svc_worker_settings_v1()', 'e4e3292858516d1d29c877921be29b76',")
  expect(mig).toContain("select pg_temp.edit_once('public.admin_toolsets_write(text,jsonb)', '531d48c1adce92dd78d44a4650d19061',")
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('the seeds keep today\'s requests, add markdown to page reads, and leave AER v1 lanes and capture alone', async () => {
  const { checkProfiles, resolveProfile, LANE_OWN } = await load('firecrawl.ts', 'fc')
  expect(checkProfiles(SEED)).toEqual([])
  expect(SEED.profiles.page_html).toMatchObject({ formats: ['rawHtml', 'markdown'], onlyMainContent: false, maxAgeMs: 172800000 })
  expect(SEED.profiles.aer_hub_page.onlyMainContent).toBe(false)
  for (const lane of ['entry_render', 'entry_fallback', 'entry_pdf_render', 'adapter_builder', 'probe']) expect(SEED.lanes[lane], lane).toBe(LANE_OWN)
  expect(Object.values(SEED.lanes)).not.toContain('aer_hub_page')  // AER v1 frozen (Decision 276): seeded, not mapped
  // every lane that scrapes is in the map (a lane not in it sends its own request)
  const lanes = new Set([...ix.matchAll(/fcx\.scrape\([^;]*?use_case: "([a-z_]+)"/g)].map((m) => m[1]))
  expect(lanes.size).toBeGreaterThanOrEqual(20)
  for (const l of lanes) expect(Object.keys(SEED.lanes), l).toContain(l)
  expect(SEED.lanes.read_page).toBe('page_html')  // fc_run Run now reads
  expect(resolveProfile(SEED, 'not_a_lane', null)).toBeNull()
  // no seed asks for a screenshot (off by default), sets a time-out or a wait (each lane keeps its own)
  for (const [k, p] of Object.entries(SEED.profiles)) { expect(p.formats, k).not.toContain('screenshot'); expect(p.waitFor ?? null, k).toBeNull(); expect(p.timeout ?? null, k).toBeNull() }
})

test('one 1-credit call returns rawHtml and markdown; on demand is fresh; lane_own and an unreadable set send the lane\'s own request', async () => {
  const { fcClient } = await load('firecrawl.ts', 'fc')
  const calls = mockFetch([both(), both(), both(), both()])
  const fcx = fcClient({ headers: {}, log: async () => null, profiles: SEED, fresh: (ctx) => ctx.item_id === 'od' })
  const sc = await fcx.scrape({ url: 'https://u.example/c', formats: ['rawHtml'], onlyMainContent: false, timeout: 45000 }, { use_case: 'course_read', provider_id: 'p1' }, { timeoutMs: 60000 })
  expect(calls.length).toBe(1)
  expect(calls[0].body).toMatchObject({ formats: ['rawHtml', 'markdown'], onlyMainContent: false, maxAge: 172800000, timeout: 45000 })
  expect(sc.accepted).toBe(true)
  expect(sc.html).toContain('Bachelor of Things')
  expect(sc.markdown).toContain('IELTS 6.5 overall')
  expect(sc.profile).toEqual({ key: 'page_html', version: 1, formats: ['rawHtml', 'markdown'], max_age_ms: 172800000, fresh: false })
  expect(sc.rec.credits_used).toBe(1)
  await fcx.scrape({ url: 'https://u.example/c' , formats: ['rawHtml'] }, { use_case: 'course_read', item_id: 'od' }, { timeoutMs: 60000 })
  expect(calls[1].body.maxAge).toBe(0)
  const aer = { url: 'https://u.example/e', formats: ['rawHtml'], onlyMainContent: false, waitFor: 4000 }
  await fcx.scrape({ ...aer }, { use_case: 'entry_render', item_id: 'od' }, { timeoutMs: 60000 })
  expect(calls[2].body).toEqual(aer)  // AER v1 lane: unchanged, not even made fresh
  // the worker uses no set that fails the check (index.ts), and the client without profiles sends the lane's request
  expect(ix).toContain('return checkProfiles(all).length ? null : all;')
  const plain = fcClient({ headers: {}, log: async () => null })
  await plain.scrape({ url: 'https://u.example/c', formats: ['rawHtml'] }, { use_case: 'course_read' }, { timeoutMs: 60000 })
  expect(calls[3].body).toEqual({ url: 'https://u.example/c', formats: ['rawHtml'] })
})

test('the markdown and the stored HTML of one read are kept under one evidence row', () => {
  // keepFormats: markdown beside the stored page (same name, .md.gz), then one attach call naming that page's storage path
  expect(ix).toContain('const base = storagePath.replace(/\\.html\\.gz$|\\.gz$/, ""), files: Record<string, string> = { stored: storagePath };')
  expect(ix).toContain('const p = `${base}.md.gz`;')
  expect(ix).toMatch(/rpc\("svc_evidence_formats_attach_v1", \{ p_rows: \[\{ storage_path: storagePath, files, firecrawl: \{\s*profile: sc\.profile\.key, profile_version: sc\.profile\.version, formats: sc\.profile\.formats/)
  for (const k of ['cache_state', 'page_status', 'credits_used', 'scrape_id', 'max_age_ms']) expect(ix).toContain(`${k}:`)
  // after the evidence row exists: course reads, Run now reads, provider descriptions
  expect(ix).toContain('if (path && via === "firecrawl") await keepFormats(path, fcRead);')
  expect(ix).toContain('if (path && readStatus) await keepFormats(path, fcSc);')
  expect(ix).toMatch(/svc_provider_description_record[\s\S]{0,600}await keepFormats\(String\(o\.fetch\.storage_path\), descFc\.get\(String\(o\.item_id\)\)\)/)
  // the database records only files stored beside that page, on its newest evidence row
  expect(mig).toContain("and (k = 'screenshot_skipped' or (val #>> '{}') = x->>'storage_path' or starts_with(val #>> '{}', v_base || '.'));")
  expect(mig).toContain("select id into v_id from pipeline.evidence_artifacts where storage_path = x->>'storage_path' order by created_at desc limit 1;")
  // a screenshot only when the profile asked, kept as received, size from a setting
  expect(ix).toContain('const SHOT_MAX_BYTES = wsNum("screenshot_max_mb", 15) * 1048576;')
  expect(fcSrc).toContain('screenshot: accepted && typeof d?.data?.screenshot === "string" ? String(d.data.screenshot) : null,')
})

test('stored HTML evidence is still converted locally by lean-md-v2; no reader reads the kept markdown', async () => {
  const { leanText, LEAN_CONVERTER } = await load('lean-input.ts', 'lean')
  expect(LEAN_CONVERTER).toBe('lean-md-v2')
  const t = leanText(BIG)
  expect(t.converter).toBe('lean-md-v2')
  expect(t.text).toContain('IELTS 6.5 overall')  // content outside <main> kept, as today
  expect(ix).not.toMatch(/download\([^)]*\.md\.gz/)
  expect(fs.readFileSync(`${DIR}/lean-input.ts`, 'utf8')).not.toMatch(/markdown|\.md\.gz/)
})

test('guardrails: no route switch, ceiling, Observe/Stop mode, model route or AER shadow setting is touched', () => {
  const top = mig.replace(/\$function\$[\s\S]*?\$function\$/g, '').replace(/\$n\$[\s\S]*?\$n\$/g, '')
  expect(top).not.toMatch(/^\s*update\b/im)
  const code = mig.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n').toLowerCase()
  for (const s of ['aer.v2_shadow_on', 'gpt-4.1-mini', 'held_kind', 'enforcement', 'ceiling', 'max_usd', 'route_on', 'paused']) expect(code, s).not.toContain(s)
  expect(ix).toMatch(/const WORKER = "coverage-sweep-worker-v0\.99\.0";/)
})

// ---- the screen: Models & services › Toolsets and limits › Firecrawl › Format profiles (v2.16.2) ----
const read = (over = {}) => ({ profiles: SEED.profiles, lanes: SEED.lanes, overrides: [], version: 1, screenshot_max_mb: 15, saved_at: '2026-11-14T09:15:00Z', reason: 'first version',
  formats: ['markdown', 'rawHtml', 'html', 'links', 'screenshot'], never_sent: ['json', 'summary', 'question', 'highlights', 'onlyCleanContent'], can_edit: true, problems: [], history: [], ...over })
async function openProfiles(page, data) {
  const sent = []
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_fc_profiles_*', async (route) => {
    const name = new URL(route.request().url()).pathname.split('/').pop(), body = route.request().postDataJSON() || {}
    sent.push({ name, body })
    const reply = name === 'admin_fc_profiles_set_v1' ? { ok: true, version: 2 } : data
    return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(reply) })
  })
  await page.goto('/#models-services?tab=limits')
  const card = page.locator('[data-card="services.toolset.firecrawl.formats"]')
  await card.locator('.cf-card-toggle').first().click()
  await expect(card.locator('[data-fc-profiles-body]')).toBeVisible()
  return { card, sent }
}

test.describe('mocked browser', () => {
  test('the card lists the profiles, refuses surcharge formats by name, keeps AER v1 lanes on their own request and saves with a reason and the version', async ({ page }) => {
    await mockAdmin(page)
    const { card, sent } = await openProfiles(page, read())
    await expect(card.locator('[data-fcp-never]')).toContainText('Never sent')
    for (const f of SURCHARGE) await expect(card.locator('[data-fcp-never]')).toContainText(f)
    await expect(card.locator('[data-fcp-never]')).toContainText('onlyCleanContent')
    await expect(card.locator('[data-fcp-profile]')).toHaveCount(Object.keys(SEED.profiles).length)
    // only the five allowed formats can be ticked
    await expect(card.locator('[data-fcp-editor] [data-fcp-format]')).toHaveCount(5)
    for (const f of SURCHARGE) await expect(card.locator(`[data-fcp-format="${f}"]`)).toHaveCount(0)
    // the preview: a scheduled read uses the 48-hour copy, Run now asks for a fresh page
    const pre = card.locator('[data-fcp-preview] pre')
    await expect(pre).toContainText('"maxAge": 172800000')
    await card.getByRole('button', { name: 'Run now' }).click()
    await expect(pre).toContainText('"maxAge": 0')
    // AER v1 lanes are not offered a profile
    await expect(card.locator('[data-fcp-lane="entry_render"] select')).toHaveCount(0)
    await expect(card.locator('[data-fcp-lane="entry_render"]')).toContainText('The lane’s own request')
    await expect(card.locator('[data-fcp-lane="course_read"]')).toContainText('rawHtml + markdown')
    // a change needs a reason; a profile with no page format cannot be saved
    const save = card.getByRole('button', { name: 'Save profiles' })
    await expect(save).toBeDisabled()
    await card.locator('[data-fcp-format="rawHtml"]').uncheck()
    await card.locator('[data-fcp-format="markdown"]').uncheck()
    await expect(card.locator('[data-fcp-problems]')).toContainText('choose at least one format')
    await card.locator('[data-fcp-format="markdown"]').check()
    await card.locator('[data-fcp-format="rawHtml"]').check()
    await card.locator('[data-fcp-lane="course_list_read"] select').selectOption('text_full')
    await card.getByPlaceholder('Why this change').fill('List pages read as text')
    await expect(save).toBeEnabled()
    await save.click()
    await expect(card.locator('[data-fcp-msg]')).toContainText('Saved as version 2')
    const call = sent.find((c) => c.name === 'admin_fc_profiles_set_v1').body
    expect(call.p_reason).toBe('List pages read as text')
    expect(call.p_expected_version).toBe(1)
    expect(call.p_lanes.course_list_read).toBe('text_full')
    expect(call.p_lanes.entry_render).toBe('lane_own')
    expect(call.p_profiles.page_html.formats).toEqual(['markdown', 'rawHtml'])
  })

  test('read only below Platform Admin (Pipeline Operator); a saved set with a problem says the worker is not using it', async ({ page }) => {
    await mockAdmin(page, { rank: 4, role: 'pipeline_operator' })
    const { card } = await openProfiles(page, read({ can_edit: false, problems: ['page_html: format json is never sent'] }))
    await expect(card.locator('[data-fcp-server-problem]')).toContainText('every lane sends its own request')
    await expect(card.getByRole('button', { name: 'Save profiles' })).toHaveCount(0)
    await expect(card.locator('[data-fcp-format="markdown"]')).toBeDisabled()
    await expect(card).toContainText('Only a Platform Admin can change it')
  })
})
