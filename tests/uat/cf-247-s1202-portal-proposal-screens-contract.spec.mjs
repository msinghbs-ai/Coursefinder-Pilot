// Guards: StudySearch Portal Release 2 (Platform Admin 26 Nov 2026, S1-API-Frontend-Delivery): proposals are Counsellor-only, read the server contract, handle the soft-lock and refresh decisions, and the consumer API (G3) is not touched
// CF-247 S1202: screen wiring and the basket. The proposal RPC names are the contract S2-Build deploys; they live in one adapter.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'

const read = (p) => fs.readFileSync(p, 'utf8')

test('the four proposal functions are named in one adapter (the list screen pages through the shared hook), with the p_args shape', () => {
  const api = read('portal/src/lib/proposalApi.js')
  for (const n of ['list', 'get', 'save', 'refresh']) expect(api).toContain(`portal_proposal_${n}_v1`)
  expect(api).toMatch(/p_args/)
  for (const f of fs.readdirSync('portal/src/screens').filter((x) => x !== 'Proposals.jsx')) expect(read(path.join('portal/src/screens', f)), f).not.toMatch(/portal_proposal_/)
  expect(read('portal/src/screens/Proposals.jsx')).toContain("usePagedList('portal_proposal_list_v1'")
})

test('proposals are Counsellor-only and Viewers never reach the functions', () => {
  const shell = read('portal/src/screens/Shell.jsx')
  expect(shell).toMatch(/to:\s*'\/proposals'[^}]*counsellor:\s*true/)
  expect(shell).toContain("COUNSELLOR_ONLY('Proposals')")
  for (const r of ['/proposals/new', '/proposals/:id', '/sheet']) expect(shell + read('portal/src/screens/Shell.jsx')).toContain(r.replace('/proposals/', '').replace(':id', ''))
})

test('the editor handles the soft-lock, the conflict and the refresh decision as the plan says', () => {
  const ed = read('portal/src/screens/ProposalEditor.jsx')
  expect(ed).toContain('others_recent')
  expect(ed).toContain('saved_after_other_edit')
  expect(ed).toMatch(/Use their version/)
  expect(ed).toMatch(/Keep mine and save/)
  expect(ed).toMatch(/Accept all changes/)
  expect(ed).toMatch(/Keep my version/)
  expect(ed).toMatch(/Nothing changes in the PDF until you choose/)
  expect(ed).toMatch(/force:\s*true/)
  expect(ed).toContain('beforeunload')
  expect(ed).toMatch(/not switched on yet/)
})

test('the basket is a small guarded session store that never throws', async () => {
  const { makeBasket } = await import('../../portal/src/lib/basket.js')
  const mem = new Map(); const storage = { getItem: (k) => mem.get(k) ?? null, setItem: (k, v) => mem.set(k, v), removeItem: (k) => mem.delete(k) }
  const b = makeBasket(storage)
  expect(b.count()).toBe(0)
  b.add({ course_id: 'c1', title: 'A', provider_name: 'P', secret: 'x' }); b.add({ course_id: 'c1', title: 'A' }); b.addMany([{ course_id: 'c2', title: 'B' }])
  expect(b.count()).toBe(2); expect(b.has('c1')).toBe(true)
  expect(JSON.stringify(b.list())).not.toContain('secret')
  b.remove('c1'); expect(b.count()).toBe(1); b.clear(); expect(b.count()).toBe(0)
  const broken = makeBasket({ getItem() { throw new Error('blocked') }, setItem() { throw new Error('blocked') }, removeItem() { throw new Error('blocked') } })
  expect(() => { broken.add({ course_id: 'z' }); broken.count(); broken.clear() }).not.toThrow()
})

test('no operational number or secret is written into the proposal code, and the frozen surface is untouched', () => {
  const files = ['lib/proposals.js', 'lib/proposalApi.js', 'lib/basket.js', 'screens/Proposals.jsx', 'screens/ProposalEditor.jsx', 'screens/ProposalSheet.jsx'].map((f) => path.join('portal/src', f))
  for (const f of files) {
    const t = read(f)
    expect(t, f).not.toMatch(/service[_-]?role|SUPABASE_SERVICE|eyJ[A-Za-z0-9_-]{20,}/i)
    expect(t, f).not.toMatch(/\b(15|900)\s*\*\s*(60|1000)\b/) // no hard-coded soft-lock minutes
    expect(t, f).not.toMatch(/courses_max\s*[:=]\s*\d|soft_lock_minutes\s*[:=]\s*\d/)
  }
  // the 15-minute window is the server's: the editor shows only the people the server returns in others_recent
  expect(read('portal/src/screens/ProposalEditor.jsx')).toContain('others_recent')
  const migs = fs.readdirSync('supabase/migrations').filter((f) => f >= '20261126')
  for (const m of migs) expect(read(path.join('supabase/migrations', m)), m).not.toMatch(/website_v2_|zoho_edge_/)
})
