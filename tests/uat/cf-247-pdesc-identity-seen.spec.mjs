// Guards: Platform Admin order 10 Nov 2026 12:07 (Task B, observability only): when the provider-description identity proof FAILS, the worker records what the page showed it (checks.identity.seen: title, h1, og:site_name, html_chars, text_chars, has_script_shell) so a provider_name_not_proved hold can be diagnosed from the database; no page passes or fails differently (the proof, the registry proof and the sub-unit rule are the earlier text).
import fs from 'node:fs'
import { test, expect } from '@playwright/test'
import { descriptionIdentitySeen, descriptionSourceIdentity, descriptionPageText, IDENTITY_SEEN_TEXT_MAX, IDENTITY_SEEN_H1_MAX, IDENTITY_SHELL_TEXT_MAX } from '../../supabase/functions/coverage-sweep/description.ts'

const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const DS = fs.readFileSync('supabase/functions/coverage-sweep/description.ts', 'utf8')

// a page drawn in the browser: the raw HTML has a root element and scripts, no title and no heading (the shape of a JavaScript shell)
const SHELL = '<!doctype html><html><head><meta charset="utf-8"><script src="/static/app.js"></script></head><body><div id="root"></div><script>window.__DATA__={"page":"about"}</script></body></html>'
const prose = (n) => '<p>' + 'Study with a university that teaches science and the arts. '.repeat(n) + '</p>'

test('a JavaScript shell is seen as a shell: no title, no heading, almost no visible text, script tags', () => {
  const s = descriptionIdentitySeen(SHELL)
  expect(s).toEqual({ title: '', h1: [], og_site_name: '', html_chars: SHELL.length, text_chars: 0, has_script_shell: true })
})

test('a title with extra words, the headings and the site name are kept as the proof reads them (entities decoded, white space collapsed)', () => {
  const html = '<html><head><title> About Swinburne &#x2013; Swinburne University of Technology |  Melbourne &amp; Sarawak </title><meta property="og:site_name" content="Swinburne &amp; Co"><meta name="og:title" content="not this"></head>'
    + '<body><h1>About   Swinburne</h1><h1 class="x"><span>Our</span> story</h1>' + prose(10) + '</body></html>'
  const s = descriptionIdentitySeen(html)
  expect(s.title).toBe('About Swinburne – Swinburne University of Technology | Melbourne & Sarawak')
  expect(s.h1).toEqual(['About Swinburne', 'Our story'])
  expect(s.og_site_name).toBe('Swinburne & Co')
  expect(s.html_chars).toBe(html.length)
  expect(s.text_chars).toBeGreaterThan(400)
  expect(s.has_script_shell).toBe(false)
})

test('the site name is read from either quote style and either attribute order; a name tag is not the site name', () => {
  expect(descriptionIdentitySeen("<meta content='Collarts' property='og:site_name'>").og_site_name).toBe('Collarts')
  expect(descriptionIdentitySeen('<meta content="Ara Institute of Canterbury" name="og:site_name">').og_site_name).toBe('Ara Institute of Canterbury')
  expect(descriptionIdentitySeen('<meta name="application-name" content="Whitecliffe">').og_site_name).toBe('')
})

test('every excerpt is capped, at most three headings are kept, and an empty heading is skipped', () => {
  expect(IDENTITY_SEEN_TEXT_MAX).toBe(160); expect(IDENTITY_SEEN_H1_MAX).toBe(3)
  const long = 'A'.repeat(500)
  const s = descriptionIdentitySeen(`<title>${long}</title><meta property="og:site_name" content="${long}"><h1></h1><h1>${long}</h1><h1>two</h1><h1>three</h1><h1>four</h1>`)
  expect(s.title).toHaveLength(160); expect(s.og_site_name).toHaveLength(160)
  expect(s.h1).toHaveLength(3); expect(s.h1[0]).toHaveLength(160); expect(s.h1.slice(1)).toEqual(['two', 'three'])
})

test('the shell label: scripts and fewer than the threshold of visible characters; a page with real text or no scripts is not a shell', () => {
  expect(IDENTITY_SHELL_TEXT_MAX).toBe(200)
  const body = (n) => 'x'.repeat(n)
  expect(descriptionIdentitySeen(`<script>1</script><body>${body(199)}</body>`).text_chars).toBe(199)
  expect(descriptionIdentitySeen(`<script>1</script><body>${body(199)}</body>`).has_script_shell).toBe(true)
  expect(descriptionIdentitySeen(`<script>1</script><body>${body(200)}</body>`).has_script_shell).toBe(false)
  expect(descriptionIdentitySeen(`<body>${body(20)}</body>`).has_script_shell).toBe(false)  // short but no script: not drawn in the browser
  expect(descriptionIdentitySeen(`<script src="a.js"></script>${prose(20)}`).has_script_shell).toBe(false)
  // script text is not visible text
  expect(descriptionIdentitySeen('<script>' + 'y'.repeat(5000) + '</script><body>hello</body>').text_chars).toBe(5)
})

test('the visible text is the whole page, not the model\'s capped page text', () => {
  const html = `<html><body><main>${prose(2000)}</main></body></html>`
  const seen = descriptionIdentitySeen(html)
  expect(descriptionPageText(html, 16000).length).toBeLessThanOrEqual(16000)
  expect(seen.text_chars).toBeGreaterThan(16000)
})

test('it never throws on empty or broken input', () => {
  for (const x of ['', null, undefined, '<title>', '<h1>unclosed', '<meta', '<<<>>>', '\u0000']) expect(() => descriptionIdentitySeen(x)).not.toThrow()
  expect(descriptionIdentitySeen('')).toEqual({ title: '', h1: [], og_site_name: '', html_chars: 0, text_chars: 0, has_script_shell: false })
})

test('it only observes: the pages the proof passes and fails are the same as before (the proof is not given the seen record and not edited)', () => {
  const names = ['Riverstone University']
  const pass = '<title>About | Riverstone University</title><h1>About our university</h1><main>Riverstone University teaches health, science and law.</main>'
  const noName = '<title>Welcome</title><h1>Study with us</h1><main>We teach health, science and law.</main>'
  const call = (h) => descriptionSourceIdentity(h, descriptionPageText(h, 16000), names)
  const before = [call(pass), call(noName), call(SHELL)]
  descriptionIdentitySeen(pass); descriptionIdentitySeen(noName); descriptionIdentitySeen(SHELL)
  expect(before).toEqual([call(pass), call(noName), call(SHELL)])
  expect(call(pass).ok).toBe(true)
  expect(call(noName)).toEqual({ ok: false, rule: 'provider_name_not_proved' })
  expect(call(SHELL)).toEqual({ ok: false, rule: 'provider_name_not_proved' })
  // the result of the proof carries no seen key: the worker adds it on failure only
  expect(Object.keys(call(noName))).toEqual(['ok', 'rule'])
  // the identity functions are the earlier text: none of them mentions the new record
  for (const fn of ['function strictSourceIdentity', 'function registryEvidenceIdentity', 'export function descriptionSourceIdentity']) {
    const a = DS.indexOf(fn); expect(a, fn).toBeGreaterThan(0)
    expect(DS.slice(a, a + 3500).split('\n').slice(0, 60).join('\n')).not.toContain('descriptionIdentitySeen')
  }
})

test('worker v0.62.0 stores seen when the proof fails and only then, and holds the read exactly as before', () => {
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v0.62.0";')
  expect(IX).toMatch(/\/\/ was v0\.61\.0 \/\/ v0\.61\.0 \(10 Nov 2026, CF-247 F-PDESC delivery/)
  expect(IX).toMatch(/import \{[^}]*\bdescriptionIdentitySeen\b[^}]*\} from "\.\/description\.ts";/)
  const id = IX.indexOf('const identity = descriptionSourceIdentity(html, page,')
  expect(id).toBeGreaterThan(0)
  const win = IX.slice(id, id + 1600)
  expect(win).toContain('rec.identity_check = { ...identity, reader_behavior_version: "provider-description-source-guard-v4" };\n          if (!identity.ok) rec.identity_check.seen = descriptionIdentitySeen(html);')
  // the hold is the earlier line, with the earlier rule and reason, and no AI call
  expect(win).toContain('if (!identity.ok) { out.push({ ...base, ...rec, rule: identity.rule, reason: "The page does not prove the provider\'s current full institutional identity; no AI call was made." }); return }')
  expect(win.indexOf('rec.identity_check')).toBeLessThan(win.indexOf('if (!identity.ok) { out.push('))
  expect(win.indexOf('if (!identity.ok)')).toBeLessThan(win.indexOf('svc_provider_description_reserve_v1'))
  // the reader behaviour stamp is unchanged, so no hold is offered again because of this change
  expect((IX.match(/provider-description-source-guard-v4/g) || []).length).toBeGreaterThanOrEqual(1)
  expect(IX).not.toContain('provider-description-source-guard-v5')
  // the helper's constants are marked fixed (G2)
  for (const c of ['IDENTITY_SEEN_TEXT_MAX', 'IDENTITY_SEEN_H1_MAX', 'IDENTITY_SHELL_TEXT_MAX']) expect(DS).toMatch(new RegExp(`export const ${c} = \\d+;\\s+// fixed:`))
})

test('the record function keeps the key: it merges identity_check into checks.identity as a whole (proved by the PostgreSQL fixture tests/fixtures/pdesc-dd-ai/run.sh)', () => {
  const S = fs.readFileSync('tests/fixtures/pdesc-dd-ai/scenarios.sql', 'utf8'), E = fs.readFileSync('tests/fixtures/pdesc-dd-ai/expected.txt', 'utf8')
  expect(S).toContain("'seen', jsonb_build_object('title', 'Welcome'")
  expect(E).toMatch(/^seen_stored\|held\|provider_name_not_proved\|false\|provider_name_not_proved\|Welcome\|Study with us\|\[\]\|1200\|90\|true$/m)
  expect(E).toMatch(/^no_seen_stored\|held\|provider_name_conflict\|false\|provider_name_conflict$/m)
})
