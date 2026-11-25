// Pure helpers for the build-time Supabase values (kept apart from supabase.js so a spec can import them without Vite).
export const cleanEnv = (v) => String(v ?? '').trim().replace(/^["'`]+|["'`]+$/g, '').trim()

// What kind of key was built in: only its kind and length are ever shown, never the value.
export function describeKey(key) {
  if (!key) return { kind: 'missing', length: 0 }
  if (key.startsWith('sb_publishable_')) return { kind: 'publishable', length: key.length }
  if (key.startsWith('sb_secret_')) return { kind: 'secret', length: key.length }
  const parts = key.split('.')
  if (parts.length === 3) {
    try {
      const role = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/'))).role
      return { kind: role === 'anon' ? 'legacy-anon' : 'secret', length: key.length }
    } catch { return { kind: 'unrecognised', length: key.length } }
  }
  return { kind: 'unrecognised', length: key.length }
}
