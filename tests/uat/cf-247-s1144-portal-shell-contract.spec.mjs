// Guards: StudySearch Portal lane (Platform Admin 25 Nov 2026 16:44, S1-API-Frontend-Delivery): the shell menu follows the role, the "Study in" bar and every limit are read from the database, and a raw database message never reaches a screen (s930 for lookups, G2 for limits).
// CF-247 S1144. Viewer (rank 1) browses Courses, Providers and Scholarships; Counsellor (rank 2 and above) also has Saved courses.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'
import { toApiError } from '../../portal/src/lib/apiErrors.js'

const read = (p) => fs.readFileSync(p, 'utf8')
const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]))
const src = 'portal/src'
const screens = walk(src).filter((f) => /\.(jsx|js)$/.test(f))

test('the menu lists the five Release 1 screens and Saved courses is for Counsellors only', () => {
  const shell = read(`${src}/screens/Shell.jsx`)
  for (const label of ['Dashboard', 'Courses', 'Universities & Providers', 'Scholarships', 'Saved courses']) expect(shell).toContain(`label: '${label}'`)
  expect(shell).toMatch(/Saved courses', counsellor: true/)
  expect(shell).toMatch(/n\.counsellor \|\| access\.kind === 'counsellor'/)
  expect(shell).toMatch(/Saved courses are for Counsellors/)
})

test('the "Study in" bar and the market list come from the live lookups, with no destination written into a screen', () => {
  const portal = read(`${src}/lib/portal.jsx`)
  expect(portal).toContain("rpc('portal_lookups_v1')")
  expect(portal).toContain("rpc('portal_settings_v1')")
  const ui = read(`${src}/components/ui.jsx`)
  expect(ui).toMatch(/destinations\.map/)
  for (const f of screens.filter((x) => !x.endsWith('copy.js'))) {
    expect(read(f), `${f} must not carry a destination name`).not.toMatch(/['"`](Australia|New Zealand|Canada)['"`]/)
  }
})

test('a raw database message never reaches a screen', () => {
  expect(toApiError({ code: 'PGRST202', message: 'Could not find the function public.x in the schema cache' }).kind).toBe('missing')
  expect(toApiError({ code: '42883', message: 'function does not exist' }).kind).toBe('missing')
  expect(toApiError({ code: '42501', message: 'permission denied for schema security' }).kind).toBe('access')
  const limit = toApiError({ code: '22023', message: 'SAVED_LIMIT: you can save up to 50 courses; remove one first' })
  expect(limit.kind).toBe('limit')
  expect(limit.message).toBe('you can save up to 50 courses; remove one first')
  const odd = toApiError({ code: 'XX000', message: 'relation "catalogue.courses" does not exist at character 12' })
  expect(odd.kind).toBe('failed')
  expect(odd.message).not.toMatch(/catalogue|relation/)
  expect(toApiError({ message: 'Failed to fetch' }).kind).toBe('network')
})

test('the portal holds no secret key and talks to the database only through its own functions', () => {
  for (const f of screens) {
    const t = read(f)
    expect(t, `${f} must not read tables directly`).not.toMatch(/\.from\(\s*['"`]/)
    for (const m of t.matchAll(/rpc\(\s*['"`]([a-z0-9_]+)['"`]/g)) expect(m[1], `${f} calls ${m[1]}`).toMatch(/^(portal_[a-z_]+_v1|admin_read)$/)
  }
})
