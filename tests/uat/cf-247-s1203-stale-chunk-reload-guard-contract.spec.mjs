// Guards: Platform Admin via Atlas 26 Nov 2026 08:56: a browser tab left open across a Worker deploy recovers by reloading once (never in a loop); index.html is always re-checked and hashed assets are immutable; Admin and portal share one guard
// CF-247 s1203: the stale-chunk guard (src/lib/chunkReload.js, copied to portal/src/lib/chunkReload.js). Pure code with injected storage, clock and reload, so no browser is needed.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = (p) => fs.readFileSync(p, 'utf8')
const G = () => import('../../src/lib/chunkReload.js')
const memory = () => { const m = new Map(); return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), m } }
const clock = (t0 = 1_000_000) => { let t = t0; const now = () => t; now.advance = (ms) => { t += ms }; return now }
const env = (over = {}) => { const reloads = []; const now = clock(); return { storage: memory(), now, reload: () => reloads.push(1), reloads, ...over } }

test('only a missing hashed file counts as a stale chunk, never an ordinary network error', async () => {
  const { isStaleChunkError } = await G()
  for (const msg of [
    'Failed to fetch dynamically imported module: https://x.workers.dev/assets/access-roles-entry-abc123.js', // Chrome, Edge
    'error loading dynamically imported module: https://x/assets/a.js', // Firefox
    'Importing a module script failed.', // Safari
    'Unable to preload CSS for /assets/a-1.css',
  ]) expect(isStaleChunkError(new TypeError(msg)), msg).toBe(true)
  expect(isStaleChunkError('Failed to fetch dynamically imported module: /assets/a.js')).toBe(true)
  for (const msg of ['Failed to fetch', 'NetworkError when attempting to fetch resource.', 'Load failed', 'JWT expired', '']) expect(isStaleChunkError(new Error(msg)), msg).toBe(false)
  expect(isStaleChunkError(undefined)).toBe(false)
  expect(isStaleChunkError(null)).toBe(false)
})

test('the first stale chunk reloads once and records the time; a second inside the window does not (no reload loop)', async () => {
  const { reloadOnceForStaleChunk, CHUNK_RELOAD_KEY, CHUNK_RELOAD_WINDOW_MS } = await G()
  const e = env(); const err = new Error('Failed to fetch dynamically imported module: /assets/x.js')
  expect(reloadOnceForStaleChunk(err, e)).toBe(true)
  expect(e.reloads.length).toBe(1)
  expect(e.storage.m.get(CHUNK_RELOAD_KEY)).toBe(String(e.now()))
  e.now.advance(CHUNK_RELOAD_WINDOW_MS - 1)
  expect(reloadOnceForStaleChunk(err, e)).toBe(false) // still failing after the reload: a real outage, leave it to the screen's own error handling
  expect(e.reloads.length).toBe(1)
  // many failures in a row still cause one reload only
  for (let i = 0; i < 20; i += 1) reloadOnceForStaleChunk(err, e)
  expect(e.reloads.length).toBe(1)
})

test('a tab that is stale again after a later deploy recovers again (the flag is not permanent)', async () => {
  const { reloadOnceForStaleChunk, CHUNK_RELOAD_WINDOW_MS } = await G()
  const e = env(); const err = new Error('Failed to fetch dynamically imported module: /assets/y.js')
  expect(reloadOnceForStaleChunk(err, e)).toBe(true)
  e.now.advance(CHUNK_RELOAD_WINDOW_MS + 1)
  expect(reloadOnceForStaleChunk(err, e)).toBe(true)
  expect(e.reloads.length).toBe(2)
})

test('it never reloads when the time cannot be recorded, or for a different kind of error', async () => {
  const { reloadOnceForStaleChunk } = await G()
  const err = new Error('Failed to fetch dynamically imported module: /assets/z.js')
  const blocked = env({ storage: { getItem: () => null, setItem: () => { throw new Error('blocked') } } })
  expect(reloadOnceForStaleChunk(err, blocked)).toBe(false)
  const unreadable = env({ storage: { getItem: () => { throw new Error('blocked') }, setItem() {} } })
  expect(reloadOnceForStaleChunk(err, unreadable)).toBe(false)
  const none = env({ storage: null })
  expect(reloadOnceForStaleChunk(err, none)).toBe(false)
  const other = env()
  expect(reloadOnceForStaleChunk(new Error('Failed to fetch'), other)).toBe(false)
  expect([blocked, unreadable, none, other].flatMap((x) => x.reloads)).toEqual([])
})

test('lazyLoader returns the module, picks a named export, reloads once on a stale chunk and passes every other error on', async () => {
  const { lazyLoader } = await G()
  expect(await lazyLoader(async () => ({ default: 'D', Named: 'N' }))).toEqual({ default: 'D' })
  expect(await lazyLoader(async () => ({ default: 'D', Named: 'N' }), 'Named')).toEqual({ default: 'N' })
  const stale = () => Promise.reject(new TypeError('Failed to fetch dynamically imported module: /assets/q.js'))
  const e = env()
  const settled = await Promise.race([lazyLoader(stale, 'default', e).then(() => 'settled', () => 'settled'), new Promise((r) => setTimeout(() => r('pending'), 50))])
  expect(settled).toBe('pending') // the page is reloading, so the lazy screen never draws an error first
  expect(e.reloads.length).toBe(1)
  await expect(lazyLoader(stale, 'default', e)).rejects.toThrow(/dynamically imported module/) // second time: the error reaches the boundary
  expect(e.reloads.length).toBe(1)
  await expect(lazyLoader(() => Promise.reject(new Error('boom')), 'default', env())).rejects.toThrow('boom')
})

test('the global listeners handle a preload error and a rejected import, once, and leave network errors alone', async () => {
  const { installChunkReloadGuard } = await G()
  const listeners = {}; const win = { addEventListener: (n, f) => { listeners[n] = f } }
  const e = env()
  expect(installChunkReloadGuard(win, e)).toBe(true)
  expect(installChunkReloadGuard(win, e)).toBe(false) // installed once
  let prevented = 0; const ev = (x) => ({ ...x, preventDefault: () => { prevented += 1 } })
  listeners['unhandledrejection'](ev({ reason: new Error('Failed to fetch') }))
  expect(e.reloads.length).toBe(0); expect(prevented).toBe(0)
  listeners['vite:preloadError'](ev({ payload: new Error('Unable to preload CSS for /assets/a.css') }))
  expect(e.reloads.length).toBe(1); expect(prevented).toBe(1)
  listeners['unhandledrejection'](ev({ reason: new TypeError('Failed to fetch dynamically imported module: /assets/a.js') }))
  expect(e.reloads.length).toBe(1) // inside the window: no second reload
  expect(installChunkReloadGuard(null)).toBe(false)
})

test('every lazy screen in the Admin app goes through the guard, and both entries install it', () => {
  const sources = ['src/mature-main.jsx', 'src/AiModelsServices.jsx', 'src/ui-v1/CounsellorApp.jsx'].filter((f) => fs.existsSync(f)).map((f) => [f, read(f)])
  for (const [f, text] of sources) expect(text, f).not.toMatch(/React\.lazy\(\(\)\s*=>\s*import\(/)
  const main = read('src/mature-main.jsx')
  expect(main).toContain("from'./lib/chunkReload.js'")
  expect(main).toMatch(/function lazyPage\(load,name='default'\)\{return React\.lazy\(\(\)=>lazyLoader\(load,name\)\)\}/)
  expect(main).toMatch(/installChunkReloadGuard\(\)[^\n]*\ncreateRoot\(/)
  expect(main).toContain("const CounsellorApp=lazyPage(()=>import('./ui-v1/CounsellorApp.jsx'))")
  const ai = read('src/AiModelsServices.jsx')
  expect(ai).toContain("React.lazy(() => lazyLoader(() => import('./ProviderDescriptionPrompt')))")
  expect(ai).toContain("React.lazy(() => lazyLoader(() => import('./ScholarshipExtraction')))")
  const portal = read('portal/src/main.jsx')
  expect(portal).toContain("import { installChunkReloadGuard } from './lib/chunkReload.js'")
  expect(portal.indexOf('installChunkReloadGuard()')).toBeLessThan(portal.indexOf('createRoot('))
})

test('the portal copy is the same file as the Admin copy', () => {
  expect(read('portal/src/lib/chunkReload.js')).toBe(read('src/lib/chunkReload.js'))
  expect(read('src/lib/chunkReload.js')).not.toMatch(/^\s*import\s/m) // no imports, so it cannot itself fail to load
})

test('index.html is always re-checked and hashed assets are immutable, in both apps, set in the repository and not the dashboard', () => {
  for (const f of ['public/_headers', 'portal/public/_headers']) {
    const text = read(f)
    const rule = (path) => { const m = text.match(new RegExp('^' + path.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '\\n((?:[ \\t]+.*\\n?)+)', 'm')); return m ? m[1] : '' }
    expect(rule('/'), f).toMatch(/Cache-Control:\s*no-cache, must-revalidate/)
    expect(rule('/index.html'), f).toMatch(/Cache-Control:\s*no-cache, must-revalidate/)
    expect(rule('/assets/*'), f).toMatch(/Cache-Control:\s*public, max-age=31536000, immutable/)
    // the catch-all security block must not set Cache-Control, or it would merge with the rules above
    expect(rule('/*'), f).not.toMatch(/Cache-Control/i)
    expect(rule('/*'), f).toMatch(/Content-Security-Policy/) // security headers unchanged
  }
  for (const f of ['wrangler.jsonc', 'portal/wrangler.jsonc']) expect(read(f), f).not.toMatch(/headers|cache/i)
})
