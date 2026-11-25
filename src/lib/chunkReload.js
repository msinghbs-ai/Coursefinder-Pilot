// CF-247 s1203 (Platform Admin via Atlas, 26 Nov 2026 08:56): a browser tab left open across a Worker deploy still holds the old index.html, whose
// hashed /assets/* files no longer exist. The next lazy screen then fails with "Failed to fetch dynamically imported module". This module reloads
// the page ONCE so the tab picks up the new index.html, instead of leaving the workspace broken until the person refreshes by hand.
//
// Loop protection: the time of the last guarded reload is kept in sessionStorage. A second stale-chunk error inside the window below is NOT answered
// with another reload (the error reaches the screen's own error handling), so a real outage can never reload the page in a loop. A tab that is
// stale again after a later deploy is outside the window and recovers again. If the time cannot be recorded (storage blocked) it never reloads.
//
// The portal keeps an identical copy at portal/src/lib/chunkReload.js (spec s1203 fails if they differ). No imports, no settings, no network.
export const CHUNK_RELOAD_KEY = 'cf-chunk-reload'
// fixed: technical loop-guard window (one reload per minute at most), not an operational setting
export const CHUNK_RELOAD_WINDOW_MS = 60 * 1000

// Messages the three engines give when a hashed file is missing: Chrome and Edge, Firefox, Safari. A plain "Failed to fetch" is NOT here: that is
// an ordinary network error (offline, a database call), and reloading for it would be wrong.
const STALE_CHUNK = /Failed to fetch dynamically imported module|error loading dynamically imported module|Importing a module script failed|Unable to preload CSS|Failed to load module script/i

export function isStaleChunkError(error) {
  const text = typeof error === 'string' ? error : String(error?.message ?? error ?? '')
  return STALE_CHUNK.test(text)
}

function defaultStorage() {
  try { return typeof sessionStorage !== 'undefined' ? sessionStorage : null } catch { return null }
}

// True when it reloaded the page (the caller then stops and waits); false when the error is not a stale chunk or a reload already happened a moment ago.
export function reloadOnceForStaleChunk(error, env = {}) {
  if (!isStaleChunkError(error)) return false
  const storage = env.storage === undefined ? defaultStorage() : env.storage
  const now = (env.now || Date.now)()
  let last = 0
  try { last = Number(storage?.getItem(CHUNK_RELOAD_KEY)) || 0 } catch { return false }
  if (last && now - last < CHUNK_RELOAD_WINDOW_MS) return false
  try { storage.setItem(CHUNK_RELOAD_KEY, String(now)) } catch { return false }
  ;(env.reload || (() => window.location.reload()))()
  return true
}

// Loads one lazy module. On a stale chunk it reloads once and never settles (the page is going away); otherwise the error is passed on unchanged.
export function lazyLoader(load, name = 'default', env) {
  return load().then((m) => ({ default: m[name] })).catch((error) => {
    if (reloadOnceForStaleChunk(error, env)) return new Promise(() => {})
    throw error
  })
}

// Catches the same failure when it is not inside a lazy screen: Vite's preload helper (vite:preloadError) and a stray rejected import().
export function installChunkReloadGuard(win = typeof window !== 'undefined' ? window : null, env) {
  if (!win || win.__chunkReloadGuard) return false
  win.__chunkReloadGuard = true
  win.addEventListener('vite:preloadError', (event) => { if (reloadOnceForStaleChunk(event?.payload ?? event, env)) event.preventDefault?.() })
  win.addEventListener('unhandledrejection', (event) => { if (reloadOnceForStaleChunk(event?.reason, env)) event.preventDefault?.() })
  return true
}
