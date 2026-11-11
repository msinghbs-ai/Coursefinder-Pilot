// Guards: F-AER.04 source management in the existing AER workspace (Platform Admin decision D3, 11 Nov 2026) and the D1 quote proof (the published minimum is in the row's quote)
// Attach an address or PDF on Catalogue › Entry requirements › Sources, reads and holds: checked first (provider's own website host, classes, reuse, existing reader), attached by a
// Platform Admin with a reason into the one registry, read once by the existing reader, every read to Layer 4, an uploaded copy never machine-admitted. No new tab, dashboard or registry.
// Behaviour is proven on isolated PostgreSQL by tests/fixtures/aer-source-management/run.sh.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = (f) => fs.readFileSync(f, 'utf8')
const sqlCode = (f) => read(f).split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const D3 = sqlCode('supabase/migrations/20261112113700_cf247_aer_source_management.sql')
const QP = sqlCode('supabase/migrations/20261112110700_cf247_aer_matrix_machine_quote_proof.sql')

test('D1 quote proof: a row whose quote does not carry its published minimum stays with a person, and validation replays the same rule', () => {
  expect(QP).toContain("when not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value) then 'minimum_not_in_quote' end why")
  expect(QP).toContain("when not security.aer_quote_has_value_v1(q.quote, q.min_grade, q.min_value) then 'minimum_not_in_quote' end")
  expect(QP).toContain('or not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value)))')
  expect(QP).not.toMatch(/matrix_machine_mode', to_jsonb\(2\)|set value = to_jsonb\(2\)/)
})

test('D3 database: ownership on the provider\'s own host, classes, reuse, Platform Admin and a reason; the one registry; an upload never machine-admitted', () => {
  expect(D3).toContain("if v_sh is null or not (v_sh = v_ph or v_sh like '%.' || v_ph) then")
  expect(D3).toContain("array['country_table', 'international_qualification', 'national_qualification', 'undergraduate', 'postgraduate', 'course_specific']")
  expect(D3).toContain("if v_rank < 6 then raise exception 'Platform Admin required to attach a source'")
  expect(D3).toContain("if length(v_reason) < 5 then raise exception 'reason required'")
  expect(D3).toContain("insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via, status)")
  expect(D3).not.toMatch(/create table (if not exists )?pipeline\.entry_matrix_sources\b/)
  expect(D3).toContain("return jsonb_build_object('ok', false, 'rule', 'uploaded_copy'")
  expect(D3).toContain("revoke all on function public.svc_aer_source_upload_record(bigint, text, text) from public, anon, authenticated;")
  expect(D3).toContain('v_q := security.entry_matrix_enqueue_v1();')
})

test('D3 upload: checked under the person\'s sign-in before anything is stored, where the fetch step stores PDFs', () => {
  const fn = read('supabase/functions/aer-source-upload/index.ts')
  expect(fn.indexOf('user.rpc("admin_aer_source"')).toBeGreaterThan(0)
  expect(fn.indexOf('user.rpc("admin_aer_source"')).toBeLessThan(fn.indexOf('svc.storage.from("evidence").upload('))
  expect(fn).toContain('svc.rpc("svc_aer_source_upload_record"')
  expect(JSON.parse(read('.github/edge-functions.json')).functions['aer-source-upload']).toBe(true)
})

test('D3 screen: inside Sources, reads and holds and linked from the provider; no new tab or dashboard', () => {
  const nav = read('src/nav-map.js'), ws = read('src/AerWorkspace.jsx'), er = read('src/EntryRequirements.jsx')
  const entry = nav.slice(nav.indexOf("entry: { label: 'Entry requirements'"), nav.indexOf('rankings: {'))
  expect((entry.match(/\{ key: '/g) || []).length).toBe(4)
  const sv = ws.slice(ws.indexOf('export function SourcesView'), ws.indexOf('// ----------------------------------------------------------------------------------------------- Course-level reading'))
  expect(sv).toContain('<SourceAttach providers={o.providers||[]} providerId={f.provider_id} onAttached={()=>setRefresh(r=>r+1)}/>')
  expect(sv).toContain('<SourceDiscovery/>')
  expect(sv).toContain('const meta=useSourceMeta(rows.map(s=>s.id))')
  expect(er).toContain("href={hrefFor('entry','sources',{provider:providerId})} data-entry-sources-link>Attach or manage sources</a>")
  expect(fs.readdirSync('supabase/migrations').filter((f) => /^2026111211(07|37)00_/.test(f)).sort()).toEqual(['20261112110700_cf247_aer_matrix_machine_quote_proof.sql', '20261112113700_cf247_aer_source_management.sql'])
})
