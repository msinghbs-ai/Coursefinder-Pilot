import { createClient } from '@supabase/supabase-js'
import { cleanEnv, describeKey } from './keyInfo.js'

// Public values, set as Cloudflare build variables. The portal holds only these two public values and no privileged key.
// Pasted values often carry a trailing space, a new line or quote marks; none of those belong in a header, so they are removed (keyInfo.js).
const clean = cleanEnv

export const supabaseUrl = clean(import.meta.env.VITE_SUPABASE_URL).replace(/\/+$/, '')
const rawKey = clean(import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || import.meta.env.VITE_SUPABASE_ANON_KEY)

export const keyInfo = describeKey(rawKey)
// A secret key must never run in a browser: it is refused here rather than sent.
export const configured = Boolean(supabaseUrl && rawKey) && keyInfo.kind !== 'secret'

export const supabase = createClient(supabaseUrl || 'http://localhost', configured ? rawKey : 'missing', {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
})

// The same read the Admin app uses for who is signed in and their role rank (public.admin_read 'context' -> public.ui_context()).
// Read only; roles are managed in Admin (Users and Roles), never here.
export async function readContext() {
  const { data, error } = await supabase.rpc('admin_read', { p_operation: 'context', p_args: {} })
  if (error) throw error
  return data
}
