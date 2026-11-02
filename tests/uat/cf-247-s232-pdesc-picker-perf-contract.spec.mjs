// Guards: Integration issue IQ-00055 (provider description picker within its time-out; v2.15.410 regression)
// Since v2.15.410 public.svc_provider_description_next hit the statement time-out (the page rule ran twice for every stored copy of a provider,
// and the stored copy was looked up again for every claimed row), so the provider-description-read job claimed nothing while the scheduler said
// "succeeded". The fix keeps the page chosen exactly as before and only removes work. The behaviour runs on isolated fixtures by
// tests/fixtures/pdesc-picker-perf/run.sh (scratch PostgreSQL; the live definitions are loaded from their live text and checked against the live
// md5s; the old definitions' choices are recorded before the migration and compared after it); this spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261103100000_cf247_pdesc_picker_perf.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/pdesc-picker-perf'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const data = fs.readFileSync(`${FX}/data.sql`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const edit = (sig) => { const a = m.indexOf(`select pg_temp.edit_once('${sig}'`); expect(a, sig).toBeGreaterThan(-1); return m.slice(a, m.indexOf(']]', a)) }
const after = (block) => block.split('$n$').filter((_, i) => i % 2 === 1).join('\n')
const count = (s, needle) => s.split(needle).length - 1

const MD5 = {
  'security.provider_description_stored_v1(uuid)': ['6ddc25869e9865c9aeebf11c819feee2', 'b4bef5671c9b2125b530df3abc9c502a'],
  'public.svc_provider_description_next(integer)': ['33d735da514a7d37e2815bbb0073af03', '5342ae3f9279f6c2ec0849ec4fe0fffd'],
}
const PAGE_RULE = 'f68e0130757c71ec8d8de24eb730da96'

test('both functions are edited only from their live md5 and checked after; the page rule is read, not edited', () => {
  for (const [sig, [b, a]] of Object.entries(MD5)) {
    const e = edit(sig)
    expect(e).toContain(`'${b}', '${a}'`)
    expect(m).toContain(`${b} -> ${a}`)
    expect(run).toContain(b)
  }
  expect(m).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(m).toContain("raise exception '% after the edit has md5 %, expected %'")
  expect(m).toContain(`<> '${PAGE_RULE}' then`)
  expect(m).not.toMatch(/create or replace function security\.provider_description_page_v1|edit_once\('security\.provider_description_page_v1/)
  expect(m).toMatch(/^-- Replaces: security\.provider_description_stored_v1, public\.svc_provider_description_next \(same names; md5-guarded edits\)$/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  // no new value: the prefilter reads the page rule's own lists
  expect(m).not.toMatch(/insert into pipeline\.platform_toolset_settings/)
})

test('the stored copy: a prefilter from the page rule lists, the page rule once per copy, the same order', () => {
  const s = after(edit('security.provider_description_stored_v1(uuid)'))
  expect(s).toContain("jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb))")
  expect(s).toContain("jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_prefixes'), '[]'::jsonb)) t where t <> ''")
  // the prefilter runs first and alone (offset 0), with the words escaped so a LIKE wildcard in a list is literal
  expect(count(s, "'%/' || replace(replace(replace(lower(t), '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%'")).toBe(2)
  expect(s).toContain('where s.provider_id = p_provider and lower(a.source_url) like any (w.ws)\n        offset 0)')
  expect(s).toContain("where f.storage_path is not null and f.source_url ~* '^https?://'")
  // then one of the first two path parts, read as the page rule reads the path, must be an About page name or start with an About prefix
  expect(s).toContain("regexp_match(z.p, '^/*([^/]+)(?:/+([^/]+))?') m")
  expect(s).toContain("from (select lower(coalesce(substring(f.source_url from '^https?://[^/?#]+(/[^?#]*)'), '')) p) z) g")
  // no longer than the rule allows (pdesc.about_max_segments, plus a language part)
  expect(s).toContain("security.pipeline_num_v1('pdesc.about_max_segments', 2) + 1 max_parts")
  expect(s).toContain("and regexp_count(g.p, '[^/]+') <= w.max_parts")
  expect(s).toContain('and (g.m[1] = any (w.names) or g.m[2] = any (w.names)')
  expect(count(s, 'security.provider_description_page_v1(')).toBe(1)
  expect(s).toContain("cross join lateral (select security.provider_description_page_v1(p_provider, c.source_url) pg offset 0) r")
  expect(s).toContain("order by (r.pg->>'main_host')::boolean desc, c.at desc, c.id")
  // the age limit is read once, not once per copy
  expect(count(s, "security.pipeline_num_v1('pdesc.source_max_age_days', 365)")).toBe(1)
  expect(s).toContain('and f.at > w.since')
})

test('the picker: the stored copy once per claimed row and never in the filter while direct acquisition is on; the page rule once per suggestion', () => {
  const e = edit('public.svc_provider_description_next(integer)')
  const n = after(e)
  expect(n).toContain("and case when security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 then true else security.provider_description_stored_v1(r.provider_id) is not null end")
  expect(n).toContain('from upd u cross join lateral (select security.provider_description_stored_v1(u.provider_id) stored_id offset 0) st')
  expect(n).toContain('from pipeline.evidence_artifacts a where a.id = st.stored_id),')
  expect(count(n, 'security.provider_description_page_v1(')).toBe(1)
  expect(n).toContain("cross join lateral (select security.provider_description_page_v1(u.provider_id, y.url) pg offset 0) g")
  expect(n).toContain("jsonb_agg(z.url order by (z.pg->>'main_host')::boolean desc, z.score desc, length(z.url))")
  // every edit applies exactly once to the live text
  expect(m).toContain("]], array[1, 1, 1, 1]);")
})

// The page rule (security.provider_description_page_v1) on the path: language part dropped, at most about_max_segments parts, the first part
// an About page name or starting with an About prefix. The prefilter must pass every address the rule passes.
const firstPartPasses = (url, patterns, prefixes, maxSegs) => {
  const mm = /^https?:\/\/[^/?#]+(\/[^?#]*)/.exec(url)
  const path = (mm ? mm[1] : '').toLowerCase()
  let segs = path.replace(/\/+$/, '').split('/').filter((x) => x !== '')
  if (segs.length > 0 && /^[a-z]{2}(-[a-z]{2})?$/.test(segs[0])) segs = segs.slice(1)
  if (segs.length === 0 || segs.length > maxSegs) return false
  const f = segs[0]
  return patterns.some((a) => f === a.toLowerCase()) || prefixes.some((x) => x !== '' && f.startsWith(x.toLowerCase()) && f.length > x.length)
}
const prefilter = (url, patterns, prefixes, maxSegs) => {
  const ws = [...patterns.map((a) => '/' + a.toLowerCase()), ...prefixes.filter((x) => x !== '').map((x) => '/' + x.toLowerCase())]
  if (!ws.some((w) => url.toLowerCase().includes(w))) return false
  // the first two path parts, as regexp_match(path, '^/*([^/]+)(?:/+([^/]+))?')
  const mm = /^https?:\/\/[^/?#]+(\/[^?#]*)/.exec(url)
  const g = /^\/*([^/]+)(?:\/+([^/]+))?/.exec((mm ? mm[1] : '').toLowerCase())
  if (!g) return false
  if ((mm ? mm[1] : '').split('/').filter((x) => x !== '').length > maxSegs + 1) return false
  const ok = (p) => p !== undefined && (patterns.some((a) => p === a.toLowerCase()) || prefixes.some((x) => x !== '' && p.startsWith(x.toLowerCase()) && p.length > x.length))
  return ok(g[1]) || ok(g[2])
}

test('the prefilter never skips an address the page rule passes (every combination of host, language part, name and tail)', () => {
  const lists = [
    [['about', 'about-us', 'overview', 'our-university', 'who-we-are', 'discover'], ['about-', 'about_']],
    [['About', 'OVERVIEW'], []], [[], ['about-']], [['about', ''], ['', 'ABOUT_']],
  ]
  const hosts = ['https://www.uni.edu.au', 'http://uni.edu.au', 'https://campus.uni.edu.au', 'https://uni.edu.au:443']
  const langs = ['', '/en', '/en-au', '/EN-AU', '/xyz', '//']
  const names = ['/study/x', '/about', '/About', '/about-us', '/about-uni', '/about_us', '/about-', '/aboutus', '/Overview/', '/who-we-are', '/news', '/our-university', '']
  const tails = ['', '/', '/history', '/a/b', '?q=1', '#top', '/About-Us', '/overview', '/about']
  let passed = 0
  for (const [patterns, prefixes] of lists) for (const h of hosts) for (const l of langs) for (const n of names) for (const t of tails) {
    const url = h + l + n + t
    for (const maxSegs of [1, 2, 4]) {
      if (firstPartPasses(url, patterns, prefixes, maxSegs)) { passed++; expect(prefilter(url, patterns, prefixes, maxSegs), url).toBe(true) }
    }
  }
  expect(passed).toBeGreaterThan(500)
  // and it does skip a deeper About word and a path longer than the rule allows (live: 735 Waikato copies under /about/calendar/...)
  expect(prefilter('https://www.waikato.ac.nz/study/subjects/x/overview', ['overview'], [], 2)).toBe(false)
  expect(prefilter('https://www.waikato.ac.nz/about/calendar/admission/criteria/', ['about'], [], 2)).toBe(false)
  expect(prefilter('https://www.waikato.ac.nz/en/about/history', ['about'], [], 2)).toBe(true)
})

test('the fixture run proves the same choice: old choices recorded before the migration, compared after, applied twice', () => {
  expect(run).toContain('MIG=supabase/migrations/20261103100000_cf247_pdesc_picker_perf.sql')
  expect(run).toContain('"$BEFORE" = "6ddc25869e9865c9aeebf11c819feee2 33d735da514a7d37e2815bbb0073af03"')
  for (const md5 of [PAGE_RULE, '000b9c49c899c6d33ec99501ae6194d4', '2af79164c5f92d0e6e5aeceb7783e7ee', '3f16959316449464576f5d77a951460a']) expect(run).toContain(md5)
  expect(run).toContain("grep -c 'already applied' | grep -qx 2")
  expect(run.indexOf('$FX/data.sql')).toBeLessThan(run.indexOf('-f $MIG'))
  expect(data).toContain('create table fx_old_stored')
  expect(data).toContain('create table fx_old_next')
  expect(fixtures).toContain("chose a different stored copy")
  expect(fixtures).toContain('the prefilter skipped % copies the page rule passes')
  expect(fixtures).toContain("the picker items differ")
  for (const f of fs.readdirSync(`${FX}/live-before`)) expect(fs.readFileSync(`${FX}/live-before/${f}`, 'utf8')).toMatch(/^CREATE OR REPLACE FUNCTION /)
})
