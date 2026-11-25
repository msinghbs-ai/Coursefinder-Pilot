// Guards: StudySearch Portal lane (Platform Admin 25 Nov 2026, S1-API-Frontend-Delivery): separate Worker on *.workers.dev, role guards, public keys only
// CF-247 S1141: the portal is its own Worker in portal/, beside the Admin Worker. It must not change the Admin Worker's configuration,
// must not hold a service-role key, and must keep Counsellor and Viewer access to the database's own role rank.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'

const read = (p) => fs.readFileSync(p, 'utf8')
const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.name === 'node_modules' || e.name === 'dist' ? [] : e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]))
const strip = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '')

test('the portal is a separate Worker and the Admin Worker is untouched', () => {
  const portal = JSON.parse(strip(read('portal/wrangler.jsonc')))
  const admin = JSON.parse(strip(read('wrangler.jsonc')))
  expect(portal.name).toBe('studysearch-portal')
  expect(admin.name).toBe('coursefinder-pilot')
  expect(portal.name).not.toBe(admin.name)
  expect(portal.assets.not_found_handling).toBe('single-page-application')
  expect(admin.assets.directory).toBe('./dist')
  expect(fs.existsSync('portal/package-lock.json'), 'never create a lockfile').toBe(false)
  expect(fs.existsSync('package-lock.json')).toBe(false)
})

test('the portal never holds a service-role key and reads only the public build variables', () => {
  const files = walk('portal').filter((f) => /\.(jsx?|html|jsonc?|css)$/.test(f) && !f.endsWith('package.json'))
  for (const f of files) {
    const text = read(f)
    expect(text, f).not.toMatch(/service[_-]?role/i)
    expect(text, f).not.toMatch(/SUPABASE_SERVICE/i)
    expect(text, f).not.toMatch(/eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/)
  }
  const client = read('portal/src/lib/supabase.js')
  expect(client).toContain('VITE_SUPABASE_URL')
  expect(client).toContain('VITE_SUPABASE_PUBLISHABLE_KEY')
})

test('access follows the database role rank: Viewer 1, Counsellor 2 and above, nothing else', async () => {
  const { portalAccess, VIEWER_RANK, COUNSELLOR_RANK } = await import('../../portal/src/lib/roles.js')
  expect([VIEWER_RANK, COUNSELLOR_RANK]).toEqual([1, 2])
  expect(portalAccess(null).allowed).toBe(false)
  expect(portalAccess({ authenticated: false, role_rank: 6 }).allowed).toBe(false)
  expect(portalAccess({ authenticated: true, role: 'unassigned', role_rank: 0 }).allowed).toBe(false)
  expect(portalAccess({ authenticated: true, role: 'viewer', role_rank: 1 })).toMatchObject({ allowed: true, kind: 'viewer' })
  expect(portalAccess({ authenticated: true, role: 'counsellor', role_rank: 2 })).toMatchObject({ allowed: true, kind: 'counsellor' })
  expect(portalAccess({ authenticated: true, role: 'platform_admin', role_rank: 6 })).toMatchObject({ allowed: true, kind: 'counsellor' })
})

test('the portal sends the same browser security headers as Admin and no operational number is written into it', () => {
  const headers = read('portal/public/_headers')
  for (const h of ['Content-Security-Policy', 'Strict-Transport-Security', 'X-Frame-Options: DENY', 'X-Content-Type-Options: nosniff']) expect(headers).toContain(h)
  expect(headers).toContain("frame-ancestors 'none'")
  expect(headers).toContain('https://fxcwkweaxjtknorudmwp.supabase.co')
  expect(headers).not.toContain('coursefinder-demo')
  const copy = read('portal/src/copy.js')
  expect(copy, 'example prompts are wording only: no provider, fee or intake figure from the platform').not.toMatch(/A\$\s?\d{2},\d{3}/)
})
